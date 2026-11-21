import CoreGraphics
import CourtFit
import Foundation
import simd

/// コートにいる選手を選び、同じ人に同じ番号を付け続ける。
///
/// フレームごとの骨格（観客や審判も入る）を渡すと、足元がコートの中かその近くにある人を選手の候補にし、
/// 前のフレームの選手と、足元の近さと見た目（服の色）でつなぐ。つながらなかった候補は、空いている番号で新しい選手にする。
/// 手前と奥に、それぞれ `maximumPlayers` の半分まで（ダブルスなら 2 人ずつ）。
///
/// 選手がすれ違うと、番号が入れ替わりやすい。見た目を覚えておき、入れ替わったほうが見た目が合う状態が続いたら、番号を戻す。
/// 見失った選手が戻ってきたときも、覚えている見た目に近い番号を付ける。
public struct CourtPlayerTracker: Sendable {
    /// 追う選手の数の上限（ダブルスは 4、シングルスは 2）。
    public var maximumPlayers: Int
    /// 新しい選手を、出し始めるまでの時間（秒）。一瞬だけ出た人（誤検出、横切る人）を選手にしない。
    public var confirmSeconds: TimeInterval = 0.2
    /// 選手が見つからないまま、番号を空けるまでの時間（秒）。
    public var loseSeconds: TimeInterval = 1.0
    /// 出し始める前の選手が見つからないまま、捨てるまでの時間（秒）。
    public var tentativeLoseSeconds: TimeInterval = 0.25
    /// 前のフレームの選手とつなぐときの、足元のずれの上限（身長に対する割合）。時間がたつほど広げる。
    public var reach = 0.5
    /// 選手が 1 秒に動ける距離の上限（身長に対する割合）。
    public var maximumSpeed = 4.0
    /// 選手の骨格が見つからないフレームで、少し前の骨格をそのまま出し続ける時間（秒）。0 なら、出さない。
    public var holdSeconds: TimeInterval = 0.5
    /// 前のフレームの選手とつなぐときに、見た目の違い（0〜1）に掛ける重み。足元のずれ（身長に対する割合）に足す。
    public var appearanceWeight = 2.0
    /// 番号ごとに覚えている見た目を、見つけた見た目へ近づける速さ（1 フレームあたり、0〜1）。
    public var rememberRate = 0.02
    /// 2 人の番号を入れ替えたほうが、見た目の違いの合計がこれより小さくなる状態が `swapFrames` 回続いたら、入れ替える。
    public var swapMargin = 0.08
    public var swapFrames = 3
    /// 番号が空いていないとき、出している選手がこれより多く（m）コートの外にいれば、コートの中に近い候補に番号を譲る。
    public var evictMargin = 1.0

    private var tracks = [Track]()
    private var lastTime: TimeInterval?
    /// 番号ごとに覚えている、選手の見た目。ゆっくり直す（取り違えた相手の見た目に、すぐには染まらないように）。
    private var remembered = [Int: PoseAppearance]()
    /// 番号の組ごとの、「入れ替えたほうが見た目が合う」が続いた回数。
    private var swapCounts = [Int: Int]()

    public init(maximumPlayers: Int = 4) {
        self.maximumPlayers = maximumPlayers
    }

    /// 追跡を捨てて、最初からやり直す。
    public mutating func reset() {
        tracks = []
        lastTime = nil
        remembered = [:]
        swapCounts = [:]
    }

    /// 1 フレームぶんの骨格を渡す。このフレームで見つかった選手を、番号の順に返す。
    /// `court` は、そのフレームのコート（分からなければ nil）。`imageSize` は、映像の大きさ（画素）。
    /// `appearance` は、骨格から見た目（服の色）を取る（渡さなければ、見た目は使わない）。
    public mutating func update(
        poses: [BodyPose], court: CourtPlane?, time: TimeInterval, imageSize: CGSize,
        appearance: (BodyPose) -> PoseAppearance? = { _ in nil }
    ) -> [CourtPlayer] {
        // 時刻が進んでいなければ（シーク、ループ）、前の選手とはつながらないので、やり直す。
        if let lastTime, time <= lastTime {
            reset()
        }
        lastTime = time
        let aspect = imageSize.height > 0 ? Double(imageSize.width / imageSize.height) : 1
        var candidates = PlayerCandidateFilter().candidates(from: poses, court: court, aspect: aspect)
        for index in candidates.indices {
            candidates[index].appearance = appearance(candidates[index].pose)
        }
        tracks.removeAll { time - $0.lastTime > ($0.isConfirmed(at: $0.lastTime, after: confirmSeconds) ? loseSeconds : tentativeLoseSeconds) }
        var matched = Set<Int>()
        let pairs = pairs(candidates: candidates, time: time)
        correctSwaps(pairs: pairs, candidates: candidates, time: time)
        for (trackIndex, candidateIndex) in pairs {
            tracks[trackIndex].extend(with: candidates[candidateIndex], at: time)
            matched.insert(candidateIndex)
            if let seen = candidates[candidateIndex].appearance, tracks[trackIndex].isConfirmed(at: time, after: confirmSeconds) {
                let id = tracks[trackIndex].id
                remembered[id] = remembered[id]?.blended(with: seen, rate: rememberRate) ?? seen
            }
        }
        candidates = candidates.enumerated().filter { !matched.contains($0.offset) }.map(\.element)
        for candidate in candidates {
            guard let id = freeID(for: candidate) ?? takeID(for: candidate, time: time) else { continue }
            tracks.append(Track(id: id, candidate: candidate, time: time))
        }
        return tracks
            .filter { time - $0.lastTime <= holdSeconds && $0.isConfirmed(at: $0.lastTime, after: confirmSeconds) }
            .sorted { $0.id < $1.id }
            .map {
                CourtPlayer(
                    id: $0.id, pose: $0.pose, side: $0.side, courtPosition: $0.courtPosition, firstSeen: $0.startTime,
                    isDetected: $0.lastTime == time, appearance: $0.lastAppearance
                )
            }
    }

    /// この骨格を渡したときに、見つからないままになる選手のまわりの範囲（正規化座標）。
    /// ここをもう一度、広さを変えて検出すると、取りこぼした選手を拾えることがある（Vision は、範囲の中での人の大きさで
    /// 見つけやすさが変わる）。`scales` は、選手の大きさに対する範囲の広さ。
    public func missingRegions(
        poses: [BodyPose], court: CourtPlane?, time: TimeInterval, imageSize: CGSize, scales: [Double] = [2.0, 4.0]
    ) -> [CGRect] {
        var copy = self
        _ = copy.update(poses: poses, court: court, time: time, imageSize: imageSize)
        let aspect = imageSize.height > 0 ? Double(imageSize.width / imageSize.height) : 1
        let missing = copy.tracks.filter { $0.lastTime != time && $0.isConfirmed(at: $0.lastTime, after: confirmSeconds) }
        return scales.flatMap { scale in missing.compactMap { region(around: $0, aspect: aspect, scale: scale, minimumSize: 0.08) } }
    }

    /// 追っている選手の数（出し始める前の選手も入る）。
    public var trackedCount: Int { tracks.count }

    /// 追っている選手のまわりの範囲（正規化座標、左下が原点）。次のフレームで、ここを拡大して骨格を検出すると、
    /// 小さく写った選手も取りやすい。範囲は、選手の大きさの `scale` 倍の正方形（画素で）。
    /// Vision は、人が範囲いっぱいに写っていると見つけられないので、人が範囲の 3 分の 1 くらいになる広さにする。
    /// `aspect` は、映像の横 ÷ 縦。
    public func searchRegions(aspect: Double, scale: Double = 2.8, minimumSize: Double = 0.12) -> [CGRect] {
        tracks.compactMap { region(around: $0, aspect: aspect, scale: scale, minimumSize: minimumSize) }
    }

    /// 選手のまわりの、選手の大きさの `scale` 倍の正方形（画素で）。
    private func region(around track: Track, aspect: Double, scale: Double, minimumSize: Double) -> CGRect? {
        guard let box = track.pose.boundingBox else { return nil }
        // 映像の幅を 1 とした長さで、正方形の 1 辺を決める。しゃがむと骨格の高さが縮むので、ならした身長も見る。
        let side = max(max(Double(box.width), Double(box.height) / aspect, track.height) * scale, minimumSize)
        let rect = CGRect(
            x: Double(box.midX) - side / 2, y: Double(box.midY) - side * aspect / 2, width: side, height: side * aspect
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return rect.isNull || rect.isEmpty ? nil : rect
    }

    /// 選手と候補を、足元の近い順につなぐ（選手の番号と候補の番号の組）。
    private func pairs(candidates: [PlayerCandidate], time: TimeInterval) -> [(Int, Int)] {
        var costs = [(cost: Double, track: Int, candidate: Int)]()
        for (trackIndex, track) in tracks.enumerated() {
            for (candidateIndex, candidate) in candidates.enumerated() {
                guard var cost = track.cost(of: candidate, at: time, reach: reach, maximumSpeed: maximumSpeed) else { continue }
                if let known = remembered[track.id], let seen = candidate.appearance, let difference = known.distance(to: seen) {
                    cost += appearanceWeight * difference
                }
                costs.append((cost, trackIndex, candidateIndex))
            }
        }
        var usedTracks = Set<Int>()
        var usedCandidates = Set<Int>()
        var result = [(Int, Int)]()
        for entry in costs.sorted(by: { $0.cost < $1.cost }) {
            guard !usedTracks.contains(entry.track), !usedCandidates.contains(entry.candidate) else { continue }
            usedTracks.insert(entry.track)
            usedCandidates.insert(entry.candidate)
            result.append((entry.track, entry.candidate))
        }
        return result
    }

    /// その側の選手に使う番号。コートが分かっているときは、手前が前半の番号、奥が後半の番号。
    private func ids(for side: CourtSide?) -> Range<Int> {
        let half = max(1, maximumPlayers / 2)
        switch side {
        case .near: return 0..<half
        case .far: return half..<max(half + 1, maximumPlayers)
        case nil: return 0..<maximumPlayers
        }
    }

    /// 空いている番号。いくつか空いていれば、覚えている見た目が候補にいちばん近い番号。
    private func freeID(for candidate: PlayerCandidate) -> Int? {
        let free = ids(for: candidate.side).filter { id in !tracks.contains { $0.id == id } }
        return free.min { difference(of: candidate, fromRemembered: $0) < difference(of: candidate, fromRemembered: $1) }
    }

    /// 候補の見た目と、その番号で覚えている見た目との違い。比べられなければ、中くらいの値。
    private func difference(of candidate: PlayerCandidate, fromRemembered id: Int) -> Double {
        guard let seen = candidate.appearance, let known = remembered[id] else { return 0.5 }
        return known.distance(to: seen) ?? 0.5
    }

    /// 同じ側の 2 人について、番号を入れ替えたほうが見た目が合う状態が続いたら、番号を入れ替える（すれ違いでの取り違えを戻す）。
    private mutating func correctSwaps(pairs: [(Int, Int)], candidates: [PlayerCandidate], time: TimeInterval) {
        var seen = Set<Int>()
        for (firstPosition, first) in pairs.enumerated() {
            for second in pairs[(firstPosition + 1)...] {
                let a = tracks[first.0]
                let b = tracks[second.0]
                guard a.side == b.side, let knownA = remembered[a.id], let knownB = remembered[b.id],
                      let seenA = candidates[first.1].appearance, let seenB = candidates[second.1].appearance,
                      let straight = sum(knownA.distance(to: seenA), knownB.distance(to: seenB)),
                      let crossed = sum(knownA.distance(to: seenB), knownB.distance(to: seenA)) else { continue }
                let key = min(a.id, b.id) * 1000 + max(a.id, b.id)
                seen.insert(key)
                guard crossed + swapMargin < straight else {
                    swapCounts[key] = 0
                    continue
                }
                swapCounts[key, default: 0] += 1
                guard swapCounts[key, default: 0] >= swapFrames else { continue }
                swapCounts[key] = 0
                // 番号（と、番号ごとに覚えている見た目）はそのままに、追っている相手（位置）を入れ替える。
                var other = tracks[second.0]
                tracks[first.0].swapIdentity(with: &other)
                tracks[second.0] = other
            }
        }
        for key in swapCounts.keys where !seen.contains(key) {
            swapCounts[key] = 0
        }
    }

    private func sum(_ first: Double?, _ second: Double?) -> Double? {
        guard let first, let second else { return nil }
        return first + second
    }

    /// 番号が空いていないとき、候補よりコートの外にいる選手（審判、観客、球拾い）から番号を取る。
    /// 出し始める前の選手からは、少しでも外にいれば取る。出している選手からは、`evictMargin` より外にいるときだけ取る。
    /// このフレームで見つかっていない選手を先に、次に、より外にいる選手を選ぶ。
    private mutating func takeID(for candidate: PlayerCandidate, time: TimeInterval) -> Int? {
        let range = ids(for: candidate.side)
        let rivals = tracks.indices.filter { index in
            let track = tracks[index]
            guard range.contains(track.id) else { return false }
            let margin = track.isConfirmed(at: time, after: confirmSeconds) ? evictMargin : 0
            return track.outside > candidate.outside + margin
        }
        guard let worst = rivals.max(by: { first, second in
            let a = tracks[first]
            let b = tracks[second]
            return (a.lastTime == time) == (b.lastTime == time) ? a.outside < b.outside : a.lastTime == time
        }) else { return nil }
        return tracks.remove(at: worst).id
    }
}

/// 追っている選手 1 人。
private struct Track: Sendable {
    var id: Int
    var pose: BodyPose
    var foot: SIMD2<Double>
    var height: Double
    var side: CourtSide?
    var courtPosition: CGPoint?
    /// コートの外へどれだけ出ているか（m）。
    var outside: Double
    /// 最後に見つけたフレームでの見た目。
    var lastAppearance: PoseAppearance?
    var startTime: TimeInterval
    var lastTime: TimeInterval

    init(id: Int, candidate: PlayerCandidate, time: TimeInterval) {
        outside = candidate.outside
        lastAppearance = candidate.appearance
        self.id = id
        pose = candidate.pose
        foot = candidate.foot
        height = candidate.height
        side = candidate.side
        courtPosition = candidate.courtPosition
        startTime = time
        lastTime = time
    }

    func isConfirmed(at time: TimeInterval, after seconds: TimeInterval) -> Bool {
        time - startTime >= seconds
    }

    /// 候補が、この選手の続きと言えるなら、ずれの大きさ（身長に対する割合）を返す。言えなければ nil。
    func cost(of candidate: PlayerCandidate, at time: TimeInterval, reach: Double, maximumSpeed: Double) -> Double? {
        // 手前の選手と奥の選手は、映像の上で重なっても、入れ替えない。ネット際では足元の位置が揺れるので、
        // はっきり反対側（ネットから長さの 1 割より向こう）にいる候補だけを外す。
        if let side, let position = candidate.courtPosition {
            if side == .near ? position.y > 0.6 : position.y < 0.4 {
                return nil
            }
        }
        let scale = max(height, 1e-6)
        let distance = simd_distance(candidate.foot, foot) / scale
        guard distance <= reach + maximumSpeed * (time - lastTime),
              candidate.height <= height * 2, candidate.height >= height / 2 else { return nil }
        return distance
    }

    /// 番号と、追い始めた時刻を、相手と入れ替える（位置や骨格は、そのまま）。
    mutating func swapIdentity(with other: inout Track) {
        swap(&id, &other.id)
        swap(&startTime, &other.startTime)
    }

    mutating func extend(with candidate: PlayerCandidate, at time: TimeInterval) {
        pose = candidate.pose
        foot = candidate.foot
        // 身長は、姿勢で変わるので、ゆっくり直す。
        height = height * 0.8 + candidate.height * 0.2
        courtPosition = candidate.courtPosition
        outside = candidate.outside
        lastAppearance = candidate.appearance
        // 側は、最初に決めたまま保つ（コートが見つからないフレームや、ネット際での揺れで変えない）。
        side = side ?? candidate.side
        lastTime = time
    }
}
