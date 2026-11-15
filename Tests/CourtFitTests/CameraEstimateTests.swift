@testable import CourtFit
import CoreGraphics
import simd
import Testing

struct CameraEstimateTests {
    private let imageSize = TestCamera.imageSize

    @Test func recoversCameraBehindBaseline() throws {
        // ベースラインの後ろの中央。横の線が画面と平行になる、よくある置き方。
        let homography = TestCamera.homography(camera: SIMD3(0, -12, 3), focalLength: 1500)
        let estimate = try #require(CameraEstimate(homography: homography, imageSize: imageSize))

        #expect(abs(estimate.focalLength - 1500) < 1e-3)
        #expect(abs(estimate.height - 3) < 1e-6)
        #expect(abs(estimate.rollDegrees) < 1e-6)
        #expect(abs(estimate.pitchDegrees - atan2(3.0, 12.0) * 180 / .pi) < 1e-6)
        #expect(estimate.shapeError < 1e-9)
        #expect(CameraPlausibility().accepts(estimate, imageSize: imageSize))
    }

    @Test func recoversCameraAtCorner() throws {
        let homography = TestCamera.homography(camera: SIMD3(8, -10, 2.5), focalLength: 1400)
        let estimate = try #require(CameraEstimate(homography: homography, imageSize: imageSize))

        #expect(abs(estimate.focalLength - 1400) < 1e-3)
        #expect(abs(estimate.height - 2.5) < 1e-6)
        #expect(abs(estimate.rollDegrees) < 1e-6)
        #expect(CameraPlausibility().accepts(estimate, imageSize: imageSize))
    }

    @Test func reportsRoll() throws {
        let homography = TestCamera.homography(camera: SIMD3(8, -10, 2.5), focalLength: 1400, rollDegrees: 10)
        let estimate = try #require(CameraEstimate(homography: homography, imageSize: imageSize))

        #expect(abs(abs(estimate.rollDegrees) - 10) < 1e-6)
        #expect(abs(estimate.height - 2.5) < 1e-6)
    }

    @Test func doesNotDependOnSignOfMatrix() throws {
        let homography = TestCamera.homography(camera: SIMD3(8, -10, 2.5), focalLength: 1400)
        let flipped = Homography(matrix: homography.matrix * -1)
        let estimate = try #require(CameraEstimate(homography: flipped, imageSize: imageSize))

        #expect(abs(estimate.height - 2.5) < 1e-6)
    }

    @Test func usesKnownFocalLengthAndReportsShapeError() throws {
        let homography = TestCamera.homography(camera: SIMD3(8, -10, 2.5), focalLength: 1400)
        let right = try #require(CameraEstimate(homography: homography, imageSize: imageSize, knownFocalLength: 1400))
        let wrong = try #require(CameraEstimate(homography: homography, imageSize: imageSize, knownFocalLength: 700))

        #expect(right.shapeError < 1e-9)
        #expect(wrong.shapeError > 0.1)
    }

    @Test func rejectsQuadThatNoCameraCanSee() throws {
        // 画面の上で、奥のほうが広い台形。地面のコートを上から撮ると、こうは写らない。
        let quad = DetectedQuad(
            topLeft: CGPoint(x: 0.1, y: 0.9), topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.6, y: 0.2), bottomLeft: CGPoint(x: 0.4, y: 0.2)
        )
        let homography = try #require(Homography(courtOutline: quad, imageSize: imageSize, quarterTurned: false))
        let estimate = CameraEstimate(homography: homography, imageSize: imageSize)

        #expect(estimate.map { CameraPlausibility().accepts($0, imageSize: imageSize) } != true)
    }

    @Test func rejectsCameraTooHigh() throws {
        let homography = TestCamera.homography(camera: SIMD3(0, -30, 25), focalLength: 3000)
        let estimate = try #require(CameraEstimate(homography: homography, imageSize: imageSize))

        #expect(abs(estimate.height - 25) < 1e-6)
        #expect(!CameraPlausibility().accepts(estimate, imageSize: imageSize))
    }

    @Test func failsWhenLookingStraightDown() {
        // 真上から見ると、焦点距離が決まらない。
        let homography = Homography(matrix: simd_double3x3(rows: [
            SIMD3(100, 0, 960),
            SIMD3(0, -100, 540),
            SIMD3(0, 0, 1)
        ]))

        #expect(CameraEstimate(homography: homography, imageSize: imageSize) == nil)
    }
}
