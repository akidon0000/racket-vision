import CoreFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// 動いていて、球の色をしていて、球の大きさの塊を拾い（`BallCandidateFinder`）、時間でつないで球を 1 つに決める（`BallTrackState`）。
///
/// 前の 2 フレームと追跡を覚える。映像の解析のキューから呼ばれるので、ロックで守る。
public final class MotionColorBallDetector: BallDetector, @unchecked Sendable {
    public let method = BallDetectionMethod.motionColor
    /// 球の色（探すときの色、コートの範囲で絞れるときの色、追っている球の近くを探すときの色）。
    /// コートの矩形が渡されているあいだは、範囲で絞れるので、薄く写った球まで取る色（`court`）を使う。
    public var colors: BallColorSet { lock.withLock { currentColors } }
    /// 球の色。
    public var color: BallColor { colors.ball }
    /// コートの矩形が渡されているあいだに使う、球の色。
    public var courtColor: BallColor { colors.court }
    /// 球の直径の範囲（映像の幅に対する割合）。
    public let diameterRange: ClosedRange<Double>
    /// 1 つ前のフレームから動いた画素の割合がこれを超えたら、場面の切り替わりとみなす。
    public let sceneChangeRatio: Double

    private var currentColors: BallColorSet
    private var finder: BallCandidateFinder
    private var courtFinder: BallCandidateFinder
    private let lock = NSLock()
    /// 前のフレーム（古い順、2 枚まで）。
    private var frames = [FrameImage]()
    private var state = BallTrackState()
    /// 球を探す範囲のもとになる、コートの矩形の四隅。nil なら、画面のどこでも探す。
    private var courtCorners: [CGPoint]?
    private var courtMargin = 0.05
    private var courtAirHeight = 0.6

    public init(
        colors: BallColorSet = .yellowGreen,
        diameterRange: ClosedRange<Double> = 0.002...0.02, sceneChangeRatio: Double = 0.2
    ) {
        currentColors = colors
        self.diameterRange = diameterRange
        self.sceneChangeRatio = sceneChangeRatio
        (finder, courtFinder) = Self.finders(colors, diameterRange: diameterRange, sceneChangeRatio: sceneChangeRatio)
    }

    public convenience init(
        color: BallColor, courtColor: BallColor = .yellowGreenPale,
        diameterRange: ClosedRange<Double> = 0.002...0.02, sceneChangeRatio: Double = 0.2
    ) {
        self.init(
            colors: BallColorSet(ball: color, court: courtColor, tracking: .yellowGreenWide),
            diameterRange: diameterRange, sceneChangeRatio: sceneChangeRatio
        )
    }

    private static func finders(
        _ colors: BallColorSet, diameterRange: ClosedRange<Double>, sceneChangeRatio: Double
    ) -> (BallCandidateFinder, BallCandidateFinder) {
        (
            BallCandidateFinder(color: colors.ball, trackingColor: colors.tracking, diameterRange: diameterRange, sceneChangeRatio: sceneChangeRatio),
            BallCandidateFinder(color: colors.court, trackingColor: colors.tracking, diameterRange: diameterRange, sceneChangeRatio: sceneChangeRatio)
        )
    }

    /// 球の色を切り替える（動画の途中で、球の色が分かったとき）。色が変わったら、追跡をやり直す。
    public func setColors(_ colors: BallColorSet) {
        lock.withLock {
            guard colors != currentColors else { return }
            currentColors = colors
            (finder, courtFinder) = Self.finders(colors, diameterRange: diameterRange, sceneChangeRatio: sceneChangeRatio)
            state.reset()
        }
    }

    public func detect(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> BallFrameOutcome {
        let started = CFAbsoluteTimeGetCurrent()
        var outcome = BallFrameOutcome(
            method: method,
            time: time,
            ball: nil,
            durationMilliseconds: 0,
            imageSize: CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        )
        if let frame = FrameImage(bgraPixelBuffer: pixelBuffer) {
            lock.withLock { analyze(frame, into: &outcome) }
        }
        outcome.durationMilliseconds = (CFAbsoluteTimeGetCurrent() - started) * 1000
        return outcome
    }

    /// 球を探す範囲を、コートの矩形で決める。`corners` は、正規化座標（左下が原点）の四隅（左上、右上、右下、左下の順）。
    /// `margin` は、範囲を外へどれだけ広げるか（正規化座標）。
    /// `airHeight` は、空中の球のために、範囲を上へどれだけ伸ばすか（コートの幅に対する割合。0.6 で約 3.7 m）。
    /// `nil` で範囲を外す。空の配列なら、どの候補も球にしない。
    public func setCourtRegion(_ corners: [CGPoint]?, margin: CGFloat = 0.05, airHeight: CGFloat = 0.6) {
        lock.withLock {
            courtCorners = corners
            courtMargin = Double(margin)
            courtAirHeight = Double(airHeight)
        }
    }

    public func reset() {
        lock.withLock {
            frames = []
            state.reset()
        }
    }

    private func analyze(_ frame: FrameImage, into outcome: inout BallFrameOutcome) {
        // 大きさが変わったら、覚えているフレームとは比べられない。
        if let last = frames.last, last.width != frame.width || last.height != frame.height {
            frames = []
            state.reset()
        }
        defer { frames = Array((frames + [frame]).suffix(2)) }
        guard frames.count == 2 else { return }
        let finder = courtCorners == nil ? finder : courtFinder
        let found = finder.find(current: frame, previous: frames[1], beforePrevious: frames[0])
        guard found.movingRatio <= sceneChangeRatio else {
            state.reset()
            outcome.sceneChanged = true
            return
        }
        let region = courtCorners.map {
            BallRegion(
                corners: $0, margin: courtMargin, airHeight: courtAirHeight,
                aspect: Double(frame.width) / Double(frame.height)
            )
        }
        // 球の範囲が決まっていれば、その中（少し外まで）の候補だけを残す。
        func keeps(_ candidate: BallCandidate) -> Bool {
            guard let region else { return true }
            return region.contains(SIMD2(candidate.center.x / Double(frame.width), 1 - candidate.center.y / Double(frame.height)))
        }
        let candidates = found.candidates.filter(keeps)
        outcome.candidates = candidates.map {
            observation(center: $0.center, radius: $0.radius, confidence: $0.score, in: frame)
        }
        let previous = frames[1]
        let ball = state.update(candidates: candidates, time: outcome.time, imageWidth: Double(frame.width)) { center, reach in
            finder.findNear(center: center, reach: reach, current: frame, previous: previous).filter(keeps)
        }
        if let ball {
            outcome.ball = observation(center: ball.center, radius: ball.radius, confidence: ball.confidence, in: frame)
        }
    }

    /// 画素の座標（左上が原点）を、正規化座標（左下が原点）にする。
    private func observation(center: SIMD2<Double>, radius: Double, confidence: Double, in frame: FrameImage) -> BallObservation {
        BallObservation(
            center: CGPoint(x: center.x / Double(frame.width), y: 1 - center.y / Double(frame.height)),
            radius: CGFloat(radius / Double(frame.width)),
            confidence: Float(confidence)
        )
    }
}
