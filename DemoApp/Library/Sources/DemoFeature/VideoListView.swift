import SwiftUI

/// アプリに入っている動画の一覧。選ぶと、その動画をコートの検出つきで流す。
public struct VideoListView: View {
    public init() {}

    private let videos: [URL] = (Bundle.main.urls(forResourcesWithExtension: "mp4", subdirectory: nil) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    public var body: some View {
        List {
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
        .navigationTitle("コートの検出デモ")
    }
}
