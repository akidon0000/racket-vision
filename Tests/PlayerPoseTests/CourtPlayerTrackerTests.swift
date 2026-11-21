import CoreGraphics
import CourtFit
import PlayerPose
import Testing

struct CourtPlayerTrackerTests {
    private let imageSize = CGSize(width: 1000, height: 1000)
    private let frame = 0.1

    /// `positions` の足元に立つ人を、`frames` のフレームぶん渡す。最後のフレームの結果を返す。
    private func run(
        _ tracker: inout CourtPlayerTracker, positions: [CGPoint], frames: Range<Int>, court: CourtPlane? = wholeImageCourt
    ) -> [CourtPlayer] {
        var players = [CourtPlayer]()
        for index in frames {
            players = tracker.update(
                poses: positions.map { standingPose(foot: $0) }, court: court, time: Double(index) * frame, imageSize: imageSize
            )
        }
        return players
    }

    private let four = [CGPoint(x: 0.3, y: 0.2), CGPoint(x: 0.7, y: 0.2), CGPoint(x: 0.3, y: 0.8), CGPoint(x: 0.7, y: 0.8)]

    @Test func numbersNearPlayersFirstThenFarPlayers() {
        var tracker = CourtPlayerTracker()
        let players = run(&tracker, positions: four, frames: 0..<5)
        #expect(players.map(\.id) == [0, 1, 2, 3])
        #expect(players.map(\.side) == [.near, .near, .far, .far])
        #expect(players.allSatisfy { $0.isDetected && $0.firstSeen == 0 })
        #expect(abs((players[2].courtPosition?.y ?? 0) - 0.8) < 1e-6)
    }

    @Test func doesNotShowPlayerSeenOnlyBriefly() {
        var tracker = CourtPlayerTracker()
        // 0.2 秒たつまでは、出さない。
        #expect(run(&tracker, positions: four, frames: 0..<2).isEmpty)
        #expect(run(&tracker, positions: four, frames: 2..<3).count == 4)
    }

    @Test func ignoresPeopleFarOutsideCourt() {
        var tracker = CourtPlayerTracker()
        // サイドラインの外 3.7 m（観客）と、ベースラインの後ろ 5.4 m。
        let players = run(&tracker, positions: four + [CGPoint(x: 1.6, y: 0.5), CGPoint(x: 0.5, y: 1.4)], frames: 0..<5)
        #expect(players.count == 4)
    }

    @Test func keepsIDsWhileIndexOrderChangesAndPlayersMove() {
        var tracker = CourtPlayerTracker()
        _ = run(&tracker, positions: four, frames: 0..<5)
        var players = [CourtPlayer]()
        for index in 5..<25 {
            // 手前の右の選手が、左へ歩く。骨格の並びは、毎フレーム逆にする。
            let x = 0.7 - 0.01 * Double(index - 4)
            let positions = [four[0], CGPoint(x: x, y: 0.2), four[2], four[3]]
            players = tracker.update(
                poses: positions.reversed().map { standingPose(foot: $0) }, court: wholeImageCourt, time: Double(index) * frame,
                imageSize: imageSize
            )
        }
        #expect(players.map(\.id) == [0, 1, 2, 3])
        #expect(abs((players[1].courtPosition?.x ?? 0) - 0.5) < 1e-6)
        #expect(players.allSatisfy { $0.firstSeen == 0 })
    }

    @Test func holdsMissingPlayerBrieflyAndKeepsIDWhenFoundAgain() {
        var tracker = CourtPlayerTracker()
        _ = run(&tracker, positions: four, frames: 0..<5)
        let three = Array(four.dropLast())
        // 見つからなくなって 0.3 秒。少し前の骨格を、そのまま出す。
        var players = run(&tracker, positions: three, frames: 5..<8)
        #expect(players.map(\.id) == [0, 1, 2, 3])
        #expect(players.map(\.isDetected) == [true, true, true, false])
        // 0.6 秒たったら、出さない。
        players = run(&tracker, positions: three, frames: 8..<11)
        #expect(players.map(\.id) == [0, 1, 2])
        // 1 秒たつ前に戻ってきたら、同じ番号で、追い始めた時刻もそのまま。
        players = run(&tracker, positions: four, frames: 11..<12)
        #expect(players.map(\.id) == [0, 1, 2, 3])
        #expect(players[3].firstSeen == 0 && players[3].isDetected)
    }

    @Test func playerOnCourtTakesIDFromPersonOutsideCourt() {
        var tracker = CourtPlayerTracker()
        // 手前に、選手 1 人と、サイドラインの外 1.8 m に立つ審判。
        let referee = CGPoint(x: 1.3, y: 0.3)
        _ = run(&tracker, positions: [four[0], referee], frames: 0..<5)
        // もう 1 人の選手がコートに入ってきたら、審判の番号を取る。
        let players = run(&tracker, positions: [four[0], referee, four[1]], frames: 5..<10)
        #expect(players.count == 2)
        #expect(players.allSatisfy { ($0.courtPosition?.x ?? 2) < 1 })
    }

    @Test func picksLargestPeopleWithoutCourt() {
        var tracker = CourtPlayerTracker()
        var players = [CourtPlayer]()
        for index in 0..<5 {
            let poses = (0..<6).map { standingPose(foot: CGPoint(x: 0.1 + 0.15 * Double($0), y: 0.2), height: 0.1 + 0.05 * Double($0)) }
            players = tracker.update(poses: poses, court: nil, time: Double(index) * frame, imageSize: imageSize)
        }
        #expect(players.count == 4)
        #expect(players.allSatisfy { $0.side == nil && $0.courtPosition == nil })
        // 小さく写った 2 人（左の 2 人）は選ばない。
        #expect(players.allSatisfy { ($0.pose.footPoint?.x ?? 0) > 0.39 })
    }

    @Test func correctsSwappedIDsByAppearance() {
        var tracker = CourtPlayerTracker()
        let red = PoseAppearance(torso: SIMD3(0.9, 0.1, 0.1), legs: nil)
        let blue = PoseAppearance(torso: SIMD3(0.1, 0.1, 0.9), legs: nil)
        /// 赤い服の選手が `redX`、青い服の選手が `blueX` にいるフレームを渡す。
        func step(_ index: Int, redX: Double, blueX: Double) -> [CourtPlayer] {
            let poses = [standingPose(foot: CGPoint(x: redX, y: 0.2)), standingPose(foot: CGPoint(x: blueX, y: 0.2))]
            return tracker.update(poses: poses, court: wholeImageCourt, time: Double(index) * frame, imageSize: imageSize) {
                ($0.footPoint?.x ?? 0) == CGFloat(redX) ? red : blue
            }
        }
        var players = [CourtPlayer]()
        for index in 0..<30 {
            players = step(index, redX: 0.3, blueX: 0.7)
        }
        let redID = players.first { $0.appearance == red }?.id
        // 2 人が近づいて、1 フレームで位置が入れ替わる（すれ違い）。足元の近さだけなら、番号が入れ替わる。
        for index in 30..<40 {
            players = step(index, redX: 0.52 - 0.002 * Double(index - 30), blueX: 0.48 + 0.002 * Double(index - 30))
        }
        for index in 40..<60 {
            players = step(index, redX: 0.48, blueX: 0.52)
        }
        #expect(players.count == 2)
        #expect(players.first { $0.appearance == red }?.id == redID)
    }
}
