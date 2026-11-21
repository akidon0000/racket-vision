import CoreGraphics

/// 重なる範囲から同じ人が 2 回出たとき、1 つにまとめる。
struct PoseDeduplicator {
    /// 同じ関節どうしのずれの平均が、これ（骨格の大きさに対する割合）より小さければ、同じ人とみる。
    var jointTolerance: CGFloat = 0.2
    /// 比べられる関節が少ないときは、骨格を囲む四角形の重なり（重なり ÷ 合わせた面積）がこれ以上なら、同じ人とみる。
    var overlap: CGFloat = 0.5

    /// 同じ人の骨格は、関節の多いほう（同じなら確からしいほう）を残す。
    func merge(_ poses: [BodyPose]) -> [BodyPose] {
        let sorted = poses.sorted {
            $0.joints.count == $1.joints.count ? $0.confidence > $1.confidence : $0.joints.count > $1.joints.count
        }
        var kept = [BodyPose]()
        for pose in sorted where !kept.contains(where: { isSamePerson($0, pose) }) {
            kept.append(pose)
        }
        return kept
    }

    /// 大きく写った人の枠の中に、小さく写った別の人が入ることがある（手前と奥の選手）。枠の重なりだけでは決めず、
    /// 同じ関節が同じ場所にあるかで決める。
    func isSamePerson(_ first: BodyPose, _ second: BodyPose) -> Bool {
        guard let a = first.boundingBox, let b = second.boundingBox else { return false }
        let size = max(a.width, a.height, b.width, b.height)
        var total: CGFloat = 0
        var count: CGFloat = 0
        for (joint, keypoint) in first.joints {
            guard let other = second.joints[joint] else { continue }
            let dx = keypoint.position.x - other.position.x
            let dy = keypoint.position.y - other.position.y
            total += (dx * dx + dy * dy).squareRoot()
            count += 1
        }
        if count >= 3, size > 0 {
            return total / count / size <= jointTolerance
        }
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return false }
        let common = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - common
        return union > 0 && common / union >= overlap
    }
}
