import Foundation

/// 1 種類の検出（コート、球、骨格）を、仮の時計でかける決まり。デモのアプリ（`PlayerModel`）と同じ決まりにする。
///
/// - 前の検出が終わるまで、次はかけない（そのあいだのフレームは、この検出には使わない）。
/// - 前にかけてから `interval` 秒たつまで、次はかけない（0 なら、毎フレーム）。
/// - 検出の結果は、かけたフレームの時刻に、かかった時間を足した時刻のあと、最初のフレームで画面に出す。
public struct DetectionLane: Sendable {
    /// 検出をかける間隔（秒）。
    public let interval: TimeInterval
    /// 今の検出が終わる時刻。検出していなければ nil。
    public private(set) var busyUntil: TimeInterval?
    /// 最後に検出をかけた時刻。
    public private(set) var lastStart: TimeInterval?
    /// 検出をかけた回数。
    public private(set) var starts = 0

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// `time` のフレームで、検出が終わっていれば、終わった時刻を返して、空ける。
    public mutating func finish(at time: TimeInterval) -> TimeInterval? {
        guard let busyUntil, busyUntil <= time else { return nil }
        self.busyUntil = nil
        return busyUntil
    }

    /// `time` のフレームで、検出をかけられるか。
    public func canStart(at time: TimeInterval) -> Bool {
        guard busyUntil == nil else { return false }
        guard let lastStart else { return true }
        return time - lastStart >= interval - 1e-9
    }

    /// `time` のフレームで検出をかけ、`latency` 秒で終わるとする。
    public mutating func start(at time: TimeInterval, latency: TimeInterval) {
        lastStart = time
        busyUntil = time + max(0, latency)
        starts += 1
    }
}

/// 機種の条件から、検出 1 回の時間（秒）を決める。ばらつきは、決まった種から作る（同じ条件なら、同じ結果になる）。
public struct LatencyModel: Sendable {
    public let profile: DeviceProfile
    private var state: UInt64

    public init(profile: DeviceProfile, seed: UInt64 = 1) {
        self.profile = profile
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    /// `base` ミリ秒の検出が、動画の `time` 秒の時点で、何秒かかるか。
    public mutating func seconds(base: Double, at time: TimeInterval) -> TimeInterval {
        let thermal = min(1.5, 1 + profile.thermalSlowdownPerMinute * time / 60)
        let jitter = 1 + profile.jitter * (2 * random() - 1)
        return base * thermal * jitter / 1000
    }

    /// 0〜1 の疑似乱数（xorshift）。
    private mutating func random() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}
