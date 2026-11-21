import BallTracking
import CoreGraphics
import CoreVideo
@testable import DeviceSimulation
import PlayerPose
import Testing

/// 呼ばれたフレームの時刻を覚える、偽の検出器。結果は、呼ばれた時刻を入れて返す（いつの結果が画面に出たかを見るため）。
private final class FakeDetectors: DeviceDetectors {
    var courtCalls = [Double]()
    var ballCalls = [Double]()
    var poseCalls = [Double]()
    var currentTime = 0.0
    var courtsSet = 0

    func court(in pixelBuffer: CVPixelBuffer) -> [CGPoint]? {
        courtCalls.append(currentTime)
        return [CGPoint(x: currentTime, y: 0), .zero, .zero, .zero]
    }

    func ball(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> BallFrameOutcome {
        ballCalls.append(time)
        return BallFrameOutcome(
            method: .motionColor, time: time,
            ball: BallObservation(center: CGPoint(x: 0.5, y: 0.5), radius: 0.004, confidence: 1),
            durationMilliseconds: 0, imageSize: CGSize(width: 8, height: 8)
        )
    }

    func players(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> [CourtPlayer] {
        poseCalls.append(time)
        return [CourtPlayer(id: 0, pose: BodyPose(joints: [:]), side: nil, courtPosition: nil, firstSeen: time)]
    }

    func setCourt(_ corners: [CGPoint]?) {
        courtsSet += 1
    }
}

private func profile(court: Double = 30, ball: Double = 4, pose: Double = 50, jitter: Double = 0, os: String = "27.3") -> DeviceProfile {
    DeviceProfile(
        id: "test", name: "テスト", os: os, latency: .init(court: court, ball: ball, pose: pose), jitter: jitter,
        maximumWidth: 1920, maximumHeight: 1080, maximumFrameRate: 30, thermalSlowdownPerMinute: 0, source: .estimated, note: ""
    )
}

private func pixelBuffer() throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &buffer)
    return try #require(buffer)
}

/// 30 コマ/秒で `count` 枚流す。
private func run(_ profile: DeviceProfile, frames count: Int) throws -> (DeviceRunResult, FakeDetectors) {
    let detectors = FakeDetectors()
    var session = DeviceSimulator.Session(simulator: DeviceSimulator(profile: profile), detectors: detectors)
    let buffer = try pixelBuffer()
    for index in 0..<count {
        let time = Double(index) / 30
        detectors.currentTime = time
        session.step(pixelBuffer: buffer, time: time)
    }
    return (session.result(imageSize: CGSize(width: 8, height: 8), frameRate: 30), detectors)
}

struct DetectionLaneTests {
    @Test func waitsForIntervalAndForPreviousDetection() {
        var lane = DetectionLane(interval: 0.1)
        #expect(lane.canStart(at: 0))
        lane.start(at: 0, latency: 0.25)
        // 間隔はたったが、前の検出が終わっていない。
        #expect(lane.finish(at: 0.2) == nil)
        #expect(!lane.canStart(at: 0.2))
        #expect(lane.finish(at: 0.26) == 0.25)
        #expect(lane.canStart(at: 0.26))
    }

    @Test func runsEveryFrameWhenIntervalIsZeroAndDetectionIsFast() throws {
        let (result, detectors) = try run(profile(ball: 4), frames: 30)
        #expect(detectors.ballCalls.count == 30)
        #expect(result.ballRuns == 30)
    }
}

struct DeviceSimulatorTests {
    @Test func fastDeviceRunsPoseEveryTenthOfSecond() throws {
        let (_, detectors) = try run(profile(pose: 50), frames: 60)
        // 0.1 秒ごと（3 コマごと）にかける。
        #expect(detectors.poseCalls.count == 20)
    }

    @Test func slowDeviceSkipsFramesForPose() throws {
        let (result, detectors) = try run(profile(pose: 250), frames: 60)
        // 0.25 秒かかるので、次は 0.267 秒（8 コマ目）。2 秒で 8 回。
        #expect(detectors.poseCalls.count == 8)
        #expect(abs(detectors.poseCalls[1] - 8.0 / 30) < 1e-9)
        #expect(result.poseRunsPerSecond < 5)
    }

    @Test func showsResultOnlyAfterLatency() throws {
        let (result, _) = try run(profile(pose: 250), frames: 60)
        // 0 秒にかけた骨格の検出は、0.25 秒のあと、最初のフレーム（0.267 秒）で画面に出る。
        let shown = try #require(result.frames.first { !$0.players.isEmpty })
        #expect(abs(shown.time - 8.0 / 30) < 1e-9)
        #expect(shown.players.first?.firstSeen == 0)
    }

    @Test func slowBallDetectionMissesFrames() throws {
        let (fast, _) = try run(profile(ball: 4), frames: 60)
        let (slow, _) = try run(profile(ball: 50), frames: 60)
        #expect(fast.ballRunRatio == 1)
        // 0.05 秒かかるので、1 コマおき（33 ms ごとのフレームの半分）にしかかけられない。
        #expect(abs(slow.ballRunRatio - 0.5) < 1e-9)
    }

    @Test func courtResultIsPassedToOtherDetectors() throws {
        let (result, detectors) = try run(profile(court: 30), frames: 30)
        #expect(detectors.courtsSet > 0)
        #expect(result.frames.last?.court != nil)
    }

    @Test func latencyIsDeterministicAndWithinJitter() {
        var first = LatencyModel(profile: profile(jitter: 0.4))
        var second = LatencyModel(profile: profile(jitter: 0.4))
        let a = (0..<50).map { _ in first.seconds(base: 100, at: 0) }
        let b = (0..<50).map { _ in second.seconds(base: 100, at: 0) }
        #expect(a == b)
        #expect(a.allSatisfy { (0.06...0.14).contains($0) })
        #expect(Set(a.map { Int($0 * 1000) }).count > 5)
    }
}

struct DeviceProfileTests {
    @Test func bundledProfilesLoadAndIncludeMeasuredDevice() {
        let profiles = DeviceProfile.bundled()
        #expect(profiles.count >= 4)
        #expect(Set(profiles.map(\.id)).count == profiles.count)
        #expect(profiles.contains { $0.source == .measured })
    }

    @Test func comparesOSVersions() {
        let device = profile(os: "18.2")
        #expect(device.supports(osAtLeast: [18]))
        #expect(device.supports(osAtLeast: [18, 2]))
        #expect(!device.supports(osAtLeast: [18, 3]))
        #expect(!device.supports(osAtLeast: [26]))
    }
}
