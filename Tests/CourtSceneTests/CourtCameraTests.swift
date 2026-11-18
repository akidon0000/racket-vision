import CoreGraphics
import CourtFit
import CourtScene
import PlayerPose
import simd
import Testing

/// 決めたカメラ（位置、注視点、焦点距離）で、3D の点を写す。テストの正解を作るのに使う。
struct TestCamera {
    var position: SIMD3<Double>
    var target: SIMD3<Double>
    var focalLength: Double
    var imageSize = CGSize(width: 1920, height: 1080)

    /// 3D の座標からカメラの座標（x 右、y 下、z 前）への回転。
    var rotation: simd_double3x3 {
        let forward = simd_normalize(target - position)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let down = simd_cross(forward, right)
        return simd_double3x3(rows: [right, down, forward])
    }

    /// 3D の点を、正規化座標（左下が原点）に写す。
    func project(_ point: SIMD3<Double>) -> CGPoint {
        let camera = rotation * (point - position)
        return CGPoint(
            x: focalLength * camera.x / camera.z / Double(imageSize.width) + 0.5,
            y: 0.5 - focalLength * camera.y / camera.z / Double(imageSize.height)
        )
    }

    /// コートの四隅の写り（奥の左、奥の右、手前の右、手前の左）。
    var corners: [CGPoint] {
        let model = CourtModel.pickleball
        return [
            SIMD3(-model.width / 2, 0, -model.length / 2), SIMD3(model.width / 2, 0, -model.length / 2),
            SIMD3(model.width / 2, 0, model.length / 2), SIMD3(-model.width / 2, 0, model.length / 2)
        ].map(project)
    }
}

struct CourtCameraTests {
    /// ベースラインの 4 m 後ろ、高さ 5 m から、コートの中心を見るカメラ。
    private let behind = TestCamera(position: SIMD3(0.5, 5, 10.7), target: SIMD3(0, 0, 0), focalLength: 1500)
    /// 斜め上から見るカメラ。
    private let oblique = TestCamera(position: SIMD3(-6, 9, 12), target: SIMD3(0.5, 0, -1), focalLength: 1100)

    @Test(arguments: [0, 1])
    func recoversCameraPositionAndFocalLength(_ index: Int) throws {
        let truth = [behind, oblique][index]
        let camera = try #require(CourtCamera(corners: truth.corners, imageSize: truth.imageSize))
        #expect(simd_distance(camera.position, truth.position) < 0.01)
        #expect(abs(camera.focalLength - truth.focalLength) / truth.focalLength < 0.001)
        let forward = simd_normalize(truth.target - truth.position)
        #expect(simd_dot(camera.forward, forward) > cos(0.1 * .pi / 180))
        #expect(camera.up.y > 0)
    }

    @Test func projectsAndIntersectsGround() throws {
        let camera = try #require(CourtCamera(corners: oblique.corners, imageSize: oblique.imageSize))
        let point = SIMD3(1.2, 0.0, 3.4)
        let image = try #require(camera.project(point))
        let expected = oblique.project(point)
        #expect(abs(image.x - expected.x) < 1e-6 && abs(image.y - expected.y) < 1e-6)
        let ground = try #require(camera.groundPoint(for: image))
        #expect(simd_distance(ground, point) < 0.01)
    }

    @Test func courtSpaceMatchesCourtPlaneCoordinates() {
        // 手前の左の角（コートの面で (0, 0)）と、奥の右の角（(1, 1)）。
        let model = CourtModel.pickleball
        #expect(CourtSpace.point(onCourt: CGPoint(x: 0, y: 0)) == SIMD3(-model.width / 2, 0, model.length / 2))
        #expect(CourtSpace.point(onCourt: CGPoint(x: 1, y: 1)) == SIMD3(model.width / 2, 0, -model.length / 2))
    }

    @Test func rejectsDegenerateCorners() {
        #expect(CourtCamera(corners: [], imageSize: CGSize(width: 100, height: 100)) == nil)
        let flat = [CGPoint](repeating: CGPoint(x: 0.5, y: 0.5), count: 4)
        #expect(CourtCamera(corners: flat, imageSize: CGSize(width: 100, height: 100)) == nil)
    }

    @Test func placesFlatFigureOnPlaneFacingCamera() throws {
        let camera = try #require(CourtCamera(corners: oblique.corners, imageSize: oblique.imageSize))
        // 足元が (1, 0, 2) の人。カメラのほうを向いた縦の面の上に、関節がある。
        let foot = SIMD3(1.0, 0, 2.0)
        var toCamera = oblique.position - foot
        toCamera.y = 0
        let normal = simd_normalize(toCamera)
        let side = simd_normalize(simd_cross(SIMD3(0, 1, 0), normal))
        let truth: [PoseJoint: SIMD3<Double>] = [
            .leftAnkle: foot - side * 0.15, .rightAnkle: foot + side * 0.15,
            .neck: foot + SIMD3(0, 1.45, 0), .nose: foot + SIMD3(0, 1.6, 0), .leftWrist: foot + side * 0.5 + SIMD3(0, 1.0, 0)
        ]
        let pose = BodyPose(joints: truth.mapValues { PoseKeypoint(position: oblique.project($0), confidence: 0.9) })
        let player = CourtPlayer(id: 2, pose: pose, side: .near, courtPosition: nil, firstSeen: 0)
        let placed = try #require(camera.place([player]).first)
        #expect(placed.id == 2)
        #expect(simd_distance(placed.foot, foot) < 0.01)
        for (joint, point) in truth {
            #expect(simd_distance(try #require(placed.joints[joint]), point) < 0.01)
        }
    }
}
