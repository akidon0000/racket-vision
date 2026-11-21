import BallTracking
import CourtScene
import PlayerPose
import RealityKit
import SwiftUI

/// 解析の結果（コート、選手、球、映像のカメラ）を、白い背景の 3D で描く。ドラッグで、視点をコートの中心のまわりに回す。
/// ピンチ（Mac ではトラックパッドのピンチ）で近づく・離れる。最初の視点は、映像のカメラの後ろの斜め上（カメラの印が見える）。
/// 「カメラの視点」で、映像のカメラの位置に合わせる（動画と同じ見え方）。
public struct CourtSceneView: View {
    let corners: [CGPoint]?
    let imageSize: CGSize
    let players: [CourtPlayer]
    let ballSamples: [BallSample]
    let rallyIndex: Int

    @State private var store: SceneStore?
    @State private var orbit = SceneOrbit.standard
    @State private var dragStart: SceneOrbit?
    @State private var zoomStart: SceneOrbit?
    /// 映像のカメラの位置に、視点を合わせたか。最初にコートが見つかったときに 1 回だけ合わせる。
    @State private var hasMatchedCamera = false
    /// リアルタイムの球（まだ飛んでいる途中の打球を、今ある点だけで置いたもの）も描くか。
    @State private var showsLiveBall: Bool
    /// 視点のボタンと「リアルタイムの球」のボタンを出すか（小さく描くときは出さない）。
    private let showsControls: Bool

    /// `corners` は、コートの四隅（正規化座標、左下が原点。`DetectedQuad.corners` と同じ）。`imageSize` は、映像の大きさ（画素）。
    /// `showsControls` が false なら、ボタンを出さない。`showsLiveBallInitially` は、リアルタイムの球を最初から描くか。
    public init(
        corners: [CGPoint]?, imageSize: CGSize, players: [CourtPlayer], ballSamples: [BallSample], rallyIndex: Int,
        showsControls: Bool = true, showsLiveBallInitially: Bool = false
    ) {
        self.showsControls = showsControls
        _showsLiveBall = State(initialValue: showsLiveBallInitially)
        self.corners = corners
        self.imageSize = imageSize
        self.players = players
        self.ballSamples = ballSamples
        self.rallyIndex = rallyIndex
    }

    private var courtCamera: CourtCamera? {
        corners.flatMap { CourtCamera(corners: $0, imageSize: imageSize) }
    }

    public var body: some View {
        GeometryReader { proxy in
            let aspect = proxy.size.height > 0 ? Double(proxy.size.width / proxy.size.height) : 1
            RealityView { content in
                let store = SceneStore()
                content.add(store.root)
                content.add(store.camera)
                store.apply(orbit, aspect: aspect)
                self.store = store
            } update: { _ in
                guard let store else { return }
                store.apply(orbit, aspect: aspect)
                let camera = courtCamera
                let placed = camera.map { $0.place(players) } ?? []
                let balls = camera.map { BallTrajectory(samples: ballSamples, camera: $0) }
                store.update(
                    courtCamera: camera, players: placed, trajectory: balls?.settled ?? [],
                    live: showsLiveBall ? balls?.live ?? [] : [], rallyColor: BallRallyPalette.color(forRally: rallyIndex)
                )
            }
        }
        .background(Color.white)
        .gesture(drag)
        .simultaneousGesture(zoom)
        .overlay(alignment: .topTrailing) {
            if showsControls {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Button("全体") { showOverview() }
                        Button("カメラの視点") { matchCamera() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    if let cameraText {
                        Text(cameraText)
                            .font(.caption2)
                            .foregroundStyle(.black.opacity(0.7))
                    }
                }
                .padding(8)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsControls {
                Toggle("リアルタイムの球", isOn: $showsLiveBall)
                    .toggleStyle(.button)
                    .font(.caption)
                    .padding(8)
            }
        }
        // 映像のカメラが分かったら、最初の 1 回だけ、視点をそこに合わせる。コートの位置が最初から変わらないときも合わせるよう、
        // 出たときにも確かめる。
        .onAppear(perform: matchCameraOnce)
        .onChange(of: corners) { matchCameraOnce() }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? orbit
                dragStart = start
                var next = start
                next.rotate(byDrag: value.translation)
                orbit = next
            }
            .onEnded { _ in dragStart = nil }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? orbit
                zoomStart = start
                var next = start
                next.zoom(by: value.magnification)
                orbit = next
            }
            .onEnded { _ in zoomStart = nil }
    }

    /// 映像のカメラが分かった最初の 1 回だけ、カメラとコートの両方が見える視点にする。
    private func matchCameraOnce() {
        if !hasMatchedCamera {
            showOverview()
        }
    }

    /// 視点を、映像のカメラの後ろの斜め上にする（カメラの印とコートの両方が見える）。
    private func showOverview() {
        guard let camera = courtCamera else { return }
        orbit = SceneOrbit(overviewOf: camera)
        hasMatchedCamera = true
    }

    /// 視点を、映像のカメラの位置に合わせる（動画と同じ見え方になる）。
    private func matchCamera() {
        guard let camera = courtCamera else { return }
        orbit = SceneOrbit(camera: camera)
        hasMatchedCamera = true
    }

    /// 映像のカメラの高さと、コートの中心からの距離。
    private var cameraText: String? {
        guard let position = courtCamera?.position else { return nil }
        let ground = (position.x * position.x + position.z * position.z).squareRoot()
        return String(format: "カメラ: 高さ %.1f m、コートの中心から %.1f m", position.y, ground)
    }
}
