// サンプル動画を、入っている機種ごとに流し、数を書き出す。DEVICE_LAB_VIDEO（動画のパス）を指定したときだけ動く。
// Release で動かす: swift test -c release -Xswiftc -enable-testing --filter runsDemoVideoOnEachDevice
import DeviceSimulation
import Foundation
import Testing

@Test(.enabled(if: ProcessInfo.processInfo.environment["DEVICE_LAB_VIDEO"] != nil))
func runsDemoVideoOnEachDevice() async throws {
    let video = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DEVICE_LAB_VIDEO"] ?? "")
    for profile in DeviceProfile.bundled() {
        let started = Date()
        let result = try await DeviceSimulator(profile: profile).run(video: video)
        print(String(
            format: "DEVICE %@ | ball runs %.0f%% | pose %.1f/s | 4 players %.0f%% | ball shown %.0f%% | %ld frames | %.0f s on Mac",
            profile.name, result.ballRunRatio * 100, result.poseRunsPerSecond, result.fourPlayersRatio * 100, result.ballRatio * 100,
            result.frames.count, Date().timeIntervalSince(started)
        ))
    }
}
