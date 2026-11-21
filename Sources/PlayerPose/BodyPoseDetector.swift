import CoreGraphics
import CoreVideo
import Foundation

/// 骨格を検出する方式の名前。使う側が自前の方式を足せるよう、値で表す。
public struct PoseDetectionMethod: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    /// 画面に出す名前。
    public let label: String

    public init(rawValue: String, label: String) {
        self.rawValue = rawValue
        self.label = label
    }

    public var description: String { rawValue }

    /// Vision の骨格検出を、画面の全体にかける。
    public static let vision = Self(rawValue: "vision", label: "Vision")
    /// Vision の骨格検出を、コートのまわりを分けた範囲ごとにかける（小さく写った選手を取るため）。
    public static let visionTiled = Self(rawValue: "visionTiled", label: "Vision（範囲ごと）")
}

/// 1 フレームの骨格の検出の結果。
public struct PoseFrameOutcome: Equatable, Sendable {
    public var method: PoseDetectionMethod
    /// フレームの時刻（秒）。
    public var time: TimeInterval
    /// 見つかった人ごとの骨格（選手に限らない。観客や審判も入る）。
    public var poses: [BodyPose]
    /// 処理時間（ms）。
    public var durationMilliseconds: Double
    /// 映像の大きさ（画素）。
    public var imageSize: CGSize
    /// 検出が動かなかったときの理由（Vision のエラーの説明）。動いたら nil。人がいないだけのときも nil。
    public var failure: String?

    public init(
        method: PoseDetectionMethod, time: TimeInterval, poses: [BodyPose], durationMilliseconds: Double, imageSize: CGSize,
        failure: String? = nil
    ) {
        self.method = method
        self.time = time
        self.poses = poses
        self.durationMilliseconds = durationMilliseconds
        self.imageSize = imageSize
        self.failure = failure
    }
}

/// フレームから、人ごとの骨格を検出する。方式ごとに、同じ入出力にする。
public protocol BodyPoseDetector: Sendable {
    var method: PoseDetectionMethod { get }
    /// 上向きの 32BGRA の画素バッファから、骨格を検出する。`time` は、そのフレームの時刻（秒）。
    func detect(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> PoseFrameOutcome
}
