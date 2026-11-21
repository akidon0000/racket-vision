import AVFoundation
import BallTracking
import CoreVideo
import CourtFit
import CourtLineOverlay
import CourtSceneView
import PlayerPose
import SwiftUI
import UIKit

/// カメラの映像に、コートの検出の枠を重ねる。あわせて、球の追跡と選手の骨格の検出もかけ、右下に小さく 3D で描く。
/// 映像は保存せず、その場で検出して表示する。
public struct CameraView: View {
    public init() {}

    @StateObject private var model = CameraModel()
    @Environment(\.dismiss) private var dismiss
    /// ピンチを始めたときのズームの倍率。
    @State private var pinchStart: Double?

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if model.isAvailable {
                    CameraPreviewView(session: model.session, device: model.device, output: model.output)
                    CourtLinesOverlay(
                        corners: model.quads.first?.corners, rect: fillRect(container: proxy.size, video: model.videoSize),
                        color: .red, lineWidth: 3
                    )
                } else {
                    Text(model.message)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(pinch)
            .overlay(alignment: .bottomTrailing) {
                if model.isAvailable {
                    scene(container: proxy.size)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if model.isAvailable {
                    cameraControls
                        .padding(.leading, 16)
                        .padding(.bottom, 32)
                }
            }
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
        .overlay(alignment: .top) {
            if model.isAvailable {
                Text(statusText)
                    .font(.caption2.monospaced())
                    .padding(6)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
                    .padding(.top, 14)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    /// 左下の操作。外カメラとインカメの切り替えと、ズームの倍率（0.5× の超広角など、そのカメラで選べるもの）。
    private var cameraControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(model.zoomPresets, id: \.self) { preset in
                    Button {
                        model.setZoom(preset)
                    } label: {
                        Text(CameraModel.zoomText(preset))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(isCurrent(preset) ? .yellow : .white)
                            .frame(minWidth: 38, minHeight: 38)
                            .background(.black.opacity(0.6), in: Circle())
                    }
                    .accessibilityLabel("ズーム \(CameraModel.zoomText(preset))")
                }
            }
            Button {
                model.switchCamera()
            } label: {
                Label(model.position == .front ? "外カメラへ" : "インカメへ", systemImage: "arrow.triangle.2.circlepath.camera")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
            }
            .disabled(model.isSwitching)
        }
    }

    private func isCurrent(_ preset: Double) -> Bool {
        abs(model.zoom - preset) < 0.05
    }

    /// ピンチで、ズームの倍率を連続に変える。
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? model.zoom
                pinchStart = start
                model.setZoom(start * value.magnification)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// 右下の小さな 3D（コート、選手の骨格、球）。画面の短い辺の 45% の幅。
    private func scene(container: CGSize) -> some View {
        let width = min(container.width, container.height) * 0.45
        return CourtSceneView(
            corners: model.quads.first?.corners, imageSize: model.videoSize, players: model.players,
            ballSamples: model.ballSamples, rallyIndex: model.rallyIndex, showsControls: false, showsLiveBallInitially: true
        )
        .frame(width: width, height: width * 1.2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.8), lineWidth: 1))
        .shadow(radius: 4)
        .padding(.trailing, 16)
        .padding(.bottom, 32)
    }

    private var statusText: String {
        let found = model.quads.isEmpty ? "コートなし" : "コートあり"
        let players = model.playerFailure == nil ? "選手 \(model.players.count) 人" : "選手 検出不可"
        let camera = "\(model.position == .front ? "イン" : "外") \(CameraModel.zoomText(model.zoom))"
        return String(format: "%@  %@  %.1f ms  球 %ld 点  %@", camera, found, model.milliseconds, model.ballSamples.count, players)
    }
}
