import AVFoundation
import CoreVideo
import CourtFit
import SwiftUI
import CourtLineOverlay
import UIKit

/// カメラの映像に、コートの検出の枠を重ねる。映像は保存せず、その場で検出して表示する。
public struct CameraView: View {
    public init() {}

    @StateObject private var model = CameraModel()
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if model.isAvailable {
                    CameraPreviewView(session: model.session)
                    QuadsOverlay(quads: model.quads, rect: fillRect(container: proxy.size, video: model.videoSize))
                } else {
                    Text(model.message)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .clipped()
        }
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
            if model.isAvailable {
                Text(statusText)
                    .font(.footnote.monospaced())
                    .padding(8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var statusText: String {
        let found = model.quads.isEmpty ? "検出なし" : "検出あり"
        return String(format: "%@  %.1f ms", found, model.milliseconds)
    }
}

/// カメラの状態と、検出の結果。権限が無い、カメラが無いときは、理由を出す。
@MainActor
final class CameraModel: ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var quads: [DetectedQuad] = []
    @Published private(set) var milliseconds: Double = 0
    @Published private(set) var videoSize: CGSize = .zero
    @Published private(set) var isAvailable = true
    @Published private(set) var message = ""

    private let output = AVCaptureVideoDataOutput()
    private var analyzer: FrameAnalyzer?

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            isAvailable = false
            message = "カメラの使用が許可されていません。設定アプリで、このアプリのカメラを許可してください。"
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            isAvailable = false
            message = "カメラが見つかりません（シミュレーターにはカメラがありません。実機で開いてください）。"
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        // 検出が追いつかないフレームは捨てる（映像を止めないため）。
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let analyzer = FrameAnalyzer { [weak self] result in
            Task { @MainActor in self?.show(result) }
        }
        self.analyzer = analyzer
        output.setSampleBufferDelegate(analyzer, queue: DispatchQueue(label: "court-demo.camera"))
        if session.canAddOutput(output) { session.addOutput(output) }
        // 縦向きの映像にして、検出の向き（.up）と画面の向きをそろえる。
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func stop() {
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    private func show(_ result: FrameAnalyzer.Result) {
        quads = result.quads
        milliseconds = result.milliseconds
        videoSize = result.size
    }
}

/// カメラのフレームを、コートの検出にかける（撮影の専用の作業の列で動く）。
final class FrameAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Result: Sendable {
        let quads: [DetectedQuad]
        let milliseconds: Double
        let size: CGSize
    }

    private let analyzer = CourtAnalyzer(
        detectors: [TrackingLineModelCourtRectangleDetector(searchInterval: 0)],
        switches: CourtMethodSwitches(enabled: [.lineModelTracking])
    )
    private let publish: @Sendable (Result) -> Void

    init(publish: @escaping @Sendable (Result) -> Void) {
        self.publish = publish
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let outcome = analyzer.analyze(pixelBuffer, orientation: .up).first
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        publish(Result(quads: outcome?.quads ?? [], milliseconds: outcome?.durationMilliseconds ?? 0, size: size))
    }
}

/// カメラの映像を表示する層。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass で指定しているので、必ず AVCaptureVideoPreviewLayer になる。
        layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
    }
}
