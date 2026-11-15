// swift-tools-version: 6.2

import PackageDescription

// デモの機能（動画の一覧、動画の再生と検出の表示）。アプリの殻（App/）から取り込む。
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
        .target(
            name: "DemoFeature",
            dependencies: [.product(name: "CourtFit", package: "racket-vision")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
