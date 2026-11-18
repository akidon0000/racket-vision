import SwiftUI

/// 機種ごとの再現のアプリ。動画と 2 つの機種を選び、その機種の条件でデモと同じ処理を流して、結果を並べて比べる。
@main
struct DeviceLabApp: App {
    var body: some Scene {
        WindowGroup("DeviceLab") {
            LabView()
                .frame(minWidth: 900, minHeight: 700)
        }
    }
}
