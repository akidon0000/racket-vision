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
        .library(name: "CourtOverlay", targets: ["CourtOverlay"])
    ],
    targets: [
        // コートの検出。画素を 1 つずつ回す計算が多いので、使う側のアプリは Release で測ること（Debug だと 1 フレームに数秒かかる）。
        .target(name: "CourtFit"),
        // 検出の線を映像の上に描く（iOS の画面の部品）。
        .target(name: "CourtOverlay", dependencies: ["CourtFit"]),
        .testTarget(name: "CourtFitTests", dependencies: ["CourtFit"])
    ]
)
