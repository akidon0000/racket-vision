import Foundation

/// iPhone の機種ごとの条件。`DeviceProfiles.json` から読む。
public struct DeviceProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// 検出 1 回にかかる時間（ミリ秒）。
    public struct Latency: Codable, Equatable, Hashable, Sendable {
        /// コートの検出。
        public var court: Double
        /// 球の検出。
        public var ball: Double
        /// 選手の骨格の検出。
        public var pose: Double

        public init(court: Double, ball: Double, pose: Double) {
            self.court = court
            self.ball = ball
            self.pose = pose
        }
    }

    /// 値の出どころ。
    public enum Source: String, Codable, Sendable {
        /// 実機で測った。
        case measured
        /// 公開されている性能の比などから見込んだ。
        case estimated
    }

    /// 機種の番号（iPhone18,1 など）。一覧の中で重ならない。
    public var id: String
    /// 画面に出す名前。
    public var name: String
    /// OS の版（"27.3" など）。
    public var os: String
    /// 検出 1 回の時間（ミリ秒）。
    public var latency: Latency
    /// 時間のばらつき（割合）。0.3 なら、0.7〜1.3 倍のあいだで揺れる。
    public var jitter: Double
    /// 映像の上限（横の画素、縦の画素、コマ/秒）。これを超える動画は、縮めて、コマを間引いてから流す。
    public var maximumWidth: Int
    public var maximumHeight: Int
    public var maximumFrameRate: Double
    /// 熱で遅くなる割合。1 分あたり、検出の時間がこれだけ延びる（0.02 なら 1 分で 1.02 倍）。上限は 1.5 倍。
    public var thermalSlowdownPerMinute: Double
    public var source: Source
    /// 値について書いておくこと（どう測ったか、何から見込んだか）。
    public var note: String

    public init(
        id: String, name: String, os: String, latency: Latency, jitter: Double, maximumWidth: Int, maximumHeight: Int,
        maximumFrameRate: Double, thermalSlowdownPerMinute: Double, source: Source, note: String
    ) {
        self.id = id
        self.name = name
        self.os = os
        self.latency = latency
        self.jitter = jitter
        self.maximumWidth = maximumWidth
        self.maximumHeight = maximumHeight
        self.maximumFrameRate = maximumFrameRate
        self.thermalSlowdownPerMinute = thermalSlowdownPerMinute
        self.source = source
        self.note = note
    }

    /// OS の版を数の並びにする（"17.4" → [17, 4]）。
    public var osVersion: [Int] {
        os.split(separator: ".").compactMap { Int($0) }
    }

    /// 機能が使えるか。`minimum` は、その機能が入った OS の版。
    public func supports(osAtLeast minimum: [Int]) -> Bool {
        for (index, part) in minimum.enumerated() {
            let mine = index < osVersion.count ? osVersion[index] : 0
            if mine != part {
                return mine > part
            }
        }
        return true
    }

    /// アプリに入っている機種の一覧。
    public static func bundled() -> [DeviceProfile] {
        guard let url = Bundle.module.url(forResource: "DeviceProfiles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([DeviceProfile].self, from: data) else { return [] }
        return profiles
    }
}
