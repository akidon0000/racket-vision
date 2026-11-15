import simd

/// 候補を時間の向きにつなぎ、球を 1 つに決める。画像は見ない。
///
/// 追跡が無いあいだは、候補ごとに仮の軌跡を伸ばし、続けてつながって動いたものを球とする。
/// 球が決まったあとは、その 1 本だけを追う。
struct BallTrackState {
    struct Output: Equatable {
        /// 中心（画素、左上が原点）。
        var center: SIMD2<Double>
        var radius: Double
        var confidence: Double
    }

    /// 仮の軌跡を、球として出し始めるまでの時間（秒）。
    var confirmSeconds = 0.08
    /// 候補が無いまま、追跡を捨てるまでの時間（秒）。
    var loseSeconds = 0.3
    /// 球が 1 秒に動ける距離の上限（映像の幅に対する割合）。
    var maximumSpeed = 2.0
    /// 覚えておく仮の軌跡の数の上限。
    var maximumTentatives = 32

    private var confirmed: BallTrack?
    private var tentatives = [BallTrack]()
    private var lastTime: Double?

    mutating func reset() {
        confirmed = nil
        tentatives = []
        lastTime = nil
    }

    /// 1 フレームぶんの候補を渡す。球が決まっていて、このフレームで見えていれば返す。
    mutating func update(candidates: [BallCandidate], time: Double, imageWidth: Double) -> Output? {
        // 時刻が進んでいなければ（シーク、ループ）、前の軌跡とはつながらないので、やり直す。
        if let lastTime, time <= lastTime {
            reset()
        }
        lastTime = time
        if let track = confirmed {
            if time - track.lastTime > loseSeconds {
                confirmed = nil
            } else {
                return follow(track, candidates: candidates, time: time, imageWidth: imageWidth)
            }
        }
        return grow(candidates: candidates, time: time, imageWidth: imageWidth)
    }

    private func reach(of track: BallTrack, time: Double, imageWidth: Double) -> Double {
        maximumSpeed * imageWidth * (time - track.lastTime) + 2 * track.radius
    }

    /// 決まった球を追う。打たれると向きが変わるので、前の位置から届く候補のうち、見込みの位置に一番近いものを選ぶ。
    private mutating func follow(_ track: BallTrack, candidates: [BallCandidate], time: Double, imageWidth: Double) -> Output? {
        let predicted = track.predictedPosition(at: time)
        let reach = reach(of: track, time: time, imageWidth: imageWidth)
        let near = candidates.filter { track.accepts($0, within: reach) }
        guard let best = near.min(by: { simd_distance($0.center, predicted) < simd_distance($1.center, predicted) }) else {
            return nil
        }
        var next = track
        next.extend(with: best, at: time)
        confirmed = next
        return next.output
    }

    /// 仮の軌跡を伸ばし、球と言えるものが出たら、それを追跡にする。
    private mutating func grow(candidates: [BallCandidate], time: Double, imageWidth: Double) -> Output? {
        var extended = [BallTrack]()
        for track in tentatives where time - track.lastTime <= confirmSeconds {
            let matches = matches(for: track, in: candidates, time: time, imageWidth: imageWidth)
            if matches.isEmpty {
                // このフレームでは見えなかった。confirmSeconds のあいだは残す。
                extended.append(track)
            }
            for candidate in matches {
                var next = track
                next.extend(with: candidate, at: time)
                extended.append(next)
            }
        }
        if let ball = extended.filter({ isBall($0, time: time) }).max(by: { $0.hits < $1.hits }) {
            confirmed = ball
            tentatives = []
            return ball.output
        }
        let started = candidates.map { BallTrack(startingAt: $0, time: time) }
        tentatives = Array((extended + started).sorted { $0.hits > $1.hits }.prefix(maximumTentatives))
        return nil
    }

    /// 仮の軌跡につながる候補。始まったばかり（速さが分からない）なら届く候補を全部、速さが分かれば見込みの位置の近くの 1 つ。
    private func matches(for track: BallTrack, in candidates: [BallCandidate], time: Double, imageWidth: Double) -> [BallCandidate] {
        let reach = reach(of: track, time: time, imageWidth: imageWidth)
        let near = candidates.filter { track.accepts($0, within: reach) }
        guard track.hits >= 2 else { return near }
        let predicted = track.predictedPosition(at: time)
        let tolerance = max(4 * track.radius, 0.5 * simd_distance(predicted, track.position))
        guard let nearest = near.min(by: { simd_distance($0.center, predicted) < simd_distance($1.center, predicted) }),
              simd_distance(nearest.center, predicted) <= tolerance else {
            return []
        }
        return [nearest]
    }

    /// 仮の軌跡が、球と言えるか。このフレームでつながり、十分な時間続き、その場でちらついているだけでないこと。
    private func isBall(_ track: BallTrack, time: Double) -> Bool {
        track.lastTime == time
            && track.hits >= 3
            && time - track.startTime >= confirmSeconds
            && simd_distance(track.position, track.startPosition) >= 3 * track.radius
    }
}
