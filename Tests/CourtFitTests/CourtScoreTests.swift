@testable import CourtFit
import CoreGraphics
import simd
import Testing

struct CourtScoreTests {
    private let imageSize = TestCamera.imageSize
    private let homography = TestCamera.homography(camera: SIMD3(0, -12, 3), focalLength: 1500)

    @Test func exactTransformPasses() throws {
        let score = try #require(CourtScore(estimated: homography, truth: TestCamera.keypoints(homography)))

        #expect(score.errors.count == 12)
        #expect(score.maximumImageError < 1e-6)
        #expect(score.maximumCourtError < 1e-6)
        #expect(score.passes())
    }

    @Test func farPointsCostMoreOnCourtThanNearPoints() throws {
        // 同じ 3 ピクセルのずれでも、奥の点はコートの面では大きなずれになる。
        let shifted = TestCamera.keypoints(homography).mapValues { $0 + SIMD2(0, 3) }
        let score = try #require(CourtScore(estimated: homography, truth: shifted))

        let near = try #require(score.errors[.nearBaselineCenter])
        let far = try #require(score.errors[.farBaselineCenter])
        #expect(abs(near.image - 3) < 1e-6)
        #expect(abs(far.image - 3) < 1e-6)
        #expect(far.court > near.court * 3)
        #expect(!score.passes())
    }

    @Test func scoresOnlyKeypointsThatHaveTruth() throws {
        let truth = TestCamera.keypoints(homography).filter { CourtModel.corners.contains($0.key) }
        let score = try #require(CourtScore(estimated: homography, truth: truth))

        #expect(score.errors.count == 4)
    }

    @Test func failsWithoutTruth() {
        #expect(CourtScore(estimated: homography, truth: [:]) == nil)
    }

    @Test func outlineOfDetectedQuadGivesSameTransform() throws {
        let points = TestCamera.keypoints(homography)
        func normalized(_ keypoint: CourtKeypoint) throws -> CGPoint {
            let point = try #require(points[keypoint])
            return CGPoint(x: point.x / imageSize.width, y: 1 - point.y / imageSize.height)
        }
        let quad = try DetectedQuad(
            topLeft: normalized(.farLeftCorner), topRight: normalized(.farRightCorner),
            bottomRight: normalized(.nearRightCorner), bottomLeft: normalized(.nearLeftCorner)
        )

        let upright = try #require(Homography(courtOutline: quad, imageSize: imageSize, quarterTurned: false))
        let turned = try #require(Homography(courtOutline: quad, imageSize: imageSize, quarterTurned: true))

        #expect(try #require(CourtScore(estimated: upright, truth: points)).passes())
        #expect(try #require(CourtScore(estimated: turned, truth: points)).passes() == false)
    }
}
