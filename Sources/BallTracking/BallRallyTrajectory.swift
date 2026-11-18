import CoreGraphics
import Foundation

/// 軌跡の 1 点。
public struct BallSample: Equatable, Sendable {
    /// フレームの時刻（秒）。
    public var time: TimeInterval
    /// 球の中心（正規化座標、左下が原点）。
    public var center: CGPoint
    /// 球の半径（映像の幅に対する割合）。
    public var radius: CGFloat
    /// 確からしさ（0〜1）。
    public var confidence: Float

    public init(time: TimeInterval, center: CGPoint, radius: CGFloat, confidence: Float) {
        self.time = time
        self.center = center
        self.radius = radius
        self.confidence = confidence
    }
}

/// 今のラリーの、球の軌跡。
///
/// 1 回打ってから、相手が打ち返すまでを、1 つのラリーとする。打ち返されたら、軌跡を消し、番号を 1 つ進める。
/// 打ち返しは、球の動きで決める。次の 2 つがそろったら、速さが変わった点で打ち返されたとみる。
/// - 球の速さ（向きを含む）が、短い時間（`turnWindow`）で `turnSpeed` より大きく変わった
///   （山なりの軌道の頂点は、重力でゆっくり変わるだけなので当たらない）。
/// - 打った位置から一番遠くまで行った球が、`turnDistance` より多く戻ってきた（バウンドは、戻らないので当たらない）。
///
/// 球が `rallyGap` 秒見えないか、場面が切り替わったときも、ラリーの終わりとする。
/// 番号は、表示の色を選ぶのに使う（`BallRallyPalette`）。
public struct BallRallyTrajectory: Equatable, Sendable {
    /// 球が見えない時間がこれを超えたら、ラリーの終わりとする（秒）。
    public var rallyGap: TimeInterval
    /// 球がこれより多く戻ってきたら、打ち返されたとみる（映像の短い辺に対する割合）。
    public var turnDistance: CGFloat
    /// 球の速さが変わったかを見る、時間の幅（秒）。この幅の前と後の速さを比べる。
    public var turnWindow: TimeInterval = 0.08
    /// 球の速さ（向きを含む）がこれより大きく変わったら、打たれたかバウンドしたとみる
    /// （1 秒に動く距離の差。映像の短い辺を 1 とした長さ）。重力だけでは、`turnWindow` のあいだに 0.1〜0.2 ほど変わる。
    public var turnSpeed: CGFloat = 0.4
    /// 今のラリーの番号（0 始まり）。軌跡が空のときは、次に始まるラリーの番号。
    public private(set) var rallyIndex = 0
    /// 今のラリーの軌跡（時刻の順）。ラリーが終わると空になる。
    public private(set) var samples = [BallSample]()
    /// 今のラリーで、最初の点から一番遠い点の番号と、その距離（映像の短い辺を 1 とした長さ）。
    private var farthestIndex = 0
    private var farthestDistance: CGFloat = 0
    /// 今のラリーで、一番遠い点のあたりから後で、球の速さがいちばん大きく変わった点の番号と、変わった大きさ。
    private var turnIndex: Int?
    private var turnStrength: CGFloat = 0

    public init(rallyGap: TimeInterval = 2, turnDistance: CGFloat = 0.05) {
        self.rallyGap = rallyGap
        self.turnDistance = turnDistance
    }

    /// 1 フレームぶんの結果を足す。フレームは時刻の順に渡す。球の無いフレームも渡す（ラリーの終わりを決めるのに使う）。
    public mutating func append(_ outcome: BallFrameOutcome) {
        if let last = samples.last, outcome.sceneChanged || outcome.time - last.time > rallyGap || outcome.time < last.time {
            startRally(with: [])
        }
        guard let ball = outcome.ball else { return }
        samples.append(BallSample(time: outcome.time, center: ball.center, radius: ball.radius, confidence: ball.confidence))
        let distance = distance(from: samples[0], to: samples[samples.count - 1], imageSize: outcome.imageSize)
        if distance >= farthestDistance {
            farthestDistance = distance
            farthestIndex = samples.count - 1
        }
        // 一番遠い点より前で速さが変わった点（バウンドなど）は、打ち返しではない。
        if let turn = turnIndex, turn + 2 < farthestIndex {
            turnIndex = nil
            turnStrength = 0
        }
        if let (index, strength) = speedChange(imageSize: outcome.imageSize),
           strength >= turnSpeed, strength > turnStrength, index > 0, index + 2 >= farthestIndex {
            turnIndex = index
            turnStrength = strength
        }
        if farthestDistance - distance >= turnDistance, let turn = turnIndex {
            // 速さが変わった点で打ち返された。そこから先を、次のラリーにする。
            startRally(with: Array(samples[turn...]))
            for index in samples.indices {
                let distance = self.distance(from: samples[0], to: samples[index], imageSize: outcome.imageSize)
                if distance >= farthestDistance {
                    farthestDistance = distance
                    farthestIndex = index
                }
            }
        }
    }

    /// 軌跡を消し、番号を 0 に戻す。
    public mutating func reset() {
        samples = []
        rallyIndex = 0
        farthestIndex = 0
        farthestDistance = 0
        turnIndex = nil
        turnStrength = 0
    }

    private mutating func startRally(with samples: [BallSample]) {
        self.samples = samples
        rallyIndex += 1
        farthestIndex = 0
        farthestDistance = 0
        turnIndex = nil
        turnStrength = 0
    }

    /// 最後の点の `turnWindow` 秒前の点について、その前の `turnWindow` 秒の速さと、後の速さの差を返す
    /// （点の番号と、差の大きさ。1 秒に動く距離、映像の短い辺を 1 とした長さ）。点が足りなければ nil。
    private func speedChange(imageSize: CGSize) -> (index: Int, strength: CGFloat)? {
        guard let last = samples.last,
              let middle = samples.lastIndex(where: { $0.time <= last.time - turnWindow }),
              let first = samples[..<middle].lastIndex(where: { $0.time <= samples[middle].time - turnWindow }) else {
            return nil
        }
        let before = vector(from: samples[first], to: samples[middle], imageSize: imageSize)
        let after = vector(from: samples[middle], to: last, imageSize: imageSize)
        let beforeSeconds = samples[middle].time - samples[first].time
        let afterSeconds = last.time - samples[middle].time
        let dx = after.dx / afterSeconds - before.dx / beforeSeconds
        let dy = after.dy / afterSeconds - before.dy / beforeSeconds
        return (middle, (dx * dx + dy * dy).squareRoot())
    }

    /// 2 点の差（映像の短い辺を 1 とした長さ）。
    private func vector(from first: BallSample, to second: BallSample, imageSize: CGSize) -> CGVector {
        let short = min(imageSize.width, imageSize.height)
        guard short > 0 else { return .zero }
        return CGVector(
            dx: (second.center.x - first.center.x) * imageSize.width / short,
            dy: (second.center.y - first.center.y) * imageSize.height / short
        )
    }

    /// 2 点の距離（映像の短い辺を 1 とした長さ）。
    private func distance(from first: BallSample, to second: BallSample, imageSize: CGSize) -> CGFloat {
        let vector = vector(from: first, to: second, imageSize: imageSize)
        return (vector.dx * vector.dx + vector.dy * vector.dy).squareRoot()
    }
}
