import CoreGraphics
import Foundation

/// 映像から見つけた球 1 個。
public struct BallObservation: Equatable, Sendable {
    /// 中心。映像の大きさに対する 0〜1 の正規化座標で、原点は左下（`CourtFit` の `DetectedQuad` と同じ）。
    public var center: CGPoint
    /// 半径。映像の幅に対する割合。
    public var radius: CGFloat
    /// 確からしさ（0〜1）。
    public var confidence: Float

    public init(center: CGPoint, radius: CGFloat, confidence: Float) {
        self.center = center
        self.radius = radius
        self.confidence = confidence
    }
}

/// 球の検出の方式。使う側が自前の方式を足せるよう、列挙ではなく値で表す。
public struct BallDetectionMethod: Hashable, Sendable {
    public let rawValue: String
    /// 画面に出す名前。
    public let label: String

    public init(rawValue: String, label: String) {
        self.rawValue = rawValue
        self.label = label
    }

    /// 動きと色で拾い、軌跡でつなぐ方式（`MotionColorBallDetector`）。
    public static let motionColor = BallDetectionMethod(rawValue: "motionColor", label: "動きと色")
}

/// 1 フレームぶんの、球の検出の結果。
public struct BallFrameOutcome: Equatable, Sendable {
    public var method: BallDetectionMethod
    /// 検出器に渡した、フレームの時刻（秒）。
    public var time: TimeInterval
    /// 球。見つからなければ nil。
    public var ball: BallObservation?
    /// 球の候補（追跡で絞る前）。確認用に描くためのもの。
    public var candidates: [BallObservation]
    /// 場面が切り替わったとみなして、追跡を捨てたか。
    public var sceneChanged: Bool
    /// 検出にかかった時間（ミリ秒）。
    public var durationMilliseconds: Double
    /// 検出に使った映像の大きさ（ピクセル）。
    public var imageSize: CGSize

    public init(
        method: BallDetectionMethod,
        time: TimeInterval,
        ball: BallObservation?,
        candidates: [BallObservation] = [],
        sceneChanged: Bool = false,
        durationMilliseconds: Double,
        imageSize: CGSize
    ) {
        self.method = method
        self.time = time
        self.ball = ball
        self.candidates = candidates
        self.sceneChanged = sceneChanged
        self.durationMilliseconds = durationMilliseconds
        self.imageSize = imageSize
    }
}
