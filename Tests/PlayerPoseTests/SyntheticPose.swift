import CoreGraphics
import CourtFit
import PlayerPose

/// 立っている人の骨格を作る。`foot` は足元（正規化座標、左下が原点）、`height` は身長（正規化座標の縦の長さ）。
func standingPose(foot: CGPoint, height: CGFloat = 0.25) -> BodyPose {
    func joint(_ dx: CGFloat, _ dy: CGFloat) -> PoseKeypoint {
        PoseKeypoint(position: CGPoint(x: foot.x + dx * height, y: foot.y + dy * height), confidence: 0.9)
    }
    return BodyPose(joints: [
        .leftAnkle: joint(-0.08, 0), .rightAnkle: joint(0.08, 0),
        .leftKnee: joint(-0.08, 0.25), .rightKnee: joint(0.08, 0.25),
        .leftHip: joint(-0.08, 0.5), .rightHip: joint(0.08, 0.5), .root: joint(0, 0.5),
        .leftShoulder: joint(-0.12, 0.8), .rightShoulder: joint(0.12, 0.8), .neck: joint(0, 0.82),
        .nose: joint(0, 1)
    ])
}

/// 映像の全体がコート（コートの座標と、映像の正規化座標が同じ）になるコート。
let wholeImageCourt = CourtPlane(corners: [
    CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)
])
