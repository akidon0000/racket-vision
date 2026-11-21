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

    @Test func hidesSlowCandidateLikeWalkingShoe() {
        var state = BallTrackState()
        // 1 フレームに 1 画素（1 秒に幅の 9%）。球と決める速さ（5%）は超えるが、出す速さ（12%）に届かない。
        let outputs = run(&state, from: SIMD2(100, 300), step: SIMD2(1, 0), frames: 0..<60)
        #expect(outputs.allSatisfy { $0 == nil })
    }

    @Test func keepsShowingBallBrieflyAfterItSlowsDown() {
        var state = BallTrackState()
        // 速く飛んだあと（1 秒に幅の約 110%）、頂点やバウンドのように、ほとんど動かなくなる。
        let fast = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<10)
        #expect(fast[9] != nil)
        let slow = run(&state, from: SIMD2(220, 100), step: SIMD2(0.2, 0), frames: 10..<50)
        // 速さは直近 0.2 秒で見て、下回ってからも 0.3 秒は出す。遅くなってから 0.5 秒（30 フレーム）たつと出さない。
        #expect(slow[0..<15].allSatisfy { $0 != nil })
        #expect(slow[32..<40].allSatisfy { $0 == nil })
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

    @Test func searchesNearPredictionWhenNoCandidateIsThere() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        var asked = [SIMD2<Double>]()
        // 候補が無いフレーム。見込みの位置 (172, 100) の近くを探し直し、そこで見つけた球を追う。
        let output = state.update(candidates: [], time: 6 * frame, imageWidth: 640) { center, _ in
            asked.append(center)
            return [candidate(171, 101)]
        }
        #expect(asked == [SIMD2(172, 100)])
        #expect(output?.center == SIMD2(171, 101))
    }

    @Test func prefersLooseCandidateNearPredictionOverFarCandidate() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 届く距離にある別の候補（選手の靴など）より、見込みの位置の近くで探し直した球を選ぶ。
        let output = state.update(candidates: [candidate(150, 140)], time: 6 * frame, imageWidth: 640) { _, _ in
            [candidate(172, 100)]
        }
        #expect(output?.center == SIMD2(172, 100))
    }

    @Test func doesNotSearchNearBeforeBallIsConfirmed() {
        var state = BallTrackState()
        var asked = 0
        for index in 0..<3 {
            _ = state.update(candidates: [candidate(100 + 12 * Double(index), 100)], time: Double(index) * frame, imageWidth: 640) { _, _ in
                asked += 1
                return []
            }
        }
        #expect(asked == 0)
    }

    @Test func stopsFollowingLooseCandidatesAfterLooseSeconds() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 緩い条件の候補だけが続く。0.5 秒（30 フレーム）を超えたら、球を出さない。
        var outputs = [BallTrackState.Output?]()
        for index in 6..<50 {
            let center = SIMD2(100 + 12 * Double(index), 100)
            outputs.append(state.update(candidates: [], time: Double(index) * frame, imageWidth: 640) { _, _ in
                [candidate(center.x, center.y)]
            })
        }
        #expect(outputs[0..<30].allSatisfy { $0 != nil })
        #expect(outputs[31...].allSatisfy { $0 == nil })
    }

    @Test func doesNotJumpToFarCandidate() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 球が見えなくなり、離れたところ（選手の靴など）に候補が出続ける。ゆっくりしか動かないので、球にしない。
        let outputs = (6..<30).map { index in
            state.update(candidates: [candidate(170 + 0.5 * Double(index), 180)], time: Double(index) * frame, imageWidth: 640)
        }
        #expect(outputs.allSatisfy { $0 == nil })
    }

    @Test func switchesToNewBallAfterLosingTrack() {
        var state = BallTrackState()
        _ = run(&state, from: SIMD2(100, 100), step: SIMD2(12, 0), frames: 0..<6)
        // 球が離れたところに現れて、球の速さで動く（選手に隠れているあいだに打ち返された）。0.08 秒たったら、そちらを追う。
        let outputs = run(&state, from: SIMD2(260, 200), step: SIMD2(-12, 4), frames: 6..<14)
        #expect(outputs[0..<5].allSatisfy { $0 == nil })
        #expect(outputs[5]?.center == SIMD2(200, 220))
        #expect(outputs[7]?.center == SIMD2(176, 228))
    }

    @Test func ignoresSlowlyMovingCandidate() {
        var state = BallTrackState()
        // 1 フレームに 0.4 画素（1 秒に 24 画素、幅の 3.75%）。手に持った球や、立っている選手の靴。
        let outputs = run(&state, from: SIMD2(300, 200), step: SIMD2(0.4, 0), frames: 0..<60)
        #expect(outputs.allSatisfy { $0 == nil })
    }

    @Test func keepsFollowingBallWhileAnotherThingMoves() {
        var state = BallTrackState()
        // 球を追っているあいだに、別のもの（もう 1 つの球など）が球の速さで動いても、移らない。
        let outputs = (0..<20).map { index in
            state.update(
                candidates: [candidate(100 + 12 * Double(index), 100), candidate(500 - 12 * Double(index), 300)],
                time: Double(index) * frame, imageWidth: 640
            )
        }
        #expect(outputs[19]?.center.y == 100 || outputs[19]?.center.y == 300)
        let followed = outputs[19]?.center.y
        #expect(outputs[8...].allSatisfy { $0?.center.y == followed })
    }
}
