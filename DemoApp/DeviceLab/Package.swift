// swift-tools-version: 6.2

import PackageDescription

// 機種ごとの再現（DeviceLab）。iPhone の機種と OS の条件で、デモと同じ処理を Mac で流す。
// 設計は docs/superpowers/specs/2026-11-16-device-lab-design.md。macOS アプリの殻は App/（xcodegen）。
let package = Package(
    name: "DeviceLab",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DeviceSimulation", targets: ["DeviceSimulation"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        // 機種の条件、仮の時計での処理、動画の読み込み。画面は持たない。
        .target(
            name: "DeviceSimulation",
            dependencies: [
                .product(name: "CourtFit", package: "racket-vision"),
                .product(name: "BallTracking", package: "racket-vision"),
                .product(name: "PlayerPose", package: "racket-vision")
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DeviceSimulationTests",
            dependencies: ["DeviceSimulation"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
