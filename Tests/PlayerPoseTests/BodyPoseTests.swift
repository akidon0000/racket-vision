import CoreGraphics
@testable import PlayerPose
import Testing

struct BodyPoseTests {
    private func keypoint(_ x: CGFloat, _ y: CGFloat) -> PoseKeypoint {
        PoseKeypoint(position: CGPoint(x: x, y: y), confidence: 0.8)
    }

    @Test func footPointIsMiddleOfAnkles() {
        let pose = BodyPose(joints: [.leftAnkle: keypoint(0.4, 0.2), .rightAnkle: keypoint(0.5, 0.22)])
        #expect(abs((pose.footPoint?.x ?? 0) - 0.45) < 1e-9)
        #expect(abs((pose.footPoint?.y ?? 0) - 0.21) < 1e-9)
    }

    @Test func footPointFallsBackToOneAnkleThenKnees() {
        let oneAnkle = BodyPose(joints: [.leftAnkle: keypoint(0.4, 0.2), .nose: keypoint(0.4, 0.6)])
        #expect(oneAnkle.footPoint == CGPoint(x: 0.4, y: 0.2))
        // 足首が無ければ、膝から、腿と同じ長さだけ下へ伸ばす。
        let noAnkles = BodyPose(joints: [.leftHip: keypoint(0.4, 0.5), .leftKnee: keypoint(0.4, 0.35)])
        #expect(abs((noAnkles.footPoint?.y ?? 0) - 0.2) < 1e-9)
        #expect(BodyPose(joints: [.nose: keypoint(0.4, 0.6)]).footPoint == nil)
    }

    @Test func boundingBoxSurroundsJoints() {
        let pose = standingPose(foot: CGPoint(x: 0.5, y: 0.2), height: 0.4)
        let box = pose.boundingBox
        #expect(abs((box?.minY ?? 0) - 0.2) < 1e-9)
        #expect(abs((box?.height ?? 0) - 0.4) < 1e-9)
        #expect(BodyPose(joints: [:]).boundingBox == nil)
    }

    @Test func deduplicatorMergesSamePersonFromOverlappingRegions() {
        let first = standingPose(foot: CGPoint(x: 0.5, y: 0.2))
        let second = standingPose(foot: CGPoint(x: 0.505, y: 0.203))
        #expect(PoseDeduplicator().merge([first, second]).count == 1)
    }

    @Test func deduplicatorKeepsSmallPersonInsideLargePersonsBox() {
        // 手前の大きな選手の枠の中に、奥の小さな選手が入っている。別の人として、両方を残す。
        let near = standingPose(foot: CGPoint(x: 0.5, y: 0.1), height: 0.6)
        let far = standingPose(foot: CGPoint(x: 0.5, y: 0.4), height: 0.15)
        #expect(PoseDeduplicator().merge([near, far]).count == 2)
    }
}
