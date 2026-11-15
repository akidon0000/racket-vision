import AVFoundation
import BallTracking
import BallTrackOverlay
import CoreVideo
import CourtFit
import QuartzCore
import CourtLineOverlay
import SwiftUI
import UIKit

/// 動画を流し、コートの検出の結果を枠で、球の軌跡を点で重ねる。
public struct PlayerView: View {
    @StateObject private var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    public init(url: URL) {
        _model = StateObject(wrappedValue: PlayerModel(url: url))
    }

    public var body: some View {
        GeometryReader { proxy in
            let rect = fitRect(container: proxy.size, video: model.videoSize)
            ZStack {
                Color.black
                PlayerLayerView(player: model.player)
                QuadsOverlay(quads: model.quads, rect: rect)
                BallDotsOverlay(samples: model.ballSamples, rallyIndex: model.rallyIndex, rect: rect)
            }
        }
        // 画面いっぱいに出す（安全領域の外まで、黒い背景と映像を広げる）。
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
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
        .overlay(alignment: .bottom) {
            Text(statusText)
                .font(.footnote.monospaced())
                .padding(8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
                .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
        .onDisappear { model.stop() }
    }

    private var statusText: String {
        let found = model.quads.isEmpty ? "検出なし" : "検出あり"
        let ball = "球 \(model.ballSamples.count) 点（ラリー \(model.rallyIndex + 1)）"
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
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // layerClass で AVPlayerLayer を指定しているので、必ず AVPlayerLayer になる。
        layer as? AVPlayerLayer ?? AVPlayerLayer()
    }
}

/// 検出の結果を持つ、動画の再生の状態。画面の更新のたびに新しいフレームを取り、球の追跡にかける。
/// コートの検出には、0.2 秒ごとにかける。どちらも、前の検出が終わるまで次はかけない（間に合わないフレームは飛ばす）。
@MainActor
final class PlayerModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var quads: [DetectedQuad] = []
    @Published private(set) var milliseconds: Double?
    @Published private(set) var videoSize: CGSize = .zero
    /// 今のラリーの、球の軌跡。
    @Published private(set) var ballSamples: [BallSample] = []
    @Published private(set) var rallyIndex = 0

    private let item: AVPlayerItem
    private let output: AVPlayerItemVideoOutput
    private let analyzer = CourtAnalyzer(
        detectors: [TrackingLineModelCourtRectangleDetector(searchInterval: 0)],
        switches: CourtMethodSwitches(enabled: [.lineModelTracking])
    )
    private let ballDetector = MotionColorBallDetector()
    private var rally = BallRallyTrajectory()
    private var displayLink: CADisplayLink?
    private var isAnalyzing = false
    private var isTrackingBall = false
    private var lastCourtSample: CFTimeInterval = 0

    init(url: URL) {
        item = AVPlayerItem(url: url)
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
        analyzeCourt(in: box)
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
        quads = outcome?.quads ?? []
        milliseconds = outcome?.durationMilliseconds
    }

    private func show(_ outcome: BallFrameOutcome) {
        isTrackingBall = false
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
