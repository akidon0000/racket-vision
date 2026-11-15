@testable import CourtFit

// 方式ごとの、画面に出す四角形を、デモ動画の 2 秒ごとに JSON で書き出す（方式の比べ合わせ用）。
// COURT_DEMO_DIR と COURT_QUADS_JSON（書き出す先のファイル）を指定したときだけ動く。
// アプリと同じく、CourtAnalyzer（ありえない四角形のふるい込みを含む）を通した結果を書く。
import AVFoundation
import Foundation
import Testing

/// 1 フレームぶんの書き出し。
struct DemoVideoQuadsExport: Encodable {
    var video: String
    var seconds: Double
    /// フレームの大きさ（ピクセル）。四隅の正規化座標を、ピクセルに戻すのに使う。
    var imageWidth: Int
    var imageHeight: Int
    /// 方式の rawValue から、四角形の四隅（正規化座標、左下が原点）の一覧。
    var quads: [String: [[[Double]]]]
    var milliseconds: [String: Double]

    /// 1 本の動画を、1 秒目から 2 秒ごとに検出する。
    static func frames(of video: URL) async throws -> [DemoVideoQuadsExport] {
        // 追従の方式は前のフレームを覚えるので、動画ごとに作り直す。探索の間隔は 0（2 秒おきなので毎回探してよい）。
        let detectors = detectorsToCompare().map { detector -> any CourtRectangleDetector in
            detector is TrackingLineModelCourtRectangleDetector ? TrackingLineModelCourtRectangleDetector(searchInterval: 0) : detector
        }
        let analyzer = CourtAnalyzer(detectors: detectors, switches: CourtMethodSwitches(enabled: Set(detectors.map(\.method))))
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var frames = [DemoVideoQuadsExport]()
        for seconds in stride(from: 1.0, to: duration, by: 2) {
            guard let image = try? generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil) else { continue }
            let outcomes = try analyzer.analyze(makePixelBuffer(from: image), orientation: .up)
            frames.append(DemoVideoQuadsExport(
                video: video.deletingPathExtension().lastPathComponent,
                seconds: seconds,
                imageWidth: image.width,
                imageHeight: image.height,
                quads: Dictionary(uniqueKeysWithValues: outcomes.map { outcome in
                    (outcome.method.rawValue, outcome.quads.map { $0.corners.map { [Double($0.x), Double($0.y)] } })
                }),
                milliseconds: Dictionary(uniqueKeysWithValues: outcomes.map { ($0.method.rawValue, $0.durationMilliseconds) })
            ))
        }
        return frames
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COURT_DEMO_DIR"] != nil
        && ProcessInfo.processInfo.environment["COURT_QUADS_JSON"] != nil))
func exportsQuadsOnDemoVideos() async throws {
    let environment = ProcessInfo.processInfo.environment
    let directory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    let videos = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "mp4" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var frames = [DemoVideoQuadsExport]()
    for video in videos {
        try await frames += DemoVideoQuadsExport.frames(of: video)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(frames).write(to: URL(fileURLWithPath: environment["COURT_QUADS_JSON"] ?? ""))
}
