@testable import CourtFit

// 拾う線の色（`CourtLineColor`）ごとに、アプリと同じ追従のコートの検出を動画の全フレームにかけ、枠を出したフレームの数を比べる。
// COURT_LINE_VIDEOS（動画のパスをコンマ区切り）と COURT_LINE_REPORT_DIR（書き出す先）を指定したときだけ動く。
// 出力: report.md（動画と色ごとの、枠を出したフレームの数）、<動画>-<色>-<秒>s.jpg（2 秒ごと、枠を描いた画像）。
import CoreGraphics
import Foundation
import ImageIO
import Testing
import VideoTestSupport

private let environment = ProcessInfo.processInfo.environment

@Test(.enabled(if: environment["COURT_LINE_VIDEOS"] != nil && environment["COURT_LINE_REPORT_DIR"] != nil))
func reportsCourtsByLineColor() async throws {
    let output = URL(fileURLWithPath: environment["COURT_LINE_REPORT_DIR"] ?? "")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let videos = (environment["COURT_LINE_VIDEOS"] ?? "").split(separator: ",").map { URL(fileURLWithPath: String($0)) }
    var report = "| 動画 | 線の色 | フレーム | 枠あり | 割合 | 平均処理時間（ms） |\n| --- | --- | --- | --- | --- | --- |\n"
    for video in videos {
        let name = video.deletingPathExtension().lastPathComponent
        for color in CourtLineColor.allCases {
            let reader = try await VideoFrameReader(url: video)
            let tracker = TrackingLineModelCourtRectangleDetector(searchInterval: 0, lineColor: color)
            var frames = 0
            var found = 0
            var milliseconds = 0.0
            var nextPreview = 0.0
            while let frame = reader.next() {
                let outcome = tracker.detect(in: frame.pixelBuffer, orientation: .up)
                frames += 1
                milliseconds += outcome.durationMilliseconds
                let quad = outcome.quads.first
                if quad != nil {
                    found += 1
                }
                if frame.seconds >= nextPreview {
                    nextPreview += 2
                    if let image = makeImage(from: frame.pixelBuffer) {
                        try writeJPEG(drawn(image, quad: quad?.corners), to: output.appendingPathComponent(
                            String(format: "%@-%@-%05.1fs.jpg", name, color.rawValue, frame.seconds)
                        ))
                    }
                }
            }
            report += String(
                format: "| %@ | %@ | %ld | %ld | %.0f%% | %.1f |\n",
                name, color.rawValue, frames, found, 100 * Double(found) / Double(max(1, frames)), milliseconds / Double(max(1, frames))
            )
        }
    }
    try report.write(to: output.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    print(report)
}

// COURT_LINE_RIDGE_FRAME（JPEG のパス）と COURT_LINE_REPORT_DIR を指定すると、色ごとに、まっすぐな線の芯（白）と
// 探索に使う直線の数を書き出す（線の色の拾い方を確かめるため）。
@Test(.enabled(if: environment["COURT_LINE_RIDGE_FRAME"] != nil && environment["COURT_LINE_REPORT_DIR"] != nil))
func writesRidgeByLineColor() throws {
    let url = URL(fileURLWithPath: environment["COURT_LINE_RIDGE_FRAME"] ?? "")
    let output = URL(fileURLWithPath: environment["COURT_LINE_REPORT_DIR"] ?? "")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let buffer = try makePixelBuffer(from: image)
    let search = CourtLineModelSearch()
    for color in CourtLineColor.allCases {
        let ridge = try #require(EdgeMap(ridgeOf: buffer, lineColor: color))
        let straight = search.straightRidge(ridge) ?? ridge
        let context = try #require(CGContext(
            data: nil, width: straight.width, height: straight.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: straight.width, height: straight.height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        for y in 0..<straight.height {
            for x in 0..<straight.width where straight.values[y * straight.width + x] >= 0.3 {
                context.fill(CGRect(x: x, y: straight.height - 1 - y, width: 1, height: 1))
            }
        }
        try writeJPEG(try #require(context.makeImage()), to: output.appendingPathComponent("ridge-\(color.rawValue).jpg"))
        print("RIDGE \(color.rawValue) lines=\(search.candidateLines(ridge).count) fit=\(search.search(ridge).map { String(format: "%.2f", $0.support) } ?? "-")")
    }
}

/// 枠（正規化座標、左下が原点）を赤で描いた画像。
private func drawn(_ image: CGImage, quad: [CGPoint]?) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let size = CGSize(width: image.width, height: image.height)
    context.draw(image, in: CGRect(origin: .zero, size: size))
    if let quad, quad.count == 4 {
        let points = quad.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        context.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1))
        context.setLineWidth(max(3, size.width / 300))
        context.addLines(between: points + [points[0]])
        context.strokePath()
    }
    return try #require(context.makeImage())
}
