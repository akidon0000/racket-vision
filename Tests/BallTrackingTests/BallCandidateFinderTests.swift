@testable import BallTracking
import simd
import Testing

struct BallCandidateFinderTests {
    /// 球が 1 フレームに (12, 4) 画素ずつ動く、3 枚のフレーム。`decorate` で、各フレームに物を足す。
    private func movingBall(decorate: (inout SyntheticFrame, Int) -> Void = { _, _ in }) -> [SyntheticFrame] {
        (0..<3).map { index in
            var frame = SyntheticFrame()
            decorate(&frame, index)
            frame.fillCircle(centerX: 76 + 12 * Double(index), centerY: 92 + 4 * Double(index), radius: 4, color: .ball)
            return frame
        }
    }

    private func find(_ frames: [SyntheticFrame]) -> BallCandidateFinder.Result {
        BallCandidateFinder().find(current: frames[2].image, previous: frames[1].image, beforePrevious: frames[0].image)
    }

    @Test func findsMovingBall() throws {
        let result = find(movingBall())
        let candidate = try #require(result.candidates.first)
        #expect(result.candidates.count == 1)
        #expect(simd_distance(candidate.center, SIMD2(100, 100)) <= 0.5)
        #expect(abs(candidate.radius - 4) <= 0.5)
        #expect(result.movingRatio < 0.01)
    }

    @Test func ignoresStillBallColoredThings() {
        let result = find(movingBall { frame, _ in
            // 止まった黄色（ロゴ）と、止まった球。
            frame.fillRect(x: 500, y: 40, width: 30, height: 30, color: .ball)
            frame.fillCircle(centerX: 300, centerY: 200, radius: 4, color: .ball)
        })
        #expect(result.candidates.count == 1)
    }

    @Test func ignoresMovingThingsOfOtherColorsAndSizes() {
        let result = find(movingBall { frame, index in
            // 動く灰色の塊（選手）と、動く大きな黄色の塊（黄色い服）。どちらも 1 フレームに 20 画素動く。
            frame.fillRect(x: 200 + 20 * index, y: 200, width: 60, height: 120, color: .gray)
            frame.fillRect(x: 400 + 20 * index, y: 150, width: 80, height: 80, color: .ball)
        })
        #expect(result.candidates.count == 1)
    }

    @Test func reportsSceneChangeWithoutCandidates() {
        var sequence = movingBall()
        sequence[2] = SyntheticFrame(background: .gray)
        sequence[2].fillCircle(centerX: 100, centerY: 100, radius: 4, color: .ball)
        let result = find(sequence)
        #expect(result.movingRatio > 0.9)
        #expect(result.candidates.isEmpty)
    }

    @Test func survivesWholeFrameOfMovingBallColor() {
        // 画面全体が球の色に変わる（黄色い壁をカメラが横切る）。
        let sequence = [SyntheticFrame(), SyntheticFrame(), SyntheticFrame(background: .ball)]
        let result = find(sequence)
        #expect(result.candidates.isEmpty)
    }
}
