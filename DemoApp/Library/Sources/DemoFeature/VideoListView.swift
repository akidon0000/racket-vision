import CameraDetection
import SwiftUI
import VideoPlayback

/// 一覧の画面。一番上にカメラで撮影する入口を置き、その下にアプリに入っている動画を並べる。
/// 選んだ動画は、コートの検出の枠つきで流す。
///
/// 起動引数 `-autoplay <動画の名前の一部>` を渡すと、その動画を開いた状態で始まる（実機で、画面に触れずに確かめるため）。
public struct VideoListView: View {
    public init() {}

    @State private var path: [URL] = []

    private let videos: [URL] = (Bundle.main.urls(forResourcesWithExtension: "mp4", subdirectory: nil) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    public var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationDestination(for: URL.self) { PlayerView(url: $0) }
        }
        .onAppear(perform: autoplay)
    }

    private var list: some View {
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
                    NavigationLink(url.deletingPathExtension().lastPathComponent, value: url)
                }
            }
        }
        .navigationTitle("コートの検出デモ")
    }

    private func autoplay() {
        let arguments = ProcessInfo.processInfo.arguments
        guard path.isEmpty, let index = arguments.firstIndex(of: "-autoplay"), index + 1 < arguments.count else { return }
        let name = arguments[index + 1]
        if let url = videos.first(where: { $0.lastPathComponent.contains(name) }) {
            path = [url]
        }
    }
}
