import AVKit
import CourtSceneView
import DeviceSimulation
import SwiftUI

/// 上に動画、下に 2 つの機種の 3D のシミュレーションを並べる。
struct LabView: View {
    @StateObject private var model = LabModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            PlayerNSView(player: model.player)
                .frame(minHeight: 220, idealHeight: 300)
            Divider()
            HStack(spacing: 0) {
                DeviceColumn(model: model, profile: $model.left)
                Divider()
                DeviceColumn(model: model, profile: $model.right)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Picker("動画", selection: $model.video) {
                ForEach(model.videos, id: \.self) { url in
                    Text(url.deletingPathExtension().lastPathComponent).tag(Optional(url))
                }
            }
            .frame(maxWidth: 360)
            Button("この 2 機種で流す") { model.run() }
                .keyboardShortcut(.return)
                .disabled(model.video == nil)
            Spacer()
            Text("検出は Mac で動かし、時間は機種の値で数える（仮の時計）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }
}

/// 1 つの機種の列。機種の選択、3D のシミュレーション、数。
private struct DeviceColumn: View {
    @ObservedObject var model: LabModel
    @Binding var profile: DeviceProfile?

    var body: some View {
        VStack(spacing: 0) {
            Picker("機種", selection: $profile) {
                ForEach(model.profiles) { profile in
                    Text("\(profile.name)（iOS \(profile.os)）\(profile.source == .estimated ? "・見込み" : "")").tag(Optional(profile))
                }
            }
            .padding(8)
            ZStack {
                Color.white
                if let result = model.result(for: profile), let frame = result.frame(at: model.currentTime) {
                    CourtSceneView(
                        corners: frame.court, imageSize: result.imageSize, players: frame.players,
                        ballSamples: frame.ballSamples, rallyIndex: frame.rallyIndex
                    )
                } else if let id = profile?.id, let value = model.progress[id] {
                    ProgressView(String(format: "この機種で流しています（%.0f%%）", value * 100), value: value)
                        .frame(maxWidth: 280)
                } else if let id = profile?.id, model.isWaiting(id) {
                    Text("もう 1 つの機種を流し終えたら、この機種を流します")
                } else {
                    Text("「この 2 機種で流す」を押すと、ここに結果が出ます")
                }
            }
            // 白い背景の上なので、Mac がダークモードでも、文字は明るいモードの色で描く。
            .environment(\.colorScheme, .light)
            .foregroundStyle(.secondary)
            stats
        }
    }

    @ViewBuilder private var stats: some View {
        if let result = model.result(for: profile), let profile {
            let latency = profile.latency
            VStack(alignment: .leading, spacing: 2) {
                Text(String(
                    format: "検出の時間  コート %.0f ms、球 %.0f ms、骨格 %.0f ms（ばらつき ±%.0f%%）",
                    latency.court, latency.ball, latency.pose, profile.jitter * 100
                ))
                Text(String(
                    format: "球の検出をかけたフレーム %.0f%%、骨格の検出 %.1f 回/秒、映像 %.0f×%.0f・%.0f コマ/秒",
                    result.ballRunRatio * 100, result.poseRunsPerSecond, result.imageSize.width, result.imageSize.height, result.frameRate
                ))
                Text(String(
                    format: "選手 4 人がそろったフレーム %.0f%%、球を出したフレーム %.0f%%",
                    result.fourPlayersRatio * 100, result.ballRatio * 100
                ))
                .bold()
            }
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}
