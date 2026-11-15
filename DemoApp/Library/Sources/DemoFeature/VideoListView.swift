import CameraDetection
import SwiftUI
import VideoPlayback

/// 一覧の画面。一番上にカメラで撮影する入口を置き、その下にアプリに入っている動画を並べる。
/// 選んだ動画は、コートの検出の枠つきで流す。
public struct VideoListView: View {
    public init() {}

    private let videos: [URL] = (Bundle.main.urls(forResourcesWithExtension: "mp4", subdirectory: nil) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    public var body: some View {
        List {
            Section {
                NavigationLink {
                    CameraView()
                } label: {
                    Label("カメラで撮影", systemImage: "camera")
                }
            }
            Section("動画") {
                if videos.isEmpty {
                    Text("動画が入っていません。DemoApp/videos に動画を置き、アプリを作り直してください。")
                        .foregroundStyle(.secondary)
                }
                ForEach(videos, id: \.self) { url in
                    NavigationLink(url.deletingPathExtension().lastPathComponent) {
                        PlayerView(url: url)
                    }
                }
            }
        }
        .navigationTitle("コートの検出デモ")
    }
}
