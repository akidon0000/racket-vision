import AVFoundation
import BallTracking
import CoreVideo
import CourtFit
import PlayerPose
import SwiftUI
import UIKit

/// カメラの状態と、検出の結果。権限が無い、カメラが無いときは、理由を出す。
@MainActor
final class CameraModel: ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var quads: [DetectedQuad] = []
    @Published private(set) var milliseconds: Double = 0
    @Published private(set) var videoSize: CGSize = .zero
    @Published private(set) var isAvailable = true
    @Published private(set) var message = ""
    /// 今のラリーの、球の軌跡。
    @Published private(set) var ballSamples: [BallSample] = []
    @Published private(set) var rallyIndex = 0
    /// コートにいる選手（番号の順）。
    @Published private(set) var players: [CourtPlayer] = []
    /// 骨格の検出が動かなかったときの理由。動いていれば nil。
    @Published private(set) var playerFailure: String?

    let output = AVCaptureVideoDataOutput()
    /// 使っているカメラ。画面の向きに合わせて映像を回すのに使う（`CameraPreviewView`）。
    @Published private(set) var device: AVCaptureDevice?
    /// 外カメラか、インカメか。
    @Published private(set) var position: AVCaptureDevice.Position = .back
    /// 選べるズームの倍率（表示の倍率。1 が広角のレンズ、0.5 が超広角）。
    @Published private(set) var zoomPresets: [Double] = []
    /// 今のズームの倍率（表示の倍率）。
    @Published private(set) var zoom: Double = 1
    /// カメラを切り替えている途中か。
    @Published private(set) var isSwitching = false
    private var analyzer: FrameAnalyzer?
    private var rally = BallRallyTrajectory()
    /// カメラを入れ替えた回数。古いカメラの検出の結果を捨てるのに使う。
    private var generation = 0
    private let sessionQueue = DispatchQueue(label: "court-demo.camera.session")

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            isAvailable = false
            message = "カメラの使用が許可されていません。設定アプリで、このアプリのカメラを許可してください。"
            return
        }
        guard let device = Self.camera(at: .back) ?? Self.camera(at: .front) else {
            isAvailable = false
            message = "カメラが見つかりません（シミュレーターにはカメラがありません。実機で開いてください）。"
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        // 検出が追いつかないフレームは捨てる（映像を止めないため）。
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        use(device)
        let session = session
        sessionQueue.async { session.startRunning() }
    }

    /// 外カメラとインカメを切り替える。検出の続き（球の軌跡、コートの追従）は、写る場所が変わるので捨てる。
    func switchCamera() {
        let next: AVCaptureDevice.Position = position == .front ? .back : .front
        guard let device = Self.camera(at: next) else { return }
        isSwitching = true
        use(device)
        isSwitching = false
    }

    /// ズームの倍率（表示の倍率）を変える。カメラで選べる範囲に収める。
    func setZoom(_ display: Double) {
        guard let device else { return }
        let multiplier = Double(device.displayVideoZoomFactorMultiplier)
        let factor = min(max(display / multiplier, Double(device.minAvailableVideoZoomFactor)), Self.maximumZoomFactor(of: device))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = CGFloat(factor)
            device.unlockForConfiguration()
            zoom = factor * multiplier
        } catch {
            // 設定を変えられないときは、今の倍率のままにする。
        }
    }

    /// 倍率の表示（0.5×、1×、2× など）。
    static func zoomText(_ display: Double) -> String {
        let rounded = (display * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))×" : String(format: "%.1f×", rounded)
    }

    /// そのカメラを入力にして、検出をやり直す。インカメのときは、検出に渡す映像も左右を反転し、表示（鏡のように反転）とそろえる。
    private func use(_ device: AVCaptureDevice) {
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        for old in session.inputs {
            session.removeInput(old)
        }
        if session.canAddInput(input) { session.addInput(input) }
        // 切り替える前のカメラの検出の結果が、後から届いても使わない。
        generation += 1
        let current = generation
        let analyzer = FrameAnalyzer { [weak self] update in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.show(update)
            }
        }
        self.analyzer = analyzer
        output.setSampleBufferDelegate(analyzer, queue: DispatchQueue(label: "court-demo.camera"))
        if let connection = output.connection(with: .video) {
            // まず縦向きの映像にする。そのあとは、画面の向きに合わせて回す（`CameraPreviewView`）。
            // 検出は、いつも画面と同じ向きの映像（.up）にかける。
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = device.position == .front
            }
        }
        session.commitConfiguration()
        rally = BallRallyTrajectory()
        quads = []
        players = []
        ballSamples = []
        rallyIndex = 0
        self.device = device
        position = device.position
        zoomPresets = Self.zoomPresets(of: device)
        // 外カメラは 1×（広角のレンズ）から始める。インカメは、いちばん広く写る倍率から始める。
        setZoom(device.position == .front ? (zoomPresets.first ?? 1) : 1)
    }

    /// その向きのカメラ。外カメラは、レンズを自動で切り替える仮想のカメラ（超広角から望遠まで）を優先する。
    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position)
        // DiscoverySession の並びは、渡した種類の順になる。
        return discovery.devices.first
    }

    /// 選べるズームの倍率（表示の倍率）。0.5×、1×、2×、3×、5× のうち、そのカメラで選べるもの。
    private static func zoomPresets(of device: AVCaptureDevice) -> [Double] {
        let multiplier = Double(device.displayVideoZoomFactorMultiplier)
        let minimum = Double(device.minAvailableVideoZoomFactor) * multiplier
        let maximum = maximumZoomFactor(of: device) * multiplier
        let presets = [0.5, 1, 2, 3, 5].filter { $0 >= minimum - 0.01 && $0 <= maximum + 0.01 }
        // インカメなど、1× より広くできるが 0.5× まではいかないカメラは、いちばん広い倍率を先頭に足す。
        if minimum < 0.99, presets.first.map({ $0 > minimum + 0.05 }) ?? true {
            return [minimum] + presets
        }
        return presets
    }

    /// ズームの上限。デジタルの拡大で粗くなりすぎないよう、10 倍（装置の倍率）までにする。
    private static func maximumZoomFactor(of device: AVCaptureDevice) -> Double {
        min(Double(device.maxAvailableVideoZoomFactor), 10)
    }

    func stop() {
        let session = session
        sessionQueue.async { session.stopRunning() }
    }

    private func show(_ update: FrameAnalyzer.Update) {
        switch update {
        case let .court(quads, milliseconds, size):
            self.quads = quads
            self.milliseconds = milliseconds
            videoSize = size
        case let .ball(outcome):
            rally.append(outcome)
            ballSamples = rally.samples
            rallyIndex = rally.rallyIndex
        case let .players(outcome):
            players = outcome.players
            playerFailure = outcome.failure
        }
    }
}

/// カメラのフレームを、検出にかける（撮影の専用の作業の列で動く）。
///
/// 球の追跡は、続いたフレームが要るので、毎フレーム、撮影の列でかける（1 回数 ms）。
/// コートの検出（0.2 秒ごと）と骨格の検出（0.1 秒ごと）は重いので、それぞれ別の列でかけ、前の検出が終わるまで次はかけない。
/// 見つかったコートは、球と選手を探す範囲に使う。
final class FrameAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Update: Sendable {
        case court(quads: [DetectedQuad], milliseconds: Double, size: CGSize)
        case ball(BallFrameOutcome)
        case players(CourtPlayersOutcome)
    }

    private let courtAnalyzer = CourtAnalyzer(
        detectors: [TrackingLineModelCourtRectangleDetector(searchInterval: 0)],
        switches: CourtMethodSwitches(enabled: [.lineModelTracking])
    )
    private let ballDetector = MotionColorBallDetector()
    private let playerDetector = CourtPlayerDetector()
    private let courtQueue = DispatchQueue(label: "court-demo.camera.court", qos: .userInitiated)
    private let poseQueue = DispatchQueue(label: "court-demo.camera.pose", qos: .userInitiated)
    private let publish: @Sendable (Update) -> Void

    private let lock = NSLock()
    private var isFindingCourt = false
    private var isFindingPlayers = false
    private var lastCourtTime = -Double.infinity
    private var lastPoseTime = -Double.infinity

    init(publish: @escaping @Sendable (Update) -> Void) {
        self.publish = publish
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let box = PixelBufferBox(buffer: pixelBuffer)
        publish(.ball(ballDetector.detect(in: pixelBuffer, at: time)))
        if take(\.isFindingCourt, last: \.lastCourtTime, now: time, interval: 0.2) {
            courtQueue.async { [self] in
                let outcome = courtAnalyzer.analyze(box.buffer, orientation: .up).first
                let quads = outcome?.quads ?? []
                // 球は、見つかったコートの矩形の中（少し外まで）だけで探す。選手は、コートの中かその近くに立つ人を選ぶ。
                ballDetector.setCourtRegion(quads.first?.corners)
                playerDetector.setCourt(quads.first?.corners)
                let size = CGSize(width: CVPixelBufferGetWidth(box.buffer), height: CVPixelBufferGetHeight(box.buffer))
                publish(.court(quads: quads, milliseconds: outcome?.durationMilliseconds ?? 0, size: size))
                lock.withLock { isFindingCourt = false }
            }
        }
        if take(\.isFindingPlayers, last: \.lastPoseTime, now: time, interval: 0.1) {
            poseQueue.async { [self] in
                publish(.players(playerDetector.detect(in: box.buffer, at: time)))
                lock.withLock { isFindingPlayers = false }
            }
        }
    }

    /// 前の検出が終わっていて、前にかけてから `interval` 秒たっていれば、検出中にして true を返す。
    private func take(
        _ busy: ReferenceWritableKeyPath<FrameAnalyzer, Bool>, last: ReferenceWritableKeyPath<FrameAnalyzer, Double>,
        now: Double, interval: Double
    ) -> Bool {
        lock.withLock {
            guard !self[keyPath: busy], now - self[keyPath: last] >= interval else { return false }
            self[keyPath: busy] = true
            self[keyPath: last] = now
            return true
        }
    }
}

/// 画素バッファを、別の作業の列に渡すための箱。検出の中では読むだけ。
private struct PixelBufferBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}
