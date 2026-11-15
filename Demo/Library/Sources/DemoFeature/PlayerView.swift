import AVFoundation
import CoreVideo
import CourtFit
import QuartzCore
import SwiftUI
import UIKit

/// 動画を流し、コートの検出の結果を枠で重ねる。
struct PlayerView: View {
    @StateObject private var model: PlayerModel

    init(url: URL) {
        _model = StateObject(wrappedValue: PlayerModel(url: url))
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = fitRect(container: proxy.size, video: model.videoSize)
            ZStack {
                Color.black
                PlayerLayerView(player: model.player)
                QuadsOverlay(quads: model.quads, rect: rect)
            }
        }
        .overlay(alignment: .bottom) {
            Text(statusText)
                .font(.footnote.monospaced())
                .padding(8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
                .padding(.bottom, 24)
        }
        .task { await model.load() }
        .onDisappear { model.stop() }
    }

    private var statusText: String {
        let found = model.quads.isEmpty ? "検出なし" : "検出あり"
        guard let milliseconds = model.milliseconds else { return found }
        return String(format: "%@  %.1f ms", found, milliseconds)
    }
}

/// 動画の表示の範囲（縦横比を保って、枠の中に収める）。
func fitRect(container: CGSize, video: CGSize) -> CGRect {
    guard video.width > 0, video.height > 0 else { return CGRect(origin: .zero, size: container) }
    let scale = min(container.width / video.width, container.height / video.height)
    let width = video.width * scale
    let height = video.height * scale
    return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2, width: width, height: height)
}

/// 検出した四角形を、表示の範囲に合わせて描く。
struct QuadsOverlay: View {
    let quads: [DetectedQuad]
    let rect: CGRect

    var body: some View {
        Canvas { context, _ in
            for quad in quads {
                // DetectedQuad は左下が原点の正規化座標。画面は左上が原点。
                let points = quad.corners.map {
                    CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + (1 - $0.y) * rect.height)
                }
                var path = Path()
                path.move(to: points[0])
                points.dropFirst().forEach { path.addLine(to: $0) }
                path.closeSubpath()
                context.stroke(path, with: .color(.pink), lineWidth: 4)
            }
        }
        .allowsHitTesting(false)
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

/// 検出の結果を持つ、動画の再生の状態。映像のフレームを一定の間隔で取り、検出にかける（前の検出が終わるまで次は取らない）。
@MainActor
final class PlayerModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var quads: [DetectedQuad] = []
    @Published private(set) var milliseconds: Double?
    @Published private(set) var videoSize: CGSize = .zero

    private let item: AVPlayerItem
    private let output: AVPlayerItemVideoOutput
    private let analyzer = CourtAnalyzer(
        detectors: [TrackingLineModelCourtRectangleDetector(searchInterval: 0)],
        switches: CourtMethodSwitches(enabled: [.lineModelTracking])
    )
    private var timer: Timer?
    private var isAnalyzing = false

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
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.pause()
    }

    private func sample() {
        guard !isAnalyzing else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        isAnalyzing = true
        let box = PixelBufferBox(buffer: buffer)
        let analyzer = analyzer
        // 検出は画面の外で動かす（画面を止めないため）。結果だけ画面に出す。
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
}

/// 画素バッファを、別のタスクに渡すための箱。検出の中では読むだけ。
private struct PixelBufferBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}
