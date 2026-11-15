@testable import CourtFit

// デモ動画で検出の精度を測る検証。環境変数 COURT_DEMO_DIR（動画のフォルダ）を指定したときだけ動く。
// 出力: COURT_REPORT_DIR（省略時は一時フォルダ）に report.md と、線を描いた PNG を置く。
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Testing

@Test(.enabled(if: ProcessInfo.processInfo.environment["COURT_DEMO_DIR"] != nil))
func reportsDetectionOnDemoVideos() async throws {
    let environment = ProcessInfo.processInfo.environment
    let demoDirectory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    let reportDirectory = URL(fileURLWithPath: environment["COURT_REPORT_DIR"] ?? NSTemporaryDirectory())
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

    let videos = try FileManager.default.contentsOfDirectory(at: demoDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "mp4" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var report = "# 検出の結果（デモ動画）\n\n2 秒ごとにフレームを取り、四角形を検出した割合と処理時間を見る。\n\n"
    report += "| 方式 | 動画 | フレーム数 | 検出 | 検出率 | 平均処理時間（ms） |\n| --- | --- | --- | --- | --- | --- |\n"
    for detector in detectorsToCompare() {
        for video in videos {
            report += try await measure(detector, video: video, reportDirectory: reportDirectory)
        }
    }
    try report.write(to: reportDirectory.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
}

/// 比べる方式。
/// COURT_METHODS（例: lineModel,lineModelTracking）を指定したときは、その方式だけにする。
func detectorsToCompare() -> [any CourtRectangleDetector] {
    let only = ProcessInfo.processInfo.environment["COURT_METHODS"]?.split(separator: ",").map(String.init)
    return allDetectors().filter { only == nil || only?.contains($0.method.rawValue) == true }
}

private func allDetectors() -> [any CourtRectangleDetector] {
    [
        VisionCourtRectangleDetector(), LineSearchCourtRectangleDetector(),
        LineModelCourtRectangleDetector(), LineModelCourtRectangleDetector(polishes: true),
        TrackingLineModelCourtRectangleDetector(searchInterval: 0)
    ]
}

/// 1 本の動画を、2 秒ごとに検出して、表の行を返す。線を描いた PNG も保存する。
private func measure(_ detector: any CourtRectangleDetector, video: URL, reportDirectory: URL) async throws -> String {
    let asset = AVURLAsset(url: video)
    let duration = try await asset.load(.duration).seconds
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    let name = video.deletingPathExtension().lastPathComponent
    let prefix = "\(detector.method.rawValue)-\(name)"
    var frames = 0
    var detected = 0
    var milliseconds = [Double]()
    var seconds = 1.0
    while seconds < duration {
        // シミュレータでは、まれに特定の時刻のフレームが取り出せない。その時刻は数えずに飛ばす。
        guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil) else {
            seconds += 2.0
            continue
        }
        let buffer = try makePixelBuffer(from: cgImage)
        let outcome = detector.detect(in: buffer, orientation: .up)
        frames += 1
        milliseconds.append(outcome.durationMilliseconds)
        if outcome.quads.isEmpty {
            try savePreview(cgImage, quads: [], to: reportDirectory.appendingPathComponent("\(prefix)-\(Int(seconds))s-miss.png"))
        } else {
            detected += 1
            try savePreview(cgImage, quads: outcome.quads, to: reportDirectory.appendingPathComponent("\(prefix)-\(Int(seconds))s.png"))
        }
        seconds += 2.0
    }
    let rate = frames == 0 ? 0 : Double(detected) / Double(frames) * 100
    let mean = milliseconds.isEmpty ? 0 : milliseconds.reduce(0, +) / Double(milliseconds.count)
    return "| \(detector.method.label) | \(name) | \(frames) | \(detected) | \(String(format: "%.0f", rate))% | \(String(format: "%.1f", mean)) |\n"
}

func makePixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
    )
    guard status == kCVReturnSuccess, let buffer else {
        throw CocoaError(.fileWriteUnknown)
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buffer
}

/// フレームに、検出した四角形を緑の線で描いて PNG にする（確認用）。
private func savePreview(_ image: CGImage, quads: [DetectedQuad], to url: URL) throws {
    let width = image.width
    let height = image.height
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    context.setStrokeColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.setLineWidth(max(4, CGFloat(width) / 240))
    for quad in quads {
        // 検出の座標は左下が原点。画像の描画は左下が原点なので、そのまま使える。
        let points = quad.corners.map { CGPoint(x: $0.x * CGFloat(width), y: $0.y * CGFloat(height)) }
        context.move(to: points[0])
        points.dropFirst().forEach { context.addLine(to: $0) }
        context.closePath()
        context.strokePath()
    }
    guard let output = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}
