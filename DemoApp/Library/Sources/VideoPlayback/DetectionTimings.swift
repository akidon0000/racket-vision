import Foundation

/// 検出 1 回にかかった時間（ミリ秒）を、検出の種類ごとにためる。実機で測って、DeviceLab の機種の条件
/// （`DeviceProfiles.json` の `latency`）に写すため。
struct DetectionTimings {
    private var court = [Double]()
    private var ball = [Double]()
    private var pose = [Double]()

    mutating func addCourt(_ milliseconds: Double) { court.append(milliseconds) }
    mutating func addBall(_ milliseconds: Double) { ball.append(milliseconds) }
    mutating func addPose(_ milliseconds: Double) { pose.append(milliseconds) }

    /// 1 行のまとめ。中央の値と、遅いほうから 1 割の値と、回数。`DeviceProfiles.json` の `latency` には、中央の値を写す。
    var summary: String {
        func line(_ name: String, _ values: [Double]) -> String {
            guard !values.isEmpty else { return "\(name) -" }
            let sorted = values.sorted()
            let median = sorted[sorted.count / 2]
            let p90 = sorted[min(sorted.count - 1, sorted.count * 9 / 10)]
            return String(format: "%@ median %.1f p90 %.1f n %ld", name, median, p90, values.count)
        }
        return "[Timing] " + [line("court", court), line("ball", ball), line("pose", pose)].joined(separator: " | ")
    }
}
