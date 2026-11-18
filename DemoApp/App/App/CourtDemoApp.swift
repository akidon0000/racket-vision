import DemoFeature
import SwiftUI

/// アプリの起動点。動画の一覧の画面を出す（機能は DemoFeature）。
@main
struct CourtDemoApp: App {
    var body: some Scene {
        WindowGroup {
            // 画面の行き来（NavigationStack）は、VideoListView が持つ。
            VideoListView()
        }
    }
}
