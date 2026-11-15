@testable import CourtFit

// 「線の対応」の途中の結果を、画像で確かめる。COURT_DEMO_DIR と COURT_PREVIEW_DIR を指定したときだけ動く。
// 正解のあるフレームごとに、白線の芯（白）、探索に使う直線（黄）、当てはめた図面（赤）を描いた JPEG を置く。
// COURT_PREVIEW_FRAMES（例: short-03:9,short-04:5。動画の名前の末尾と秒）を指定したときは、そのフレームだけを描く。
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import simd
import Testing

private let environment = ProcessInfo.processInfo.environment

@Test(.enabled(if: environment["COURT_DEMO_DIR"] != nil && environment["COURT_PREVIEW_DIR"] != nil))
func previewsLineModelSearch() async throws {
    let output = URL(fileURLWithPath: environment["COURT_PREVIEW_DIR"] ?? "")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let directory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    let videos = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "mp4" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let search = CourtLineModelSearch()
    for (video, seconds) in try previewFrames(videos) {
        do {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            let ridge = try #require(EdgeMap(whiteRidgeOf: makePixelBuffer(from: image)))
            let started = Date()
            let fit = search.search(ridge)
            let elapsed = Date().timeIntervalSince(started)
            let name = "\(video.deletingPathExtension().lastPathComponent)-\(Int(seconds))s"
            print("PREVIEW \(name) support \(fit.map { String(format: "%.2f", $0.support) } ?? "-") \(String(format: "%.2f", elapsed))s")
            try savePreview(search.straightRidge(ridge) ?? ridge, lines: search.candidateLines(ridge), fit: fit, to: output.appendingPathComponent("\(name).jpg"))
        }
    }
}

private func savePreview(
    _ ridge: EdgeMap,
    lines: [(normal: SIMD2<Double>, offset: Double)],
    fit: CourtFit?,
    to url: URL
) throws {
    let width = ridge.width
    let height = ridge.height
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    // 画素の座標（左上が原点）で描けるように、上下を返す。
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    for y in 0..<height {
        for x in 0..<width where ridge.values[y * width + x] >= 0.3 {
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    context.setLineWidth(1)
    context.setStrokeColor(CGColor(red: 1, green: 0.9, blue: 0, alpha: 0.7))
    for line in lines {
        let point = line.normal * line.offset
        let direction = SIMD2(-line.normal.y, line.normal.x)
        let start = point - direction * 3000
        let end = point + direction * 3000
        context.move(to: CGPoint(x: start.x, y: start.y))
        context.addLine(to: CGPoint(x: end.x, y: end.y))
    }
    context.strokePath()
    if let fit {
        drawCourt(fit, in: context)
    }
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

/// 描くフレーム（動画と秒）。COURT_PREVIEW_FRAMES が無ければ、正解のあるフレーム。
private func previewFrames(_ videos: [URL]) throws -> [(URL, Double)] {
    if let list = environment["COURT_PREVIEW_FRAMES"] {
        return list.split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":")
            guard parts.count == 2, let seconds = Double(parts[1]),
                  let video = videos.first(where: { $0.deletingPathExtension().lastPathComponent.hasSuffix(String(parts[0])) }) else { return nil }
            return (video, seconds)
        }
    }
    return try videos.flatMap { video in
        try (CourtAnnotation.load(forVideo: video)?.frames ?? []).map { (video, $0.seconds) }
    }
}

/// 当てはめた図面の線 8 本を、赤で描く。
private func drawCourt(_ fit: CourtFit, in context: CGContext) {
    context.setLineWidth(2)
    context.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1))
    for line in CourtModel.lines {
        guard let start = fit.homography.project(CourtModel.pickleball.position(of: line.start)),
              let end = fit.homography.project(CourtModel.pickleball.position(of: line.end)) else { continue }
        context.move(to: CGPoint(x: start.x, y: start.y))
        context.addLine(to: CGPoint(x: end.x, y: end.y))
    }
    context.strokePath()
}
