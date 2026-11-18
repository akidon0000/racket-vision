// サンプル動画に、選手の検出（骨格、コートにいる選手の特定）をかけ、結果を書き出す。
// COURT_DEMO_DIR（動画のフォルダ）と POSE_REPORT_DIR（書き出す先）を指定したときだけ動く。
// 出力: <動画>.json（フレームごとの選手）、<動画>-<秒>s.jpg（2 秒ごと、骨格つき）、report.md（動画ごとの集計）。
// POSE_VIDEOS（例: 1min-01,1min-04）で動画を絞る。POSE_RATE で、1 秒に何枚かけるかを決める（既定は 10）。
// POSE_RENDER_VIDEO=1 で、骨格を描いた動画 <動画>-pose.mp4 も書く。
// コートの検出は遅いので、POSE_COURT_CACHE（フォルダ）を指定すると、フレームごとの矩形を <動画>-court.json に残し、
// 次からはそれを読む（球の追跡のテストの BALL_COURT_CACHE と同じ形で、同じフォルダを使える）。
import CoreGraphics
import Foundation
import PlayerPose
import Testing
import VideoTestSupport

@Test(.enabled(if: ProcessInfo.processInfo.environment["COURT_DEMO_DIR"] != nil
        && ProcessInfo.processInfo.environment["POSE_REPORT_DIR"] != nil))
func reportsPlayersOnDemoVideos() async throws {
    let environment = ProcessInfo.processInfo.environment
    let demoDirectory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    let reportDirectory = URL(fileURLWithPath: environment["POSE_REPORT_DIR"] ?? "")
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
    let only = environment["POSE_VIDEOS"]?.split(separator: ",").map(String.init)
    let videos = try FileManager.default.contentsOfDirectory(at: demoDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "mp4" }
        .filter { video in only?.contains { video.lastPathComponent.contains($0) } ?? true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var report = "# 選手の検出の結果（サンプル動画）\n\n1 秒に \(environment["POSE_RATE"] ?? "10") 枚ずつかけた結果。"
    report += "当たっているかは画像で確かめる。「追跡の数」は、選手を追い始めた回数（少ないほど、同じ人を追い続けている）。\n\n"
    report += "「見つけた」は、そのフレームで骨格が見つかった選手だけを数える。「出した」は、見つからずに少し前の骨格を出した選手も数える。\n\n"
    report += "| 動画 | 枚数 | コートあり | 選手の数の平均（見つけた） | 4 人（見つけた） | 4 人（出した） | 2 人以上（出した） | 追跡の数 | 平均処理時間（ms） |\n"
    report += "| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n"
    for video in videos {
        report += try await measurePlayers(in: video, reportDirectory: reportDirectory, environment: environment)
    }
    try report.write(to: reportDirectory.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
}

/// 1 本の動画を先頭から流し、画像と JSON（と動画）を書き出す。集計の 1 行を返す。
private func measurePlayers(in video: URL, reportDirectory: URL, environment: [String: String]) async throws -> String {
    let name = video.deletingPathExtension().lastPathComponent
    let reader = try await VideoFrameReader(url: video)
    let interval = 1 / (Double(environment["POSE_RATE"] ?? "") ?? 10)
    // 確認用の画像は、幅 1280px に縮める。H.264 は偶数の大きさだけを受ける。
    let width = 1280
    let height = Int(1280 * reader.size.height / reader.size.width / 2) * 2
    var writer: VideoFrameWriter?
    if environment["POSE_RENDER_VIDEO"] == "1" {
        writer = try VideoFrameWriter(url: reportDirectory.appendingPathComponent("\(name)-pose.mp4"), width: width, height: height)
    }
    let detector = CourtPlayerDetector()
    var court = CourtQuadSource(video: name, cacheDirectory: environment["POSE_COURT_CACHE"])
    var exports = [PlayerFrameExport]()
    var nextSample = 0.0
    var nextPreview = 0.0
    while let frame = reader.next() {
        // コートは、追従の検出なので、全部のフレームにかける。
        let corners = court.next(in: frame.pixelBuffer)
        guard frame.seconds >= nextSample else { continue }
        nextSample = (frame.seconds / interval).rounded(.down) * interval + interval
        detector.setCourt(corners)
        let outcome = detector.detect(in: frame.pixelBuffer, at: frame.seconds)
        exports.append(PlayerFrameExport(video: name, outcome: outcome, courtFound: corners != nil))
        let isPreviewTime = frame.seconds >= nextPreview
        guard writer != nil || isPreviewTime, let image = makeImage(from: frame.pixelBuffer) else { continue }
        guard let preview = renderPosePreview(
            image, items: previewItems(for: outcome), court: corners, width: width, height: height, regions: outcome.regions
        ) else { continue }
        if isPreviewTime {
            nextPreview = (frame.seconds / 2).rounded(.down) * 2 + 2
            try writeJPEG(preview, to: reportDirectory.appendingPathComponent("\(name)-\(String(format: "%05.1f", frame.seconds))s.jpg"))
        }
        try writer?.append(preview, at: frame.seconds)
    }
    await writer?.finish()
    try court.save()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(exports).write(to: reportDirectory.appendingPathComponent("\(name).json"))
    return summaryRow(name: name, exports: exports)
}

/// 描く骨格。選手は番号の色で、選ばなかった人は白い細い線で描く。
private func previewItems(for outcome: CourtPlayersOutcome) -> [PosePreviewItem] {
    let selected = Set(outcome.players.map(\.pose))
    return outcome.poses.filter { !selected.contains($0) }.map { PosePreviewItem(pose: $0, color: nil) }
        + outcome.players.map { PosePreviewItem(pose: $0.pose, color: $0.id, isHeld: !$0.isDetected) }
}

private func summaryRow(name: String, exports: [PlayerFrameExport]) -> String {
    let count = Double(max(1, exports.count))
    let withCourt = Double(exports.filter(\.courtFound).count) / count * 100
    let mean = Double(exports.reduce(0) { $0 + $1.players.filter(\.isDetected).count }) / count
    let fourDetected = Double(exports.filter { $0.players.filter(\.isDetected).count >= 4 }.count) / count * 100
    let four = Double(exports.filter { $0.players.count >= 4 }.count) / count * 100
    let two = Double(exports.filter { $0.players.count >= 2 }.count) / count * 100
    // 追い始めた時刻が違えば、別の追跡。追跡の数が少ないほど、同じ人を追い続けている。
    let births = Set(exports.flatMap { $0.players.map { "\($0.id)@\($0.firstSeen)" } }).count
    let milliseconds = exports.reduce(0) { $0 + $1.milliseconds } / count
    return "| \(name) | \(exports.count) | " + String(
        format: "%.0f%% | %.1f | %.0f%% | %.0f%% | %.0f%% | %ld | %.0f |\n", withCourt, mean, fourDetected, four, two, births, milliseconds
    )
}
