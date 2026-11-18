import CoreGraphics
import PlayerPose
import simd

/// 3D に置いた選手 1 人。
public struct ScenePlayer: Equatable, Sendable {
    /// 選手の番号（`CourtPlayer.id`）。
    public var id: Int
    /// 足元（3D の座標、地面の上）。
    public var foot: SIMD3<Double>
    /// 関節の位置（3D の座標）。
    public var joints: [PoseJoint: SIMD3<Double>]
    /// このフレームで骨格が見つかったか（`CourtPlayer.isDetected`）。
    public var isDetected: Bool

    public init(id: Int, foot: SIMD3<Double>, joints: [PoseJoint: SIMD3<Double>], isDetected: Bool) {
        self.id = id
        self.foot = foot
        self.joints = joints
        self.isDetected = isDetected
    }
}

extension CourtCamera {
    /// 選手を 3D に置く。足元は地面の上、関節は、足元を通ってカメラのほうを向いた縦の面の上に置く（平たい人形）。
    /// 足元が分からない選手、足元が地面と交わらない選手は、出さない。
    public func place(_ players: [CourtPlayer]) -> [ScenePlayer] {
        players.compactMap { player in
            guard let footImage = player.pose.footPoint, let foot = groundPoint(for: footImage) else { return nil }
            // 足元からカメラへの、水平の向き。これに直交する縦の面に、関節を置く。
            var toCamera = position - foot
            toCamera.y = 0
            guard simd_length(toCamera) > 1e-6 else { return nil }
            let normal = simd_normalize(toCamera)
            var joints = [PoseJoint: SIMD3<Double>]()
            for (joint, keypoint) in player.pose.joints {
                guard let point = intersect(keypoint.position, plane: foot, normal: normal) else { continue }
                joints[joint] = point
            }
            return ScenePlayer(id: player.id, foot: foot, joints: joints, isDetected: player.isDetected)
        }
    }
}
