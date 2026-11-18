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

    @Test func findsWholeBallWhenItMovesSlowly() throws {
        // 半径 6 の球が、1 フレームに 2 画素だけ動く。動いた画素は縁だけだが、色でつながる球の全体を取る。
        let sequence = (0..<3).map { index in
            var frame = SyntheticFrame()
            frame.fillCircle(centerX: 196 + 2 * Double(index), centerY: 100, radius: 6, color: .ball)
            return frame
        }
        let result = find(sequence)
        let candidate = try #require(result.candidates.first)
        #expect(result.candidates.count == 1)
        #expect(simd_distance(candidate.center, SIMD2(200, 100)) <= 0.5)
        #expect(abs(candidate.radius - 6) <= 0.5)
    }

    @Test func ignoresBallColoredSpotOnLargeBallColoredThing() {
        // 黄色い服（止まっている）の上で、球の色のまま少しだけ明るさが変わる（しわ、影）。服の全体につながるので、球にしない。
        let flicker = SyntheticColor(red: 160, green: 180, blue: 60)
        let result = find(movingBall { frame, index in
            frame.fillRect(x: 400, y: 150, width: 80, height: 80, color: .ball)
            if index == 2 {
                frame.fillCircle(centerX: 440, centerY: 190, radius: 4, color: flicker)
            }
        })
        #expect(result.candidates.count == 1)
    }

    /// 薄く写った球（`yellowGreen` には入らず、`yellowGreenWide` には入る色）。
    private let faintBall = SyntheticColor(red: 140, green: 160, blue: 100)

    @Test func findsFaintBallNearGivenPosition() throws {
        var previous = SyntheticFrame()
        previous.fillCircle(centerX: 196, centerY: 100, radius: 4, color: faintBall)
        var current = SyntheticFrame()
        current.fillCircle(centerX: 200, centerY: 100, radius: 4, color: faintBall)
        let finder = BallCandidateFinder()
        // 画面の全体から探すときの条件（色）では、候補にならない。
        #expect(finder.find(current: current.image, previous: previous.image, beforePrevious: previous.image).candidates.isEmpty)
        let near = finder.findNear(center: SIMD2(204, 100), reach: 20, current: current.image, previous: previous.image)
        let candidate = try #require(near.first)
        #expect(near.count == 1)
        #expect(simd_distance(candidate.center, SIMD2(200, 100)) <= 0.5)
        // 窓の外は探さない。
        #expect(finder.findNear(center: SIMD2(300, 100), reach: 20, current: current.image, previous: previous.image).isEmpty)
    }

    @Test func findNearIgnoresStillThings() {
        var frame = SyntheticFrame()
        frame.fillCircle(centerX: 200, centerY: 100, radius: 4, color: .ball)
        let near = BallCandidateFinder().findNear(center: SIMD2(200, 100), reach: 20, current: frame.image, previous: frame.image)
        #expect(near.isEmpty)
    }
}
