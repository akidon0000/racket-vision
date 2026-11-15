import simd

/// 候補を時間の向きにつないだ、1 本の軌跡。座標は画素（左上が原点）、速さは画素/秒。
struct BallTrack {
    var position: SIMD2<Double>
    var velocity = SIMD2<Double>(0, 0)
    var radius: Double
    var score: Double
    var lastTime: Double
    let startTime: Double
    let startPosition: SIMD2<Double>
    /// つないだ候補の数。
    var hits = 1

    init(startingAt candidate: BallCandidate, time: Double) {
        position = candidate.center
        radius = candidate.radius
        score = candidate.score
        lastTime = time
        startTime = time
        startPosition = candidate.center
    }

    /// 候補が、届く距離の中にあり、大きさが近いか。
    func accepts(_ candidate: BallCandidate, within reach: Double) -> Bool {
        simd_distance(candidate.center, position) <= reach
            && candidate.radius <= radius * 2.5
            && candidate.radius >= radius / 2.5
    }

    /// 速さから見込んだ、`time` での位置。
    func predictedPosition(at time: Double) -> SIMD2<Double> {
        position + velocity * (time - lastTime)
    }

    /// 候補をつなぐ。`time` は `lastTime` より後であること。
    mutating func extend(with candidate: BallCandidate, at time: Double) {
        let measured = (candidate.center - position) / (time - lastTime)
        // 打たれた直後やバウンドの直後に遅れないよう、新しい速さを重く見る。
        velocity = hits >= 2 ? velocity * 0.3 + measured * 0.7 : measured
        position = candidate.center
        radius = (radius + candidate.radius) / 2
        score = candidate.score
        lastTime = time
        hits += 1
    }

    var output: BallTrackState.Output {
        BallTrackState.Output(center: position, radius: radius, confidence: min(1, Double(hits) / 10) * score)
    }
}
