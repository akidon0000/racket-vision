// swift-tools-version: 6.2

import PackageDescription

// デモの機能。アプリの殻（DemoApp/App）から取り込む。
// コートの検出は、同じリポジトリの CourtFit（ルートのパッケージ）を使う。
let package = Package(
    name: "DemoLibrary",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "DemoFeature", targets: ["DemoFeature"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        // 枠を描く部品と、表示の範囲の計算（動画とカメラで共通）
        .target(
            name: "CourtLineOverlay",
            dependencies: [.product(name: "CourtFit", package: "racket-vision")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 球の軌跡の点を描く部品
        .target(
            name: "BallTrackOverlay",
            dependencies: [.product(name: "BallTracking", package: "racket-vision")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 動画を流しながら、コートの検出の枠と、球の軌跡の点を重ねる
        .target(
            name: "VideoPlayback",
            dependencies: [
                "CourtLineOverlay",
                "BallTrackOverlay",
                .product(name: "CourtFit", package: "racket-vision"),
                .product(name: "BallTracking", package: "racket-vision")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // カメラの映像に、コートの検出の枠を重ねる
        .target(
            name: "CameraDetection",
            dependencies: ["CourtLineOverlay", .product(name: "CourtFit", package: "racket-vision")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 一覧の画面（動画の一覧と、カメラの入口）
        .target(
            name: "DemoFeature",
            dependencies: ["VideoPlayback", "CameraDetection"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
