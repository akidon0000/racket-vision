// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RacketVision",
    platforms: [
        .iOS(.v18),
        // 計算のテストと、デモ動画での採点を、ホストの macOS で swift test できるようにするため。
        .macOS(.v14)
    ],
    products: [
        .library(name: "CourtFit", targets: ["CourtFit"]),
        .library(name: "CourtOverlay", targets: ["CourtOverlay"]),
        .library(name: "BallTracking", targets: ["BallTracking"]),
        .library(name: "PlayerPose", targets: ["PlayerPose"]),
        .library(name: "CourtScene", targets: ["CourtScene"]),
        .library(name: "SceneAdvisor", targets: ["SceneAdvisor"])
    ],
    targets: [
        // コートの検出。画素を 1 つずつ回す計算が多く、最適化なし（Debug）では 1 フレームに数秒かかる。
        // 使う側のアプリの開発ビルドでも枠が遅れずに出るよう、Debug でも最適化する。
        .target(name: "CourtFit", swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        // 検出の線を映像の上に描く（iOS の画面の部品）。
        .target(name: "CourtOverlay", dependencies: ["CourtFit"]),
        .testTarget(name: "CourtFitTests", dependencies: ["CourtFit", "VideoTestSupport"]),
        // 球の追跡。全画素を回すので、CourtFit と同じく Debug でも最適化する。
        .target(name: "BallTracking", swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        // テスト用の共通の部品（動画を順に読む、画像と動画を書き出す、コートの矩形を残して読む）。ライブラリとしては出さない。
        .target(name: "VideoTestSupport", dependencies: ["CourtFit"]),
        .testTarget(name: "BallTrackingTests", dependencies: ["BallTracking", "VideoTestSupport", "CourtFit"]),
        // 選手の骨格の検出と、コートにいる選手の特定。
        .target(name: "PlayerPose", dependencies: ["CourtFit"]),
        .testTarget(name: "PlayerPoseTests", dependencies: ["PlayerPose", "VideoTestSupport", "CourtFit"]),
        // 解析の結果（コート、選手、球）を、コートの 3D の座標に置く。
        .target(name: "CourtScene", dependencies: ["CourtFit", "PlayerPose", "BallTracking"]),
        .testTarget(name: "CourtSceneTests", dependencies: ["CourtScene", "CourtFit", "PlayerPose", "BallTracking"]),
        // 外部のモデル（TypeSafe AI の Jev）に映像の 1 枚を見せて、検出の設定（球の色、拾う線の色）を選ぶ。試作。
        .target(name: "SceneAdvisor", dependencies: ["BallTracking", "CourtFit"]),
        .testTarget(name: "SceneAdvisorTests", dependencies: ["SceneAdvisor", "BallTracking", "CourtFit", "VideoTestSupport"])
    ]
)
