@testable import BallTracking

// 動画の一部のフレームについて、球の候補と結果を 1 行ずつ書き出す（原因を調べるため）。
// COURT_DEMO_DIR（動画のフォルダ）、BALL_TRACE_VIDEO（動画の名前の一部）、BALL_TRACE_FROM と BALL_TRACE_TO（秒）を
// 指定したときだけ動く。BALL_TRACE_OUT を指定すると、そのファイルに書く。
import CoreGraphics
import CourtFit
import Foundation
import Testing
import VideoTestSupport

@Test(.enabled(if: ProcessInfo.processInfo.environment["COURT_DEMO_DIR"] != nil
        && ProcessInfo.processInfo.environment["BALL_TRACE_VIDEO"] != nil))
func tracesBallCandidates() async throws {
    let environment = ProcessInfo.processInfo.environment
    let demoDirectory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    let name = environment["BALL_TRACE_VIDEO"] ?? ""
    let from = Double(environment["BALL_TRACE_FROM"] ?? "") ?? 0
    let to = Double(environment["BALL_TRACE_TO"] ?? "") ?? .infinity
    let video = try #require(
        try FileManager.default.contentsOfDirectory(at: demoDirectory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "mp4" && $0.lastPathComponent.contains(name) }
    )
    let reader = try await VideoFrameReader(url: video)
    let gated = MotionColorBallDetector()
    let free = MotionColorBallDetector()
    let courtTracker = TrackingLineModelCourtRectangleDetector(searchInterval: 0)
    var lines = [String]()
    while let frame = reader.next() {
        guard frame.seconds <= to else { break }
        let quad = courtTracker.detect(in: frame.pixelBuffer, orientation: .up).quads.first
        gated.setCourtRegion(quad?.corners)
        let gatedOutcome = gated.detect(in: frame.pixelBuffer, at: frame.seconds)
        let freeOutcome = free.detect(in: frame.pixelBuffer, at: frame.seconds)
        guard frame.seconds >= from else { continue }
        lines.append(traceLine(seconds: frame.seconds, free: freeOutcome, gated: gatedOutcome, quad: quad))
    }
    let text = lines.joined(separator: "\n") + "\n"
    if let out = environment["BALL_TRACE_OUT"] {
        try text.write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
    } else {
        print(text)
    }
}

/// 1 フレームぶんの 1 行。座標は画素（左上が原点）。
private func traceLine(seconds: Double, free: BallFrameOutcome, gated: BallFrameOutcome, quad: DetectedQuad?) -> String {
    let width = Double(free.imageSize.width)
    let height = Double(free.imageSize.height)
    func pixel(_ ball: BallObservation) -> String {
        String(format: "(%.0f,%.0f r%.1f)", Double(ball.center.x) * width, (1 - Double(ball.center.y)) * height, Double(ball.radius) * width)
    }
    let court = quad.map { quad in
        quad.corners.map { String(format: "%.0f,%.0f", Double($0.x) * width, (1 - Double($0.y)) * height) }.joined(separator: " ")
    } ?? "-"
    return String(
        format: "%.3f scene=%@ free=%@ cands=[%@] gated=%@ gatedCands=%ld court=[%@]",
        seconds,
        free.sceneChanged ? "1" : "0",
        free.ball.map(pixel) ?? "-",
        free.candidates.map(pixel).joined(separator: " "),
        gated.ball.map(pixel) ?? "-",
        gated.candidates.count,
        court
    )
}
