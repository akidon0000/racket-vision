import simd

/// 候補を時間の向きにつないだ、1 本の軌跡。座標は画素（左上が原点）、速さは画素/秒。
struct BallTrack {
    var position: SIMD2<Double>
    var velocity = SIMD2<Double>(0, 0)
    var radius: Double
    var score: Double
    var lastTime: Double
    /// 最後に、厳しい条件の候補（画面の全体から探した候補）をつないだ時刻。
    var lastStrictTime: Double
    let startTime: Double
    let startPosition: SIMD2<Double>
    /// つないだ候補の数。
    var hits = 1
    /// 最後に、球として出せる速さ（`BallTrackState.outputSpeed`）で動いていた時刻。
    var lastFastTime: Double?
    /// 直近につないだ位置と時刻（古い順、`historyLimit` 個まで）。直近の速さを見るため。
    private(set) var history: [(position: SIMD2<Double>, time: Double)]
    static let historyLimit = 24

    init(startingAt candidate: BallCandidate, time: Double) {
        position = candidate.center
        radius = candidate.radius
        score = candidate.score
        lastTime = time
        lastStrictTime = time
        startTime = time
        startPosition = candidate.center
        history = [(candidate.center, time)]
    }

    /// 直近 `seconds` 秒の、始点から終点への速さ（画素/秒）。
    /// 道のりではなく始点から終点で見るので、その場で揺れているだけのもの（客席、足踏み）は遅くなる。
    /// 点が 1 つだけなら nil。
    func recentSpeed(within seconds: Double) -> Double? {
        let recent = history.filter { lastTime - $0.time <= seconds }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return nil }
        return simd_distance(first.position, last.position) / (last.time - first.time)
    }

    /// 候補が、届く距離の中にあり、大きさが近いか。
    func accepts(_ candidate: BallCandidate, within reach: Double) -> Bool {
        simd_distance(candidate.center, position) <= reach && hasSimilarSize(candidate)
    }

    /// 候補の大きさが、追っている球に近いか。
    func hasSimilarSize(_ candidate: BallCandidate) -> Bool {
        candidate.radius <= radius * 2.5 && candidate.radius >= radius / 2.5
    }

    /// 速さから見込んだ、`time` での位置。
    func predictedPosition(at time: Double) -> SIMD2<Double> {
        position + velocity * (time - lastTime)
    }

    /// 候補をつなぐ。`time` は `lastTime` より後であること。`isStrict` は、厳しい条件の候補か。
    mutating func extend(with candidate: BallCandidate, at time: Double, isStrict: Bool = true) {
        let measured = (candidate.center - position) / (time - lastTime)
        // 打たれた直後やバウンドの直後に遅れないよう、新しい速さを重く見る。
        velocity = hits >= 2 ? velocity * 0.3 + measured * 0.7 : measured
        position = candidate.center
        radius = (radius + candidate.radius) / 2
        score = candidate.score
        lastTime = time
        if isStrict {
            lastStrictTime = time
        }
        hits += 1
        history.append((candidate.center, time))
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    var output: BallTrackState.Output {
        BallTrackState.Output(center: position, radius: radius, confidence: min(1, Double(hits) / 10) * score)
    }
}
