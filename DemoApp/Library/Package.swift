// swift-tools-version: 6.2

import PackageDescription

// デモの機能。アプリの殻（DemoApp/App）から取り込む。
// コートの検出は、同じリポジトリの CourtFit（ルートのパッケージ）を使う。
let package = Package(
    name: "DemoLibrary",
    platforms: [
        .iOS(.v18),
        // 3D のシミュレーションなどの部品は、Mac のアプリ（DeviceLab）でも使う。
        .macOS(.v15)
    ],
    products: [
        .library(name: "DemoFeature", targets: ["DemoFeature"]),
        // Mac のアプリ（DeviceLab）でも使う、3D のシミュレーションの部品。
        .library(name: "CourtSceneView", targets: ["CourtSceneView"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        // 映像に検出したコートの線を重ねる部品と、映像の表示の範囲の計算（動画とカメラで共通）
        .target(
            name: "CourtLineOverlay",
            dependencies: [.product(name: "CourtFit", package: "racket-vision")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 解析の結果を 3D で描く部品（iOS と macOS）
        .target(
            name: "CourtSceneView",
            dependencies: [
                .product(name: "CourtScene", package: "racket-vision"),
                .product(name: "PlayerPose", package: "racket-vision"),
                .product(name: "BallTracking", package: "racket-vision"),
                .product(name: "CourtFit", package: "racket-vision")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 動画を流しながら、映像にコートの線を重ね、検出の結果（コート、球の軌跡、選手の骨格）を 3D で描く
        .target(
            name: "VideoPlayback",
            dependencies: [
                "CourtLineOverlay",
                "CourtSceneView",
                .product(name: "CourtFit", package: "racket-vision"),
                .product(name: "BallTracking", package: "racket-vision"),
                .product(name: "PlayerPose", package: "racket-vision")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // カメラの映像に、コートの検出の枠を重ねる。球と選手の骨格も検出し、右下に小さく 3D で描く
        .target(
            name: "CameraDetection",
            dependencies: [
                "CourtLineOverlay",
                "CourtSceneView",
                .product(name: "CourtFit", package: "racket-vision"),
                .product(name: "BallTracking", package: "racket-vision"),
                .product(name: "PlayerPose", package: "racket-vision")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 動画の一覧を、見出し（撮った日、サンプル動画）ごとに分ける
        .target(name: "VideoCatalog"),
        .testTarget(name: "VideoCatalogTests", dependencies: ["VideoCatalog"]),
        // 一覧の画面（動画の一覧と、カメラの入口）
        .target(
            name: "DemoFeature",
            dependencies: ["VideoPlayback", "CameraDetection", "VideoCatalog"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
