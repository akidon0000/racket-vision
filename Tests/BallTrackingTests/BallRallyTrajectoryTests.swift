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

    /// 球が (x, y)（正規化座標）にある結果。
    private func outcome(at time: Double, x: Double, y: Double) -> BallFrameOutcome {
        BallFrameOutcome(
            method: .motionColor,
            time: time,
            ball: BallObservation(center: CGPoint(x: x, y: y), radius: 0.005, confidence: 0.8),
            durationMilliseconds: 0,
            imageSize: CGSize(width: 1920, height: 1080)
        )
    }

    @Test func startsNextRallyWhenBallIsHitBack() {
        var rally = BallRallyTrajectory()
        // 手前から奥へ 0.5 進み、打ち返されて戻る。
        let ys = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.68, 0.6, 0.5]
        for (index, y) in ys.enumerated() {
            rally.append(outcome(at: Double(index) * 0.1, x: 0.5, y: y))
        }
        // 0.7 で打ち返された。そこから先が、次のラリーの軌跡になる。
        #expect(rally.rallyIndex == 1)
        #expect(rally.samples.map(\.center.y) == [0.7, 0.68, 0.6, 0.5])
    }

    @Test func countsEachReturnAsRally() {
        var rally = BallRallyTrajectory()
        let ys = [0.2, 0.4, 0.6, 0.8, 0.6, 0.4, 0.2, 0.4, 0.6, 0.8, 0.6]
        for (index, y) in ys.enumerated() {
            rally.append(outcome(at: Double(index) * 0.1, x: 0.5, y: y))
        }
        #expect(rally.rallyIndex == 3)
        #expect(rally.samples.map(\.center.y) == [0.8, 0.6])
    }

    @Test func keepsRallyThroughSmallMoveBack() {
        var rally = BallRallyTrajectory()
        // バウンドで少し（短い辺の 5% 未満）戻るだけなら、同じラリーのまま。
        let ys = [0.2, 0.3, 0.4, 0.38, 0.37, 0.45, 0.55]
        for (index, y) in ys.enumerated() {
            rally.append(outcome(at: Double(index) * 0.1, x: 0.5, y: y))
        }
        #expect(rally.rallyIndex == 0)
        #expect(rally.samples.count == ys.count)
    }

    /// 山なりの球（重力で落ちる）。`count` 個の点を、1/30 秒おきに返す。
    private func arc(count: Int) -> [(x: Double, y: Double)] {
        (0..<count).map { index in
            let time = Double(index) / 30
            return (0.30 + 0.045 * time, 0.30 + 1.0 * time - 0.75 * time * time)
        }
    }

    @Test func keepsRallyThroughTopOfHighArc() {
        var rally = BallRallyTrajectory()
        // 上がってから落ちて、打った位置に近づくが、速さは重力でゆっくり変わるだけなので、同じラリーのまま。
        let points = arc(count: 40)
        for (index, point) in points.enumerated() {
            rally.append(outcome(at: Double(index) / 30, x: point.x, y: point.y))
        }
        #expect(rally.rallyIndex == 0)
        #expect(rally.samples.count == points.count)
    }

    @Test func startsNextRallyWhenFallingBallIsHitTowardCamera() {
        var rally = BallRallyTrajectory()
        // 山なりの球が落ちてきたところを打ち返され、手前（映像の下）へ速く飛ぶ。映像の上では向きが変わらなくても、
        // 速さが急に変わるので、打ち返しとみる。
        let points = arc(count: 32)
        for (index, point) in points.enumerated() {
            rally.append(outcome(at: Double(index) / 30, x: point.x, y: point.y))
        }
        let hit = points[31]
        for step in 1...6 {
            rally.append(outcome(at: Double(31 + step) / 30, x: hit.x, y: hit.y - 0.04 * Double(step)))
        }
        #expect(rally.rallyIndex == 1)
        #expect(abs(rally.samples[0].time - 31.0 / 30) <= 0.07)
    }

    @Test func keepsRallyThroughBounce() {
        var rally = BallRallyTrajectory()
        // 手前から奥へ飛び、バウンドして、そのまま奥へ進む。速さは急に変わるが、打った位置へ戻らないので、同じラリーのまま。
        var points = [(x: Double, y: Double)]()
        for step in 0..<12 {
            points.append((0.5, 0.20 + 0.02 * Double(step) - 0.004 * Double(step * step) / 4))
        }
        let landing = points[11]
        for step in 1...12 {
            points.append((0.5, landing.y + 0.03 * Double(step)))
        }
        for (index, point) in points.enumerated() {
            rally.append(outcome(at: Double(index) / 30, x: point.x, y: point.y))
        }
        #expect(rally.rallyIndex == 0)
    }

    @Test func measuresTurnInUnitsOfShortSide() {
        var rally = BallRallyTrajectory()
        // 横に 0.04（映像の幅に対して）戻る。短い辺（縦）に対しては 0.071 なので、打ち返しとみる。
        for (index, x) in [0.2, 0.4, 0.36].enumerated() {
            rally.append(outcome(at: Double(index) * 0.1, x: x, y: 0.5))
        }
        #expect(rally.rallyIndex == 1)
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
