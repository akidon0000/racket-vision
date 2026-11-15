@testable import BallTracking
import CoreGraphics
import Testing

struct BallRallyTrajectoryTests {
    private func outcome(at time: Double, ball: Bool = true, sceneChanged: Bool = false) -> BallFrameOutcome {
        BallFrameOutcome(
            method: .motionColor,
            time: time,
            ball: ball ? BallObservation(center: CGPoint(x: time / 10, y: 0.5), radius: 0.005, confidence: 0.8) : nil,
            sceneChanged: sceneChanged,
            durationMilliseconds: 0,
            imageSize: CGSize(width: 1920, height: 1080)
        )
    }

    @Test func keepsBallsOfCurrentRallyAsSamples() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 0.1, ball: false))
        rally.append(outcome(at: 0.2))
        #expect(rally.samples.map(\.time) == [0, 0.2])
        #expect(rally.samples[1].center == outcome(at: 0.2).ball?.center)
        #expect(rally.rallyIndex == 0)
    }

    @Test func keepsRallyThroughShortGap() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 1.9))
        #expect(rally.samples.count == 2)
        #expect(rally.rallyIndex == 0)
    }

    @Test func endsRallyWhenBallIsGoneForRallyGap() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 0.1))
        // 球が無いまま 2 秒を超えると、点が消えて、次のラリーの番号になる。
        rally.append(outcome(at: 2.2, ball: false))
        #expect(rally.samples.isEmpty)
        #expect(rally.rallyIndex == 1)
        rally.append(outcome(at: 2.3))
        #expect(rally.samples.map(\.time) == [2.3])
        #expect(rally.rallyIndex == 1)
    }

    @Test func startsNextRallyWithBallAfterGap() {
        var rally = BallRallyTrajectory(rallyGap: 1)
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 1.5))
        #expect(rally.samples.map(\.time) == [1.5])
        #expect(rally.rallyIndex == 1)
    }

    @Test func endsRallyOnSceneChange() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 0.1, ball: false, sceneChanged: true))
        #expect(rally.samples.isEmpty)
        #expect(rally.rallyIndex == 1)
    }

    @Test func doesNotCountRalliesWithoutBalls() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0, ball: false, sceneChanged: true))
        rally.append(outcome(at: 5, ball: false))
        rally.append(outcome(at: 10, ball: false, sceneChanged: true))
        #expect(rally.rallyIndex == 0)
    }

    @Test func endsRallyWhenTimeGoesBack() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 5))
        rally.append(outcome(at: 1))
        #expect(rally.samples.map(\.time) == [1])
        #expect(rally.rallyIndex == 1)
    }

    @Test func resetClearsSamplesAndIndex() {
        var rally = BallRallyTrajectory()
        rally.append(outcome(at: 0))
        rally.append(outcome(at: 3))
        rally.reset()
        #expect(rally.samples.isEmpty)
        #expect(rally.rallyIndex == 0)
    }

    @Test func paletteChangesColorForEachRallyAndCycles() {
        let count = BallRallyPalette.colors.count
        #expect(count >= 2)
        #expect(BallRallyPalette.color(forRally: 0) != BallRallyPalette.color(forRally: 1))
        #expect(BallRallyPalette.color(forRally: count) == BallRallyPalette.color(forRally: 0))
        #expect(BallRallyPalette.color(forRally: -1) == BallRallyPalette.color(forRally: count - 1))
    }
}
