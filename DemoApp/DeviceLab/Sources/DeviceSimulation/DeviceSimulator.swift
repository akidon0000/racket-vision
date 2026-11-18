import BallTracking
import CourtFit
import CoreVideo
import Foundation
import PlayerPose

/// ある時刻に、その機種の画面に出ている結果。
public struct DeviceFrameState: Sendable {
    /// フレームの時刻（秒）。
    public var time: TimeInterval
    /// コートの四隅（正規化座標、左下が原点）。見つかっていなければ nil。
    public var court: [CGPoint]?
    /// 選手。
    public var players: [CourtPlayer]
    /// 今のラリーの、球の軌跡。
    public var ballSamples: [BallSample]
    public var rallyIndex: Int
    /// 直前の球の検出で、球が見つかったか。
    public var hasBall: Bool
}

/// 1 本の動画を、1 つの機種の条件で流した結果。
public struct DeviceRunResult: Sendable {
    public var profile: DeviceProfile
    /// フレームごとの、画面に出ている結果（時刻の順）。
    public var frames: [DeviceFrameState]
    /// 読んだ映像の大きさ（画素）とコマ数。
    public var imageSize: CGSize
    public var frameRate: Double
    /// 検出をかけた回数（コート、球、骨格）。
    public var courtRuns: Int
    public var ballRuns: Int
    public var poseRuns: Int

    /// 時刻 `time` に、画面に出ている結果。
    public func frame(at time: TimeInterval) -> DeviceFrameState? {
        var low = 0
        var high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].time <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low > 0 ? frames[low - 1] : frames.first
    }

    /// 選手が 4 人そろって出ていたフレームの割合（このフレームで見つけた選手だけを数える）。
    public var fourPlayersRatio: Double {
        ratio { $0.players.filter(\.isDetected).count >= 4 }
    }

    /// 球を出していたフレームの割合。
    public var ballRatio: Double {
        ratio(\.hasBall)
    }

    /// 骨格の検出を、フレームのうちどれだけにかけられたか（1 秒に何回かけたか）。
    public var poseRunsPerSecond: Double {
        guard let last = frames.last?.time, last > 0 else { return 0 }
        return Double(poseRuns) / last
    }

    /// 球の検出を、フレームのうちどれだけにかけられたか。
    public var ballRunRatio: Double {
        frames.isEmpty ? 0 : Double(ballRuns) / Double(frames.count)
    }

    private func ratio(_ predicate: (DeviceFrameState) -> Bool) -> Double {
        frames.isEmpty ? 0 : Double(frames.filter(predicate).count) / Double(frames.count)
    }
}

/// 検出器。実際の検出（`LibraryDetectors`）と、テスト用の偽の検出を、同じ形で渡す。
public protocol DeviceDetectors: AnyObject {
    /// コートの四隅。見つからなければ nil。
    func court(in pixelBuffer: CVPixelBuffer) -> [CGPoint]?
    /// 球の検出（1 フレーム）。
    func ball(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> BallFrameOutcome
    /// 選手の検出（1 フレーム）。
    func players(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> [CourtPlayer]
    /// コートの結果が画面に出たときに呼ぶ（球と選手の検出の範囲を、そのコートで決める。デモのアプリと同じ）。
    func setCourt(_ corners: [CGPoint]?)
}

/// 本物の検出器（`CourtFit`、`BallTracking`、`PlayerPose`）。デモのアプリと同じ設定。
public final class LibraryDetectors: DeviceDetectors {
    private let analyzer = CourtAnalyzer(
        detectors: [TrackingLineModelCourtRectangleDetector(searchInterval: 0)],
        switches: CourtMethodSwitches(enabled: [.lineModelTracking])
    )
    private let ballDetector = MotionColorBallDetector()
    private let playerDetector = CourtPlayerDetector()

    public init() {}

    public func court(in pixelBuffer: CVPixelBuffer) -> [CGPoint]? {
        analyzer.analyze(pixelBuffer, orientation: .up).first?.quads.first?.corners
    }

    public func ball(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> BallFrameOutcome {
        ballDetector.detect(in: pixelBuffer, at: time)
    }

    public func players(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> [CourtPlayer] {
        playerDetector.detect(in: pixelBuffer, at: time).players
    }

    public func setCourt(_ corners: [CGPoint]?) {
        ballDetector.setCourtRegion(corners)
        playerDetector.setCourt(corners)
    }
}

/// 機種の条件で、デモのアプリと同じ処理を、仮の時計で流す。
///
/// 検出は Mac で本当に動かす。ただし、終わる時刻は、Mac でかかった時間ではなく、機種の時間で決める。
/// 検出のあいだに来たフレームは、その検出には使わない（実機と同じく、飛ばす）。
public struct DeviceSimulator {
    public var profile: DeviceProfile
    /// コートと骨格の検出をかける間隔（秒）。デモのアプリと同じ。
    public var courtInterval: TimeInterval = 0.2
    public var poseInterval: TimeInterval = 0.1

    public init(profile: DeviceProfile) {
        self.profile = profile
    }

    /// 動画を流す。`progress` には、読んだ割合（0〜1）を渡す。
    public func run(
        video: URL, detectors: DeviceDetectors = LibraryDetectors(), progress: (Double) -> Void = { _ in }
    ) async throws -> DeviceRunResult {
        let source = try await DeviceFrameSource(
            url: video, maximumWidth: profile.maximumWidth, maximumHeight: profile.maximumHeight,
            maximumFrameRate: profile.maximumFrameRate
        )
        var session = Session(simulator: self, detectors: detectors)
        while let frame = source.next() {
            session.step(pixelBuffer: frame.pixelBuffer, time: frame.seconds)
            if source.duration > 0 {
                progress(min(1, frame.seconds / source.duration))
            }
        }
        return session.result(imageSize: source.size, frameRate: source.frameRate)
    }

    /// 仮の時計で流す途中の状態。テストでは、フレームを 1 枚ずつ渡す。
    public struct Session {
        let simulator: DeviceSimulator
        let detectors: DeviceDetectors
        private var latency: LatencyModel
        private var courtLane: DetectionLane
        private var ballLane = DetectionLane(interval: 0)
        private var poseLane: DetectionLane
        /// かけたが、まだ画面に出ていない結果。
        private var pendingCourt: [CGPoint]??
        private var pendingBall: BallFrameOutcome?
        private var pendingPlayers: [CourtPlayer]?
        private var state = DeviceFrameState(time: 0, court: nil, players: [], ballSamples: [], rallyIndex: 0, hasBall: false)
        private var rally = BallRallyTrajectory()
        private(set) var frames = [DeviceFrameState]()

        public init(simulator: DeviceSimulator, detectors: DeviceDetectors) {
            self.simulator = simulator
            self.detectors = detectors
            latency = LatencyModel(profile: simulator.profile)
            courtLane = DetectionLane(interval: simulator.courtInterval)
            poseLane = DetectionLane(interval: simulator.poseInterval)
        }

        /// 1 フレームぶん進める。終わった検出の結果を画面に出し、空いている検出をかける。
        public mutating func step(pixelBuffer: CVPixelBuffer, time: TimeInterval) {
            applyFinished(at: time)
            let base = simulator.profile.latency
            if courtLane.canStart(at: time) {
                courtLane.start(at: time, latency: latency.seconds(base: base.court, at: time))
                pendingCourt = .some(detectors.court(in: pixelBuffer))
            }
            if ballLane.canStart(at: time) {
                ballLane.start(at: time, latency: latency.seconds(base: base.ball, at: time))
                pendingBall = detectors.ball(in: pixelBuffer, at: time)
            }
            if poseLane.canStart(at: time) {
                poseLane.start(at: time, latency: latency.seconds(base: base.pose, at: time))
                pendingPlayers = detectors.players(in: pixelBuffer, at: time)
            }
            state.time = time
            frames.append(state)
        }

        private mutating func applyFinished(at time: TimeInterval) {
            if courtLane.finish(at: time) != nil, let court = pendingCourt {
                state.court = court
                detectors.setCourt(court)
                pendingCourt = nil
            }
            if ballLane.finish(at: time) != nil, let outcome = pendingBall {
                rally.append(outcome)
                state.ballSamples = rally.samples
                state.rallyIndex = rally.rallyIndex
                state.hasBall = outcome.ball != nil
                pendingBall = nil
            }
            if poseLane.finish(at: time) != nil, let players = pendingPlayers {
                state.players = players
                pendingPlayers = nil
            }
        }

        public func result(imageSize: CGSize, frameRate: Double) -> DeviceRunResult {
            DeviceRunResult(
                profile: simulator.profile, frames: frames, imageSize: imageSize, frameRate: frameRate,
                courtRuns: courtLane.starts, ballRuns: ballLane.starts, poseRuns: poseLane.starts
            )
        }
    }
}
