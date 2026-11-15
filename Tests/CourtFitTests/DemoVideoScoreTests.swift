@testable import CourtFit

// デモ動画で、検出の正しさを採点する検証。環境変数 COURT_DEMO_DIR（動画のフォルダ）を指定したときだけ動く。
// 正解は Tests/CourtAnnotations/ の JSON。正解の無い動画は飛ばす。
// 出力: COURT_REPORT_DIR（省略時は一時フォルダ）に score.md を置く。
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import simd
import Testing

private let environment = ProcessInfo.processInfo.environment

private func demoVideos() throws -> [URL] {
    let directory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "mp4" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func frame(of video: URL, at seconds: Double) async throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
}

private func centimeters(_ meters: Double) -> String {
    String(format: "%.1f", meters * 100)
}

/// 正解を付けるためのフレームを、PNG で書き出す。COURT_FRAMES_DIR を指定したときだけ動く。
/// 各動画の 1 秒、21 秒、41 秒のフレームを `<動画の名前>-<秒>s.png` で置く。
@Test(.enabled(if: environment["COURT_DEMO_DIR"] != nil && environment["COURT_FRAMES_DIR"] != nil))
func exportsFramesForAnnotation() async throws {
    let output = URL(fileURLWithPath: environment["COURT_FRAMES_DIR"] ?? "")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for video in try demoVideos() {
        let duration = try await AVURLAsset(url: video).load(.duration).seconds
        for seconds in [1.0, 21.0, 41.0] where seconds < duration {
            let image = try await frame(of: video, at: seconds)
            let name = "\(video.deletingPathExtension().lastPathComponent)-\(Int(seconds))s.png"
            let destination = try #require(
                CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil)
            )
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }
}

/// 正解のあるフレームで、方式ごとに、交点のずれを測る。
@Test(.enabled(if: environment["COURT_DEMO_DIR"] != nil))
func reportsScoreOnDemoVideos() async throws {
    let reportDirectory = URL(fileURLWithPath: environment["COURT_REPORT_DIR"] ?? NSTemporaryDirectory())
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

    var report = "# 検出の採点（デモ動画）\n\n"
    report += "正解のある交点で、図面から写した位置とのずれを測る。合格は、すべての交点がコートの面で 5cm 以内。\n"
    report += "「注釈」の行は、正解の交点そのものに図面を当てはめた結果（正解の付け方と、コートの寸法の確かめ）。\n\n"
    report += "| 方式 | 動画 | 秒 | 最大のずれ（cm） | 平均のずれ（cm） | 最大のずれ（px） | カメラとしてありえるか | 合格 |\n"
    report += "| --- | --- | --- | --- | --- | --- | --- | --- |\n"

    for video in try demoVideos() {
        guard let annotation = try CourtAnnotation.load(forVideo: video) else { continue }
        let name = video.deletingPathExtension().lastPathComponent
        for annotated in annotation.frames {
            let truth = annotated.keypoints
            let image = try await frame(of: video, at: annotated.seconds)
            // 正解を付けたときと、フレームの大きさが違うと、座標が合わない。
            #expect(image.width == annotation.imageWidth && image.height == annotation.imageHeight)
            let imageSize = CGSize(width: image.width, height: image.height)
            let prefix = "\(name) | \(Int(annotated.seconds))"

            report += row("注釈", prefix, fitted(to: truth), truth: truth, imageSize: imageSize)
            let buffer = try makePixelBuffer(from: image)
            for detector in detectorsToCompare() {
                let outcome = detector.detect(in: buffer, orientation: .up)
                let best = bestTransform(for: outcome.quads, truth: truth, imageSize: imageSize)
                report += row(detector.method.label, prefix, best, truth: truth, imageSize: imageSize)
            }
        }
    }
    try report.write(to: reportDirectory.appendingPathComponent("score.md"), atomically: true, encoding: .utf8)
}

/// 正解の交点に、図面を最小二乗で当てはめた変換。
private func fitted(to truth: [CourtKeypoint: SIMD2<Double>]) -> Homography? {
    let keypoints = Array(truth.keys)
    return Homography(
        from: keypoints.map { CourtModel.pickleball.position(of: $0) },
        to: keypoints.compactMap { truth[$0] }
    )
}

/// 検出した四角形のうち、正解にいちばん近い変換。四角形の向き（どの辺がベースラインか）は、両方を試す。
private func bestTransform(for quads: [DetectedQuad], truth: [CourtKeypoint: SIMD2<Double>], imageSize: CGSize) -> Homography? {
    var best: (homography: Homography, error: Double)?
    for quad in quads {
        for quarterTurned in [false, true] {
            guard let homography = Homography(courtOutline: quad, imageSize: imageSize, quarterTurned: quarterTurned),
                  let score = CourtScore(estimated: homography, truth: truth) else { continue }
            if best == nil || score.maximumCourtError < (best?.error ?? .infinity) {
                best = (homography, score.maximumCourtError)
            }
        }
    }
    return best?.homography
}

private func row(
    _ method: String,
    _ prefix: String,
    _ homography: Homography?,
    truth: [CourtKeypoint: SIMD2<Double>],
    imageSize: CGSize
) -> String {
    guard let homography, let score = CourtScore(estimated: homography, truth: truth) else {
        return "| \(method) | \(prefix) | 検出なし | - | - | - | - |\n"
    }
    let plausible = CameraEstimate(homography: homography, imageSize: imageSize)
        .map { CameraPlausibility().accepts($0, imageSize: imageSize) } ?? false
    let cells = [
        centimeters(score.maximumCourtError),
        centimeters(score.meanCourtError),
        String(format: "%.1f", score.maximumImageError),
        plausible ? "はい" : "いいえ",
        score.passes() ? "合格" : "不合格"
    ]
    return "| \(method) | \(prefix) | \(cells.joined(separator: " | ")) |\n"
}

/// 画面に出る「1 件目」（面積の大きい順の先頭）だけを、正解と比べる。フィルタの前と後を、同じフレームで比べる。
/// 既存の採点（検出した中で一番いいもの）と違い、実際に画面に出る結果の正しさを測る。
@Test(.enabled(if: environment["COURT_DEMO_DIR"] != nil))
func reportsOutputScoreOnDemoVideos() async throws {
    let reportDirectory = URL(fileURLWithPath: environment["COURT_REPORT_DIR"] ?? NSTemporaryDirectory())
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

    var report = "# 画面に出る 1 件目の採点（デモ動画）\n\n"
    report += "アプリが画面に出すのは、面積の大きい順の 1 件目だけ。その 1 件目を正解と比べる。\n"
    report += "「フィルタ前」は検出のそのまま。「カメラ範囲のみ」は、カメラとしてありえる写り方だけを残す。「カメラ範囲+白線」は、さらに白線の支持率で残す（`keepingPlausibleQuads(edges:)`）。\n\n"
    report += "| 方式 | 動画 | 秒 | 最大のずれ（cm） | 平均のずれ（cm） | 最大のずれ（px） | カメラとしてありえるか | 合格 |\n"
    report += "| --- | --- | --- | --- | --- | --- | --- | --- |\n"

    for video in try demoVideos() {
        guard let annotation = try CourtAnnotation.load(forVideo: video) else { continue }
        let name = video.deletingPathExtension().lastPathComponent
        for annotated in annotation.frames {
            let truth = annotated.keypoints
            let image = try await frame(of: video, at: annotated.seconds)
            let imageSize = CGSize(width: image.width, height: image.height)
            let prefix = "\(name) | \(Int(annotated.seconds))"
            let buffer = try makePixelBuffer(from: image)
            for detector in detectorsToCompare() {
                let outcome = detector.detect(in: buffer, orientation: .up)
                let edges = EdgeMap(bgraPixelBuffer: buffer)
                let stages = [
                    ("フィルタ前", outcome),
                    ("カメラ範囲のみ", outcome.keepingPlausibleQuads()),
                    ("カメラ範囲+白線", outcome.keepingPlausibleQuads(edges: edges))
                ]
                for (stage, kept) in stages {
                    let first = Array(kept.quads.prefix(1))
                    let best = bestTransform(for: first, truth: truth, imageSize: imageSize)
                    report += row("\(detector.method.label) \(stage)", prefix, best, truth: truth, imageSize: imageSize)
                }
            }
        }
    }
    try report.write(to: reportDirectory.appendingPathComponent("output-score.md"), atomically: true, encoding: .utf8)
}
