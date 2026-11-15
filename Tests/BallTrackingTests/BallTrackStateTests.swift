@testable import BallTracking
import simd
import Testing

struct BallTrackStateTests {
    private let frame = 1.0 / 60

    private func candidate(_ x: Double, _ y: Double) -> BallCandidate {
        BallCandidate(center: SIMD2(x, y), radius: 4, score: 0.8)
    }

    /// 球を 1 フレームに `step` ずつ動かす。`start` は `frames` の最初のフレームの位置。フレームごとの結果を返す。
    private func run(
        _ state: inout BallTrackState, from start: SIMD2<Double>, step: SIMD2<Double>, frames: Range<Int>
    ) -> [BallTrackState.Output?] {
        frames.map { index in
            let center = start + step * Double(index - frames.lowerBound)
            return state.update(candidates: [candidate(center.x, center.y)], time: Double(index) * frame, imageWidth: 640)
        }
    }

    @Test func confirmsBallMovingInALine() throws {
        var state = BallTrackState()
        let outputs = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<8)
        // 0.08 秒たつ 6 枚目（番号 5）から出す。
        #expect(outputs[0..<5].allSatisfy { $0 == nil })
        let first = try #require(outputs[5])
        #expect(first.center == SIMD2(160, 100))
        #expect(outputs[6] != nil && outputs[7] != nil)
    }

    @Test func ignoresCandidateThatStaysInPlace() {
        var state = BallTrackState()
        let outputs = run(&state, from: SIMD2(300, 200), step: SIMD2(0, 0), frames: 0..<40)
        #expect(outputs.allSatisfy { $0 == nil })
    }

    @Test func followsBallAfterBounce() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(6, 10), frames: 0..<6)
        // 向きが変わっても、追い続ける。
        let after = run(&state, from: SIMD2(136, 140), step: SIMD2(6, -10), frames: 6..<12)
        #expect(after.allSatisfy { $0 != nil })
        #expect(after.last??.center == SIMD2(166, 90))
    }

    @Test func prefersCandidateNearPrediction() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 見込みの位置 (172, 100) の候補と、近くの別の候補。
        let output = state.update(candidates: [candidate(150, 110), candidate(172, 100)], time: 6 * frame, imageWidth: 640)
        #expect(output?.center == SIMD2(172, 100))
    }

    @Test func keepsTrackThroughShortGap() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 5 フレーム（0.083 秒）隠れる。
        for index in 6..<11 {
            #expect(state.update(candidates: [], time: Double(index) * frame, imageWidth: 640) == nil)
        }
        let output = state.update(candidates: [candidate(232, 100)], time: 11 * frame, imageWidth: 640)
        #expect(output?.center == SIMD2(232, 100))
    }

    @Test func dropsTrackAfterLoseSeconds() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 0.35 秒あとに、近くに候補が出ても、追跡は捨ててあるので、すぐには出さない。
        let output = state.update(candidates: [candidate(170, 100)], time: 5 * frame + 0.35, imageWidth: 640)
        #expect(output == nil)
    }

    @Test func restartsWhenTimeDoesNotAdvance() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 同じ時刻と、戻った時刻。どちらも落ちずに、追跡をやり直す。
        #expect(state.update(candidates: [candidate(172, 100)], time: 5 * frame, imageWidth: 640) == nil)
        #expect(state.update(candidates: [candidate(184, 100)], time: 1 * frame, imageWidth: 640) == nil)
        let outputs = run(&state, from: SIMD2(196, 100), step: SIMD2(12, 0), frames: 2..<8)
        #expect(outputs.last??.center == SIMD2(256, 100))
    }
}
