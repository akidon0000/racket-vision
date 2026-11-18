import CoreGraphics
import Foundation

/// コートのどちら側か。
public enum CourtSide: String, Codable, Sendable {
    /// 手前（カメラに近い側）。
    case near
    /// 奥。
    case far
}

/// コートにいる選手 1 人。
public struct CourtPlayer: Equatable, Sendable {
    /// 選手の番号。同じ人を追えているあいだ、同じ番号が続く。
    /// コートが分かっているときは、手前の選手が 0 と 1、奥の選手が 2 と 3。
    public var id: Int
    public var pose: BodyPose
    /// どちら側の選手か。コートが分からないときは nil。
    public var side: CourtSide?
    /// コートの上の位置（横 0〜1、縦 0〜1。`CourtPlane` の座標）。コートが分からないときは nil。
    public var courtPosition: CGPoint?
    /// この番号で追い始めた、フレームの時刻（秒）。同じ番号でも、これが変わったら、追い直した別の追跡。
    public var firstSeen: TimeInterval
    /// このフレームで骨格が見つかったか。false のときは、見つからなかったので、少し前の骨格と位置をそのまま出している。
    public var isDetected: Bool
    /// このフレームでの見た目（服の色）。取れなければ nil。
    public var appearance: PoseAppearance?

    public init(
        id: Int, pose: BodyPose, side: CourtSide?, courtPosition: CGPoint?, firstSeen: TimeInterval, isDetected: Bool = true,
        appearance: PoseAppearance? = nil
    ) {
        self.appearance = appearance
        self.id = id
        self.pose = pose
        self.side = side
        self.courtPosition = courtPosition
        self.firstSeen = firstSeen
        self.isDetected = isDetected
    }
}
