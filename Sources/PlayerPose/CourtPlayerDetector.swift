import CoreFoundation
import CoreGraphics
import CourtFit
import CoreVideo
import Foundation

/// 1 フレームの、選手の検出の結果。
public struct CourtPlayersOutcome: Equatable, Sendable {
    /// フレームの時刻（秒）。
    public var time: TimeInterval
    /// コートにいる選手（番号の順）。
    public var players: [CourtPlayer]
    /// 見つかった人の全員の骨格（選手に選ばなかった観客や審判も入る。確認用）。
    public var poses: [BodyPose]
    /// 検出をかけた範囲（確認用）。画面の全体にかけたときは空。
    public var regions: [CGRect]
    /// 処理時間（ms）。
    public var durationMilliseconds: Double
    /// 映像の大きさ（画素）。
    public var imageSize: CGSize
    /// 骨格の検出が動かなかったときの理由。動いたら nil（選手がいないだけのときも nil）。
    public var failure: String?
}

/// フレームから骨格を検出し、コートにいる選手を選んで、同じ人に同じ番号を付け続ける。
///
/// Vision の骨格検出は、映像を小さくしてから見るので、小さく写った選手を取りこぼす。そこで、範囲を絞って検出をかける。
/// - 追えている選手は、そのまわりだけを拡大して検出する。
/// - 選手が足りないとき（と、`searchInterval` 秒ごと）は、広く探す。コートの矩形を `setCourt(_:)` で渡されていれば、
///   奥の半面と手前の半面に分けた範囲、無ければ画面を格子に分けた範囲。
///
/// コートが分かっていれば、足元がコートの中かその近くにある人だけを選手にする。分からなければ、大きく写っている人から選手にする。
///
/// 追跡を覚える。映像の解析のキューから呼ばれるので、ロックで守る。
public final class CourtPlayerDetector: @unchecked Sendable {
    /// 検出の範囲の作り方。
    public let regions: PoseRegions
    /// コートが見つからなくなってから、前のコートを使い続ける時間（秒）。
    public let courtHoldSeconds: TimeInterval
    /// 選手が全員追えているあいだも、この時間（秒）ごとに広く探す（入れ替わった選手や、取り違えを直すため）。
    public let searchInterval: TimeInterval
    /// 追う選手の数の上限。
    public let maximumPlayers: Int

    private let lock = NSLock()
    private var tracker: CourtPlayerTracker
    private var court: CourtPlane?
    /// 最後にコートを渡された、フレームの時刻。
    private var courtTime: TimeInterval?
    private var hasFreshCourt = false
    /// 最後に広く探した、フレームの時刻。
    private var lastSearchTime: TimeInterval?

    public init(
        maximumPlayers: Int = 4, regions: PoseRegions = PoseRegions(), courtHoldSeconds: TimeInterval = 1,
        searchInterval: TimeInterval = 0.5
    ) {
        self.maximumPlayers = maximumPlayers
        self.regions = regions
        self.courtHoldSeconds = courtHoldSeconds
        self.searchInterval = searchInterval
        tracker = CourtPlayerTracker(maximumPlayers: maximumPlayers)
    }

    /// コートの矩形の四隅（正規化座標、左下が原点。奥の左、奥の右、手前の右、手前の左の順）を渡す。
    /// 見つからなかったフレームでは nil を渡す（`courtHoldSeconds` のあいだは、前のコートを使い続ける）。
    /// 四隅のどれかが、映像からこれ（映像の大きさに対する割合）より外にあるコートは、検出の誤りとみて使わない。
    public static let courtLimit: CGFloat = 0.2

    public func setCourt(_ corners: [CGPoint]?) {
        // 四隅が映像から大きく外れたコートは、検出の誤り（手前の角が画面のはるか外に出る）が多い。
        // 誤ったコートで選手を絞ると、本物の選手を捨てるので、コートが無いものとして扱う。
        let range = -CourtPlayerDetector.courtLimit...(1 + CourtPlayerDetector.courtLimit)
        let corners = corners.flatMap { points in
            points.allSatisfy { range.contains($0.x) && range.contains($0.y) } ? points : nil
        }
        lock.withLock {
            if let plane = corners.flatMap({ CourtPlane(corners: $0) }) {
                court = plane
                hasFreshCourt = true
            } else {
                hasFreshCourt = false
            }
        }
    }

    public func detect(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> CourtPlayersOutcome {
        let started = CFAbsoluteTimeGetCurrent()
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let aspect = imageSize.height > 0 ? Double(imageSize.width / imageSize.height) : 1
        let (plane, tiles) = lock.withLock { () -> (CourtPlane?, [CGRect]) in
            let plane = currentCourt(at: time)
            return (plane, searchTiles(court: plane, aspect: aspect, time: time))
        }
        let detector = VisionBodyPoseDetector(regions: tiles)
        let found = detector.detect(in: pixelBuffer, at: time)
        var poses = found.poses
        // 追っている選手が見つからなかったら、そのまわりを、広さを変えてもう一度探す。
        let retries = lock.withLock { tracker.missingRegions(poses: poses, court: plane, time: time, imageSize: imageSize) }
        if !retries.isEmpty {
            poses = PoseDeduplicator().merge(
                poses + VisionBodyPoseDetector(regions: retries).detect(in: pixelBuffer, at: time).poses
            )
        }
        let players = lock.withLock {
            tracker.update(poses: poses, court: plane, time: time, imageSize: imageSize) {
                PoseAppearance(pose: $0, in: pixelBuffer)
            }
        }
        return CourtPlayersOutcome(
            time: time, players: players, poses: poses, regions: tiles + retries,
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000, imageSize: imageSize,
            failure: found.failure
        )
    }

    public func reset() {
        lock.withLock {
            tracker.reset()
            court = nil
            courtTime = nil
            hasFreshCourt = false
            lastSearchTime = nil
        }
    }

    /// このフレームで骨格の検出をかける範囲。追えている選手のまわりと、要るときは広く探す範囲。
    private func searchTiles(court: CourtPlane?, aspect: Double, time: TimeInterval) -> [CGRect] {
        var tiles = tracker.searchRegions(aspect: aspect)
        let isDue = lastSearchTime.map { time < $0 || time - $0 >= searchInterval } ?? true
        if tracker.trackedCount < maximumPlayers || isDue {
            tiles += court.map { regions.tiles(for: $0, aspect: aspect) } ?? regions.grid(aspect: aspect)
            lastSearchTime = time
        }
        return tiles
    }

    /// このフレームで使うコート。渡されたばかりならそれを、見つからなくなって間もなければ前のものを返す。
    private func currentCourt(at time: TimeInterval) -> CourtPlane? {
        if hasFreshCourt {
            courtTime = time
            return court
        }
        guard let courtTime, time >= courtTime, time - courtTime <= courtHoldSeconds else {
            court = nil
            return nil
        }
        return court
    }
}
