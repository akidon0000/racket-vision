import AVFoundation
import BallTracking
import BallTrackOverlay
import CoreVideo
import CourtFit
import QuartzCore
import CourtLineOverlay
import CourtSceneView
import PlayerPose
import PlayerPoseOverlay
import SwiftUI
import UIKit

/// 動画を流し、映像の上に検出したコートの線を赤で重ね、検出の結果（コート、選手の骨格、球の軌跡、映像のカメラ）を白い背景の 3D で描く。縦画面では上に動画、下に 3D、
/// 横画面では左に動画、右に 3D を並べる。
/// 3D は、ドラッグで視点をコートの中心のまわりに回せる。最初の視点は映像のカメラの位置なので、動画と見比べられる。
public struct PlayerView: View {
    @StateObject private var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    /// 縦の幅が狭い（iPhone の横画面）か。
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public init(url: URL) {
        _model = StateObject(wrappedValue: PlayerModel(url: url))
    }

    /// 動画と 3D の並べ方。横画面なら左右、縦画面なら上下。
    private var layout: AnyLayout {
        verticalSizeClass == .compact ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }

    public var body: some View {
        layout {
            ZStack {
                Color.black
                PlayerLayerView(player: model.player)
                // 検出したコートの線を、映像の上に赤で重ねる（映像は縦横比を保って枠に収めている）。
                GeometryReader { proxy in
                    CourtLinesOverlay(
                        corners: model.quads.first?.corners, rect: fitRect(container: proxy.size, video: model.videoSize),
                        color: .red, lineWidth: 3
                    )
                }
            }
            .overlay(alignment: .topLeading) { closeButton }
            Divider()
            CourtSceneView(
                corners: model.quads.first?.corners, imageSize: model.videoSize, players: model.players,
                ballSamples: model.ballSamples, rallyIndex: model.rallyIndex
            )
            .overlay(alignment: .bottom) {
                Text(statusText)
                    .font(.caption2.monospaced())
                    .padding(6)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.black)
                    .padding(.bottom, 8)
            }
        }
        .background {
            layout {
                Color.black
                Color.white
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
        .onDisappear { model.stop() }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.6), in: Circle())
        }
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    private var playerText: String {
        if model.usesRecordedPlayers {
            return "選手 \(model.players.count) 人（記録）"
        }
        return model.playerFailure == nil ? "選手 \(model.players.count) 人" : "選手 検出不可"
    }

    private var statusText: String {
        let found = model.quads.isEmpty ? "コートなし" : "コートあり"
        let ball = "球 \(model.ballSamples.count) 点（ラリー \(model.rallyIndex + 1)）  \(playerText)"
        guard let milliseconds = model.milliseconds else { return "\(found)  \(ball)" }
        return String(format: "%@  %.1f ms  %@", found, milliseconds, ball)
    }
}

/// AVPlayer の映像を表示する層。
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // layerClass で AVPlayerLayer を指定しているので、必ず AVPlayerLayer になる。
        layer as? AVPlayerLayer ?? AVPlayerLayer()
    }
}

/// 検出の結果を持つ、動画の再生の状態。画面の更新のたびに新しいフレームを取り、球の追跡にかける。
/// コートの検出には 0.2 秒ごと、選手の骨格の検出には 0.1 秒ごとにかける。どれも、前の検出が終わるまで次はかけない
/// （間に合わないフレームは飛ばす）。
@MainActor
final class PlayerModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var quads: [DetectedQuad] = []
    @Published private(set) var milliseconds: Double?
    @Published private(set) var videoSize: CGSize = .zero
    /// 今のラリーの、球の軌跡。
    @Published private(set) var ballSamples: [BallSample] = []
    @Published private(set) var rallyIndex = 0
    /// コートにいる選手（番号の順）。
    @Published private(set) var players: [CourtPlayer] = []
    /// 骨格の検出が動かなかったときの理由。動いていれば nil。
    @Published private(set) var playerFailure: String?
    /// その場の検出の代わりに、前もって求めた記録（`RecordedPlayers`）を出しているか。
    @Published private(set) var usesRecordedPlayers = false

    private let item: AVPlayerItem
    private let output: AVPlayerItemVideoOutput
    private let analyzer = CourtAnalyzer(
        detectors: [TrackingLineModelCourtRectangleDetector(searchInterval: 0)],
        switches: CourtMethodSwitches(enabled: [.lineModelTracking])
    )
    private let ballDetector = MotionColorBallDetector()
    private let playerDetector = CourtPlayerDetector()
    /// 前もって求めた選手の検出の記録。その場の検出が動かないとき（シミュレーター）に使う。
    private let recordedPlayers: RecordedPlayers?
    private var rally = BallRallyTrajectory()
    private var displayLink: CADisplayLink?
    private var isAnalyzing = false
    /// 検出 1 回の時間。10 秒ごとに、ログへ出す。
    private var timings = DetectionTimings()
    private var lastTimingLog: CFTimeInterval = 0
    private var isTrackingBall = false
    private var isTrackingPlayers = false
    private var lastCourtSample: CFTimeInterval = 0
    private var lastPlayerSample: CFTimeInterval = 0

    init(url: URL) {
        item = AVPlayerItem(url: url)
        recordedPlayers = RecordedPlayers(video: url)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
    }

    func load() async {
        guard let track = try? await item.asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return }
        let size = natural.applying(transform)
        videoSize = CGSize(width: abs(size.width), height: abs(size.height))
        player.play()
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in self?.sample() }, selector: #selector(DisplayLinkTarget.fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        player.pause()
    }

    private func sample() {
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let box = PixelBufferBox(buffer: buffer)
        trackBall(in: box, seconds: time.seconds)
        if usesRecordedPlayers, let recordedPlayers {
            players = recordedPlayers.players(at: time.seconds)
        } else {
            trackPlayers(in: box, seconds: time.seconds)
        }
        analyzeCourt(in: box)
    }

    private func trackPlayers(in box: PixelBufferBox, seconds: Double) {
        let now = CACurrentMediaTime()
        guard !isTrackingPlayers, now - lastPlayerSample >= 0.1 else { return }
        lastPlayerSample = now
        isTrackingPlayers = true
        let detector = playerDetector
        Task.detached(priority: .userInitiated) {
            let outcome = detector.detect(in: box.buffer, at: seconds)
            await MainActor.run { [weak self] in self?.show(outcome) }
        }
    }

    private func trackBall(in box: PixelBufferBox, seconds: Double) {
        guard !isTrackingBall else { return }
        isTrackingBall = true
        let detector = ballDetector
        // 検出は画面の外で動かす（画面を止めないため）。結果だけ画面に出す。
        Task.detached(priority: .userInitiated) {
            let outcome = detector.detect(in: box.buffer, at: seconds)
            await MainActor.run { [weak self] in self?.show(outcome) }
        }
    }

    private func analyzeCourt(in box: PixelBufferBox) {
        let now = CACurrentMediaTime()
        guard !isAnalyzing, now - lastCourtSample >= 0.2 else { return }
        lastCourtSample = now
        isAnalyzing = true
        let analyzer = analyzer
        Task.detached(priority: .userInitiated) {
            let outcome = analyzer.analyze(box.buffer, orientation: .up).first
            await MainActor.run { [weak self] in self?.show(outcome) }
        }
    }

    private func show(_ outcome: DetectionOutcome?) {
        isAnalyzing = false
        if let outcome {
            timings.addCourt(outcome.durationMilliseconds)
        }
        logTimings()
        quads = outcome?.quads ?? []
        milliseconds = outcome?.durationMilliseconds
        // 球は、見つかったコートの矩形の中（少し外まで）だけで探す。矩形が無いときは、範囲で絞らない。
        ballDetector.setCourtRegion(quads.first?.corners)
        // 選手は、コートの中かその近くに立つ人だけを選ぶ。矩形が無いときは、大きく写った人から選ぶ。
        playerDetector.setCourt(quads.first?.corners)
    }

    private func show(_ outcome: CourtPlayersOutcome) {
        isTrackingPlayers = false
        if outcome.failure == nil {
            timings.addPose(outcome.durationMilliseconds)
        }
        players = outcome.players
        playerFailure = outcome.failure
        // その場の検出が動かない（シミュレーター）ときは、記録があれば、そちらに切り替える。
        if outcome.failure != nil, recordedPlayers != nil {
            usesRecordedPlayers = true
        }
        logPlayers(outcome)
    }

    private var lastPlayerLog: CFTimeInterval = 0

    /// 10 秒ごとに、検出 1 回の時間のまとめ（再生を始めてからの全部）をログに出す。
    private func logTimings() {
        let now = CACurrentMediaTime()
        guard now - lastTimingLog >= 10 else { return }
        lastTimingLog = now
        NSLog("%@", timings.summary)
    }

    /// 1 秒ごとに、選手の数と番号をログに出す（画面を見られない実機で、検出が動いているかを確かめるため）。
    private func logPlayers(_ outcome: CourtPlayersOutcome) {
        let now = CACurrentMediaTime()
        guard now - lastPlayerLog >= 1 else { return }
        lastPlayerLog = now
        let ids = outcome.players.map { "\($0.id)\($0.isDetected ? "" : "?")" }.joined(separator: ",")
        // NSLog は、端末のログ（Console、log show）にも出る。print は、つないだコンソールにしか出ない。
        NSLog("%@", String(
            format: "[PlayerPose] t=%.1f players=%ld ids=[%@] poses=%ld %.0fms failure=%@",
            outcome.time, outcome.players.count, ids, outcome.poses.count, outcome.durationMilliseconds, outcome.failure ?? "-"
        ))
    }

    private func show(_ outcome: BallFrameOutcome) {
        isTrackingBall = false
        timings.addBall(outcome.durationMilliseconds)
        rally.append(outcome)
        ballSamples = rally.samples
        rallyIndex = rally.rallyIndex
    }
}

/// `CADisplayLink` から呼ばれる相手。`CADisplayLink` は相手を強く持つので、モデルを直接渡さない。
private final class DisplayLinkTarget: NSObject {
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor @objc func fire() {
        action()
    }
}

/// 画素バッファを、別のタスクに渡すための箱。検出の中では読むだけ。
private struct PixelBufferBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}
