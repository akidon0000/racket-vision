import simd

/// 候補を時間の向きにつなぎ、球を 1 つに決める。画像は見ない。
///
/// 候補ごとに仮の軌跡を伸ばし、続けてつながって、球の速さで動いたものを球とする。
/// 球が決まったあとは、その 1 本を追う。前の位置と速さから次の位置を見込み、その近くに候補が無ければ、
/// 近くだけを緩い条件で探し直す（`NearSearch`）。それでも無ければ、打たれたかバウンドしたとみて、
/// 少し広い範囲の候補へ移る。遠くの候補へは、すぐには移らない（選手の靴などへ飛ばないため）。
/// 球を見失っているあいだに、別の仮の軌跡が球と言えるようになったら、そちらへ移る。
struct BallTrackState {
    struct Output: Equatable {
        /// 中心（画素、左上が原点）。
        var center: SIMD2<Double>
        var radius: Double
        var confidence: Double
    }

    /// 見込みの位置（画素）と、そこからの距離（画素）を受けて、その近くを緩い条件で探した候補を返す。
    typealias NearSearch = (_ center: SIMD2<Double>, _ reach: Double) -> [BallCandidate]

    /// 1 フレームの時刻と、その前のフレームからの時間、映像の幅。
    private struct Frame {
        var time: Double
        var interval: Double
        var imageWidth: Double
    }

    /// 仮の軌跡を、球として出し始めるまでの時間（秒）。
    var confirmSeconds = 0.08
    /// 候補が無いまま、追跡を捨てるまでの時間（秒）。
    var loseSeconds = 0.3
    /// 緩い条件の候補だけで、追い続けてよい時間（秒）。これを超えたら、厳しい条件の候補が出るまで球を出さない。
    var looseSeconds = 0.5
    /// 球が 1 秒に動ける距離の上限（映像の幅に対する割合）。
    var maximumSpeed = 2.0
    /// 仮の軌跡を球とみなすのに要る、速さの下限（1 秒に動く距離の、映像の幅に対する割合）。
    /// 手に持った球や、立っている選手の靴のように、ゆっくり動くものを球にしない。
    /// ネット際の遅い球（奥では 1 秒に幅の 1 割ほど）を落とさない値にしてある。
    var minimumSpeed = 0.05
    /// 打たれて向きや速さが変わった球へ、すぐに移ってよい範囲を決める速さ（1 秒に動く距離の、映像の幅に対する割合）。
    /// 見込みの位置から、この速さで 1 フレームに動く距離までの候補へは、すぐに移る。
    var jumpSpeed = 0.75
    /// 追っている球にこの時間（秒）つなげなかったら、球と言えるようになった別の仮の軌跡へ移ってよい。
    var switchSeconds = 0.05
    /// 覚えておく仮の軌跡の数の上限。
    var maximumTentatives = 32
    /// 追っている球を出すのに要る、速さの下限（1 秒に動く距離の、映像の幅に対する割合）。直近 `outputWindow` 秒の始点から
    /// 終点への速さで見る。球を見失って、近くの靴や顔、客席に乗り移ったまま出し続けないため。
    /// 0 なら速さで絞らない。
    var outputSpeed = 0.12
    var outputWindow = 0.2
    /// 速さが下限を下回っても、この時間（秒）のうちに下限を超えていれば出す（頂点やバウンドで遅くなった球）。
    var holdSeconds = 0.3

    private var confirmed: BallTrack?
    private var tentatives = [BallTrack]()
    private var lastTime: Double?

    mutating func reset() {
        confirmed = nil
        tentatives = []
        lastTime = nil
    }

    /// 1 フレームぶんの候補を渡す。球が決まっていて、このフレームで見えていれば返す。
    /// `near` は、追っている球の見込みの位置の近くを、緩い条件で探す（渡さなければ、探さない）。
    mutating func update(
        candidates: [BallCandidate], time: Double, imageWidth: Double, near: NearSearch = { _, _ in [] }
    ) -> Output? {
        // 時刻が進んでいなければ（シーク、ループ）、前の軌跡とはつながらないので、やり直す。
        if let lastTime, time <= lastTime {
            reset()
        }
        // 最初のフレームでは、追っている球は無いので、前のフレームからの時間は使わない。
        let frame = Frame(time: time, interval: lastTime.map { time - $0 } ?? 0, imageWidth: imageWidth)
        lastTime = time
        var followed: BallTrack?
        var used: BallCandidate?
        if let track = confirmed {
            if time - track.lastTime > loseSeconds {
                confirmed = nil
            } else if let (next, candidate) = follow(track, candidates: candidates, frame: frame, near: near) {
                confirmed = next
                followed = next
                used = candidate
            }
        }
        // 仮の軌跡は、球を追っているあいだも伸ばす（追っている球につないだ候補は除く）。
        let others = candidates.filter { $0 != used }
        let fresh = grow(candidates: others, time: time, imageWidth: imageWidth)
        if var followed {
            let shows = shows(&followed, time: time, imageWidth: imageWidth)
            confirmed = followed
            return shows ? followed.output : nil
        }
        if var fresh, confirmed.map({ time - $0.lastTime > switchSeconds }) ?? true {
            let shows = shows(&fresh, time: time, imageWidth: imageWidth)
            confirmed = fresh
            tentatives = []
            return shows ? fresh.output : nil
        }
        return nil
    }

    /// 追っている球を、このフレームで出すか。遅いもの（止まった球、靴、客席）は出さない（`outputSpeed`、`holdSeconds`）。
    private func shows(_ track: inout BallTrack, time: Double, imageWidth: Double) -> Bool {
        guard outputSpeed > 0 else { return true }
        if let speed = track.recentSpeed(within: outputWindow), speed >= outputSpeed * imageWidth {
            track.lastFastTime = time
        }
        return track.lastFastTime.map { time - $0 <= holdSeconds } ?? false
    }

    private func reach(of track: BallTrack, time: Double, imageWidth: Double) -> Double {
        maximumSpeed * imageWidth * (time - track.lastTime) + 2 * track.radius
    }

    /// 決まった球を追う。見込みの位置の近くの候補を選ぶ。無ければ、近くだけを緩い条件で探す。
    /// それも無ければ、打たれたかバウンドして向きが変わったとみて、少し広い範囲の候補を選ぶ。
    /// つないだ軌跡と、つないだ候補（画面の全体から探した候補のとき）を返す。
    private func follow(
        _ track: BallTrack, candidates: [BallCandidate], frame: Frame, near: NearSearch
    ) -> (BallTrack, BallCandidate?)? {
        let time = frame.time
        let predicted = track.predictedPosition(at: time)
        let reach = reach(of: track, time: time, imageWidth: frame.imageWidth)
        let step = simd_distance(predicted, track.position)
        let tolerance = min(reach, max(4 * track.radius, 0.5 * step))
        // 向きが逆になると、見込みの位置から、1 フレームに動く距離の 2 倍まで外れる。
        let jump = min(
            reach,
            max(tolerance, 8 * track.radius, 2.5 * simd_length(track.velocity) * frame.interval, jumpSpeed * frame.imageWidth * frame.interval)
        )
        func distance(_ candidate: BallCandidate) -> Double {
            simd_distance(candidate.center, predicted)
        }
        let best = candidates.filter { track.accepts($0, within: reach) }.min { distance($0) < distance($1) }
        var next = track
        if let best, distance(best) <= tolerance {
            next.extend(with: best, at: time)
            return (next, best)
        }
        if time - track.lastStrictTime <= looseSeconds,
           let loose = near(predicted, tolerance)
               .filter({ track.hasSimilarSize($0) && distance($0) <= tolerance })
               .min(by: { distance($0) < distance($1) }) {
            next.extend(with: loose, at: time, isStrict: false)
            return (next, nil)
        }
        if let best, distance(best) <= jump {
            next.extend(with: best, at: time)
            return (next, best)
        }
        return nil
    }

    /// 仮の軌跡を伸ばす。球と言えるものが出たら、それを返す。
    private mutating func grow(candidates: [BallCandidate], time: Double, imageWidth: Double) -> BallTrack? {
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
        let started = candidates.map { BallTrack(startingAt: $0, time: time) }
        tentatives = Array((extended + started).sorted { $0.hits > $1.hits }.prefix(maximumTentatives))
        return extended.filter { isBall($0, time: time, imageWidth: imageWidth) }.max { $0.hits < $1.hits }
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

    /// 仮の軌跡が、球と言えるか。このフレームでつながり、十分な時間続き、球の速さで動いていること
    /// （その場でちらついているだけのものや、ゆっくり動くものは球にしない）。
    private func isBall(_ track: BallTrack, time: Double, imageWidth: Double) -> Bool {
        let moved = simd_distance(track.position, track.startPosition)
        return track.lastTime == time
            && track.hits >= 3
            && time - track.startTime >= confirmSeconds
            && moved >= 3 * track.radius
            && moved >= minimumSpeed * imageWidth * (time - track.startTime)
    }
}
