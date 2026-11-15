@testable import CourtFit
import simd
import Testing

struct CourtAlignmentTests {
    private static let imageWidth = 1920
    private static let imageHeight = 1080

    /// 正しい変換。
    private let truth = TestCamera.homography(camera: SIMD3(8, -10, 2.5), focalLength: 1400)

    /// 四隅に、手の指定を模した固定のずれを足した出発点（near の左、near の右、far の右、far の左）。
    private func startingHomography(from base: Homography) throws -> Homography {
        let shifts: [SIMD2<Double>] = [
            SIMD2(8, -6),
            SIMD2(-7, 5),
            SIMD2(5, 9),
            SIMD2(-9, -4)
        ]
        let model = CourtModel.pickleball
        let courtCorners = CourtModel.corners.map { model.position(of: $0) }
        let imageCorners = try courtCorners.enumerated().map { index, corner -> SIMD2<Double> in
            let projected = try #require(base.project(corner))
            return projected + shifts[index]
        }
        return try #require(Homography(from: courtCorners, to: imageCorners))
    }

    /// 変換で図面の線を画像に写し、線の上を 1、それ以外を 0 にした画像を、3×3 のぼかしで滑らかにする。
    private func syntheticEdges(for homography: Homography) throws -> EdgeMap {
        let width = Self.imageWidth
        let height = Self.imageHeight
        var values = [Float](repeating: 0, count: width * height)
        let model = CourtModel.pickleball
        for line in CourtModel.lines {
            let start = model.position(of: line.start)
            let end = model.position(of: line.end)
            for index in 0...2000 {
                let fraction = Double(index) / 2000
                guard let pixel = homography.project(start + (end - start) * fraction) else { continue }
                // 小数の位置を、近い 4 つの画素に按分して置く（丸めによる誤差を減らす）。
                let x0 = Int(pixel.x.rounded(.down))
                let y0 = Int(pixel.y.rounded(.down))
                let fx = Float(pixel.x - Double(x0))
                let fy = Float(pixel.y - Double(y0))
                for (dx, dy, weight) in [(0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)] {
                    let x = x0 + dx
                    let y = y0 + dy
                    guard x >= 0, y >= 0, x < width, y < height else { continue }
                    values[y * width + x] = max(values[y * width + x], weight)
                }
            }
        }
        var blurred = [Float](repeating: 0, count: width * height)
        let kernel: [Float] = [1, 2, 1]
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                var sum: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        sum += values[(y + dy) * width + (x + dx)] * kernel[dx + 1] * kernel[dy + 1]
                    }
                }
                blurred[y * width + x] = sum / 16
            }
        }
        return try #require(EdgeMap(width: width, height: height, values: blurred))
    }

    @Test func recoversKnownHomography() throws {
        let edges = try syntheticEdges(for: truth)
        let initial = try startingHomography(from: truth)

        let result = try #require(aligned(edges, from: initial))
        let score = try #require(CourtScore(estimated: result.homography, truth: TestCamera.keypoints(truth)))

        #expect(score.maximumImageError <= 1.5, "最大のずれ \(score.maximumImageError)px、反復 \(result.iterations) 回、残差内の割合 \(result.inlierRatio)")
    }

    @Test func keepsCorrectHomographyWhenStarting() throws {
        let edges = try syntheticEdges(for: truth)

        let result = try #require(aligned(edges, from: truth))
        let score = try #require(CourtScore(estimated: result.homography, truth: TestCamera.keypoints(truth)))

        #expect(score.maximumImageError <= 0.5, "最大のずれ \(score.maximumImageError)px、反復 \(result.iterations) 回、残差内の割合 \(result.inlierRatio)")
    }

    @Test func returnsNilForEmptyEdges() throws {
        let empty = try #require(EdgeMap(
            width: 200,
            height: 100,
            values: [Float](repeating: 0, count: 200 * 100)
        ))

        #expect(aligned(empty, from: truth) == nil)
    }
}
