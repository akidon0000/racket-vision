import CoreFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// 動いていて、球の色をしていて、球の大きさの塊を拾い（`BallCandidateFinder`）、時間でつないで球を 1 つに決める（`BallTrackState`）。
///
/// 前の 2 フレームと追跡を覚える。映像の解析のキューから呼ばれるので、ロックで守る。
public final class MotionColorBallDetector: BallDetector, @unchecked Sendable {
    public let method = BallDetectionMethod.motionColor
    /// 球の色。
    public let color: BallColor
    /// 球の直径の範囲（映像の幅に対する割合）。
    public let diameterRange: ClosedRange<Double>
    /// 1 つ前のフレームから動いた画素の割合がこれを超えたら、場面の切り替わりとみなす。
    public let sceneChangeRatio: Double

    private let finder: BallCandidateFinder
    private let lock = NSLock()
    /// 前のフレーム（古い順、2 枚まで）。
    private var frames = [FrameImage]()
    private var state = BallTrackState()

    public init(color: BallColor = .yellowGreen, diameterRange: ClosedRange<Double> = 0.002...0.02, sceneChangeRatio: Double = 0.2) {
        self.color = color
        self.diameterRange = diameterRange
        self.sceneChangeRatio = sceneChangeRatio
        finder = BallCandidateFinder(color: color, diameterRange: diameterRange, sceneChangeRatio: sceneChangeRatio)
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
        let found = finder.find(current: frame, previous: frames[1], beforePrevious: frames[0])
        guard found.movingRatio <= sceneChangeRatio else {
            state.reset()
            outcome.sceneChanged = true
            return
        }
        outcome.candidates = found.candidates.map {
            observation(center: $0.center, radius: $0.radius, confidence: $0.score, in: frame)
        }
        if let ball = state.update(candidates: found.candidates, time: outcome.time, imageWidth: Double(frame.width)) {
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
