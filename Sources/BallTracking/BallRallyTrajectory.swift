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
/// 球を追えているひと続きを、1 つのラリーとする。球が `rallyGap` 秒見えないか、場面が切り替わったら、ラリーの終わりとして、
/// 軌跡を消し、番号を 1 つ進める。番号は、表示の色を選ぶのに使う（`BallRallyPalette`）。
public struct BallRallyTrajectory: Equatable, Sendable {
    /// 球が見えない時間がこれを超えたら、ラリーの終わりとする（秒）。
    public var rallyGap: TimeInterval
    /// 今のラリーの番号（0 始まり）。軌跡が空のときは、次に始まるラリーの番号。
    public private(set) var rallyIndex = 0
    /// 今のラリーの軌跡（時刻の順）。ラリーが終わると空になる。
    public private(set) var samples = [BallSample]()

    public init(rallyGap: TimeInterval = 2) {
        self.rallyGap = rallyGap
    }

    /// 1 フレームぶんの結果を足す。フレームは時刻の順に渡す。球の無いフレームも渡す（ラリーの終わりを決めるのに使う）。
    public mutating func append(_ outcome: BallFrameOutcome) {
        if let last = samples.last, outcome.sceneChanged || outcome.time - last.time > rallyGap || outcome.time < last.time {
            samples = []
            rallyIndex += 1
        }
        guard let ball = outcome.ball else { return }
        samples.append(BallSample(time: outcome.time, center: ball.center, radius: ball.radius, confidence: ball.confidence))
    }

    /// 軌跡を消し、番号を 0 に戻す。
    public mutating func reset() {
        samples = []
        rallyIndex = 0
    }
}
