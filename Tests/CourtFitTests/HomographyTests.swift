@testable import CourtFit
import simd
import Testing

struct HomographyTests {
    @Test func recoversTransformFromFourCorners() throws {
        let truth = TestCamera.homography(camera: SIMD3(8, -10, 2.5), focalLength: 1400)
        let model = CourtModel.pickleball
        let courtPoints = CourtModel.corners.map { model.position(of: $0) }
        let imagePoints = try courtPoints.map { try #require(truth.project($0)) }

        let estimated = try #require(Homography(from: courtPoints, to: imagePoints))

        for keypoint in CourtKeypoint.allCases {
            let expected = try #require(truth.project(model.position(of: keypoint)))
            let actual = try #require(estimated.project(model.position(of: keypoint)))
            #expect(simd_length(expected - actual) < 1e-6)
        }
    }

    @Test func inverseMapsBack() throws {
        let homography = TestCamera.homography(camera: SIMD3(0, -12, 3), focalLength: 1500)
        let point = SIMD2<Double>(1.5, -2)
        let projected = try #require(homography.project(point))
        let back = try #require(homography.inverse?.project(projected))
        #expect(simd_length(back - point) < 1e-9)
    }

    @Test func failsWithTooFewPoints() {
        let points: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1)]
        #expect(Homography(from: points, to: points) == nil)
    }

    @Test func failsWhenPointsAreOnOneLine() {
        let points: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(2, 0), SIMD2(3, 0)]
        #expect(Homography(from: points, to: points) == nil)
    }
}
