import AVFoundation
import SwiftUI
import UIKit

/// カメラの映像を表示する層。カメラが決まったら、画面の向き（縦、横）に合わせて、表示と検出に渡す映像を回す。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    let output: AVCaptureVideoDataOutput

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if let device {
            uiView.followRotation(of: device, output: output)
        }
    }
}

final class CameraPreviewUIView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass で指定しているので、必ず AVCaptureVideoPreviewLayer になる。
        layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
    }

    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observations = [NSKeyValueObservation]()

    /// 画面の向きが変わるたびに、表示する映像と、検出に渡す映像（`output`）を、水平が保たれる向きに回す。
    /// カメラが切り替わったら（インカメと外カメラ）、そのカメラで作り直す。
    func followRotation(of device: AVCaptureDevice, output: AVCaptureVideoDataOutput) {
        guard coordinator?.device?.uniqueID != device.uniqueID else { return }
        observations = []
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        self.coordinator = coordinator
        let apply = { [weak self] in
            let preview = coordinator.videoRotationAngleForHorizonLevelPreview
            if let connection = self?.previewLayer.connection, connection.isVideoRotationAngleSupported(preview) {
                connection.videoRotationAngle = preview
            }
            let capture = coordinator.videoRotationAngleForHorizonLevelCapture
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(capture) {
                connection.videoRotationAngle = capture
            }
        }
        apply()
        observations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview) { _, _ in DispatchQueue.main.async(execute: apply) },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture) { _, _ in DispatchQueue.main.async(execute: apply) }
        ]
    }
}
