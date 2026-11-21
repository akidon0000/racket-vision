/// 骨格の関節。左右は、本人から見た左右。
public enum PoseJoint: String, CaseIterable, Codable, Sendable {
    case nose
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case neck
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    /// 腰の中心。
    case root
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

/// 関節をつなぐ骨。骨格を線で描くときに使う。
public struct PoseBone: Equatable, Sendable {
    public var start: PoseJoint
    public var end: PoseJoint

    public init(start: PoseJoint, end: PoseJoint) {
        self.start = start
        self.end = end
    }

    /// 体の骨（顔の中の線は入れない）。
    public static let body: [PoseBone] = [
        PoseBone(start: .nose, end: .neck),
        PoseBone(start: .neck, end: .leftShoulder),
        PoseBone(start: .neck, end: .rightShoulder),
        PoseBone(start: .leftShoulder, end: .leftElbow),
        PoseBone(start: .leftElbow, end: .leftWrist),
        PoseBone(start: .rightShoulder, end: .rightElbow),
        PoseBone(start: .rightElbow, end: .rightWrist),
        PoseBone(start: .neck, end: .root),
        PoseBone(start: .root, end: .leftHip),
        PoseBone(start: .root, end: .rightHip),
        PoseBone(start: .leftHip, end: .leftKnee),
        PoseBone(start: .leftKnee, end: .leftAnkle),
        PoseBone(start: .rightHip, end: .rightKnee),
        PoseBone(start: .rightKnee, end: .rightAnkle)
    ]
}
