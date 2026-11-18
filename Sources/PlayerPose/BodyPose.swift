import CoreGraphics

/// 関節 1 つの位置。
public struct PoseKeypoint: Hashable, Sendable {
    /// 位置（映像の大きさに対する 0〜1 の正規化座標、左下が原点）。
    public var position: CGPoint
    /// 確からしさ（0〜1）。
    public var confidence: Float

    public init(position: CGPoint, confidence: Float) {
        self.position = position
        self.confidence = confidence
    }
}

/// 1 人ぶんの骨格。見つからなかった関節は入らない。
public struct BodyPose: Hashable, Sendable {
    public var joints: [PoseJoint: PoseKeypoint]

    public init(joints: [PoseJoint: PoseKeypoint]) {
        self.joints = joints
    }

    /// 関節の位置。見つかっていなければ nil。
    public func position(of joint: PoseJoint) -> CGPoint? {
        joints[joint]?.position
    }

    /// 見つかった関節を囲む四角形（正規化座標）。関節が無ければ nil。
    public var boundingBox: CGRect? {
        guard let first = joints.values.first else { return nil }
        var minX = first.position.x
        var maxX = minX
        var minY = first.position.y
        var maxY = minY
        for keypoint in joints.values {
            minX = min(minX, keypoint.position.x)
            maxX = max(maxX, keypoint.position.x)
            minY = min(minY, keypoint.position.y)
            maxY = max(maxY, keypoint.position.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 関節の確からしさの平均。関節が無ければ 0。
    public var confidence: Float {
        joints.isEmpty ? 0 : joints.values.reduce(0) { $0 + $1.confidence } / Float(joints.count)
    }

    /// 足元（地面に接している点の見込み、正規化座標）。コートのどこに立っているかを求めるのに使う。
    ///
    /// 両足首の中点。片方だけなら、その足首。足首が無ければ、膝から、腿と同じ長さだけ下へ伸ばした点。
    /// どれも無ければ nil。
    public var footPoint: CGPoint? {
        let ankles = [PoseJoint.leftAnkle, .rightAnkle].compactMap { position(of: $0) }
        if !ankles.isEmpty {
            return mean(of: ankles)
        }
        let shins = [(PoseJoint.leftHip, PoseJoint.leftKnee), (.rightHip, .rightKnee)].compactMap { hip, knee -> CGPoint? in
            guard let hip = position(of: hip), let knee = position(of: knee) else { return nil }
            return CGPoint(x: 2 * knee.x - hip.x, y: 2 * knee.y - hip.y)
        }
        return shins.isEmpty ? nil : mean(of: shins)
    }

    private func mean(of points: [CGPoint]) -> CGPoint {
        CGPoint(
            x: points.reduce(0) { $0 + $1.x } / CGFloat(points.count),
            y: points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
        )
    }
}
