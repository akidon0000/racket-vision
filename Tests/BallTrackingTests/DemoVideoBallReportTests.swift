@testable import BallTracking

// サンプル動画の全フレームに球の追跡をかけ、結果を書き出す。COURT_DEMO_DIR（動画のフォルダ）と BALL_REPORT_DIR（書き出す先）を
// 指定したときだけ動く。
// 出力: <動画>.json（フレームごとの球の位置）、<動画>-<秒>s.jpg（0.5 秒ごと、軌跡の点つき）、report.md（動画ごとの集計）。
// BALL_VIDEOS（例: 1min-01,1min-04）で動画を絞る。BALL_RENDER_VIDEO=1 で、点を描いた動画 <動画>-ball.mp4 も書く。
// BALL_COURT=1 で、アプリと同じ追従のコートの検出で、球を探す範囲を決める。コートの検出は遅いので、
// BALL_COURT_CACHE（フォルダ）を指定すると、フレームごとの矩形を <動画>-court.json に残し、次からはそれを読む。
// BALL_COLOR（yellow_green、orange、white）で、球の色（`BallColorSet`）を変える。
import CoreGraphics
import CourtFit
import Foundation
import Testing
import VideoTestSupport

@Test(.enabled(if: ProcessInfo.processInfo.environment["COURT_DEMO_DIR"] != nil
        && ProcessInfo.processInfo.environment["BALL_REPORT_DIR"] != nil))
func reportsBallsOnDemoVideos() async throws {
    let environment = ProcessInfo.processInfo.environment
    let demoDirectory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    let reportDirectory = URL(fileURLWithPath: environment["BALL_REPORT_DIR"] ?? "")
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
    let only = environment["BALL_VIDEOS"]?.split(separator: ",").map(String.init)
    let videos = try FileManager.default.contentsOfDirectory(at: demoDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "mp4" }
        .filter { video in only?.contains { video.lastPathComponent.contains($0) } ?? true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var report = "# 球の追跡の結果（サンプル動画）\n\n全フレームを流した結果。「球あり」は球を出したフレームの数で、当たっているかは画像で確かめる。\n\n"
    report += "| 動画 | 大きさ | コマ/秒 | フレーム | 球あり | 割合 | ラリー | 平均処理時間（ms） |\n"
    report += "| --- | --- | --- | --- | --- | --- | --- | --- |\n"
    for video in videos {
        report += try await measureBalls(in: video, reportDirectory: reportDirectory, rendersVideo: environment["BALL_RENDER_VIDEO"] == "1")
    }
    try report.write(to: reportDirectory.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
}

/// 1 本の動画を先頭から流し、画像と JSON（と動画）を書き出す。集計の 1 行を返す。
private func measureBalls(in video: URL, reportDirectory: URL, rendersVideo: Bool) async throws -> String {
    let name = video.deletingPathExtension().lastPathComponent
    let reader = try await VideoFrameReader(url: video)
    // 確認用の画像は、幅 960px に縮める。H.264 は偶数の大きさだけを受ける。
    let width = 960
    let height = Int(960 * reader.size.height / reader.size.width / 2) * 2
    var writer: VideoFrameWriter?
    if rendersVideo {
        writer = try VideoFrameWriter(url: reportDirectory.appendingPathComponent("\(name)-ball.mp4"), width: width, height: height)
    }
    // BALL_COLOR（yellow_green、orange、white）で球の色を変える。
    let detector = MotionColorBallDetector(
        colors: ProcessInfo.processInfo.environment["BALL_COLOR"].flatMap(BallColorSet.init(name:)) ?? .yellowGreen
    )
    let usesCourt = ProcessInfo.processInfo.environment["BALL_COURT"] == "1"
    var court = CourtQuadSource(video: name, cacheDirectory: ProcessInfo.processInfo.environment["BALL_COURT_CACHE"])
    var rally = BallRallyTrajectory()
    var exports = [BallFrameExport]()
    var nextPreview = 0.0
    while let frame = reader.next() {
        if usesCourt {
            // 矩形が見つからないフレームは、範囲で絞らない（nil）。
            detector.setCourtRegion(court.next(in: frame.pixelBuffer))
        }
        let outcome = detector.detect(in: frame.pixelBuffer, at: frame.seconds)
        rally.append(outcome)
        exports.append(BallFrameExport(video: name, outcome: outcome, rally: rally.rallyIndex))
        let isPreviewTime = frame.seconds >= nextPreview
        guard writer != nil || isPreviewTime, let image = makeImage(from: frame.pixelBuffer),
              let preview = renderBallPreview(image, outcome: outcome, rally: rally, width: width, height: height) else { continue }
        if isPreviewTime {
            nextPreview = (frame.seconds * 2).rounded(.down) / 2 + 0.5
            let seconds = String(format: "%05.1f", frame.seconds)
            try writeJPEG(preview, to: reportDirectory.appendingPathComponent("\(name)-\(seconds)s.jpg"))
        }
        try writer?.append(preview, at: frame.seconds)
    }
    await writer?.finish()
    try court.save()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(exports).write(to: reportDirectory.appendingPathComponent("\(name).json"))
    return summaryRow(name: name, reader: reader, exports: exports)
}

private func summaryRow(name: String, reader: VideoFrameReader, exports: [BallFrameExport]) -> String {
    let found = exports.filter { $0.ball != nil }
    let ratio = exports.isEmpty ? 0 : Double(found.count) / Double(exports.count) * 100
    let rallies = Set(found.map(\.rally)).count
    let milliseconds = exports.isEmpty ? 0 : exports.reduce(0) { $0 + $1.milliseconds } / Double(exports.count)
    let size = "\(Int(reader.size.width))×\(Int(reader.size.height))"
    let rate = String(format: "%.0f", reader.frameRate)
    return "| \(name) | \(size) | \(rate) | \(exports.count) | \(found.count) | "
        + String(format: "%.0f%% | %ld | %.1f |\n", ratio, rallies, milliseconds)
}
