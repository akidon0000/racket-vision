@testable import BallTracking

// 球の検出の点が、同じ時刻のコートの矩形の内側にあるかを数える（検証用）。
// COURT_DEMO_DIR（動画）、BALL_JSON_DIR（球の検出の JSON）、BALL_REPORT_DIR（書き出す先）を指定したときだけ動く。
// BALL_AUDIT_INDEX（目視の 48 件の index.json）を指定すると、その時刻も調べる。
// 0.5 秒ごとの時刻と、監査の時刻の、球の検出のある点だけ、コートの矩形を 1 枚ずつ求める（追従なし）。
import CoreGraphics
import CoreVideo
import CourtFit
import Foundation
import ImageIO
import Testing
import VideoTestSupport

/// 球の検出 1 件と、同じ時刻のコートの矩形との関係。
struct BallCourtRow: Encodable {
    var video: String
    var seconds: Double
    var ball: [Double]
    /// コートの矩形が見つかったか。
    var courtFound: Bool
    /// コートの内側なら正、外側なら負（正規化座標で、いちばん近い辺までの距離）。矩形が無ければ nil。
    var margin: Double?
    /// 監査（目視）の番号。監査の時刻でなければ nil。
    var auditIndex: Int?
}

/// 球の検出の JSON（`BallFrameExport`）の、読むところだけ。
private struct BallExportRow: Decodable {
    var seconds: Double
    var ball: [Double]?
}

/// 監査の 48 件（`audit/index.json`）の、読むところだけ。
private struct AuditRow: Decodable {
    var idx: Int
    var video: String
    var seconds: Double
}

/// 点が四角形の内側なら正、外側なら負。正規化座標で、いちばん近い辺までの距離（凸な四角形を想定）。
private func margin(of point: [Double], in quad: DetectedQuad) -> Double {
    let corners = quad.corners.map { SIMD2(Double($0.x), Double($0.y)) }
    let p = SIMD2(point[0], point[1])
    var area2 = 0.0
    for i in 0..<4 {
        let a = corners[i]
        let b = corners[(i + 1) % 4]
        area2 += a.x * b.y - b.x * a.y
    }
    let orientation: Double = area2 >= 0 ? 1 : -1
    var best = Double.infinity
    for i in 0..<4 {
        let a = corners[i]
        let b = corners[(i + 1) % 4]
        let edge = b - a
        let length = (edge.x * edge.x + edge.y * edge.y).squareRoot()
        let cross = edge.x * (p.y - a.y) - edge.y * (p.x - a.x)
        best = min(best, orientation * cross / length)
    }
    return best
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COURT_DEMO_DIR"] != nil
        && ProcessInfo.processInfo.environment["BALL_JSON_DIR"] != nil
        && ProcessInfo.processInfo.environment["BALL_REPORT_DIR"] != nil))
func measuresBallCourtOverlapOnDemoVideos() async throws {
    let environment = ProcessInfo.processInfo.environment
    let demoDirectory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    let jsonDirectory = URL(fileURLWithPath: environment["BALL_JSON_DIR"] ?? "")
    let reportDirectory = URL(fileURLWithPath: environment["BALL_REPORT_DIR"] ?? "")
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
    var audit = [AuditRow]()
    if let path = environment["BALL_AUDIT_INDEX"] {
        audit = try JSONDecoder().decode([AuditRow].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }
    let videos = try FileManager.default.contentsOfDirectory(at: demoDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "mp4" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var rows = [BallCourtRow]()
    for video in videos {
        let name = video.deletingPathExtension().lastPathComponent
        let jsonURL = jsonDirectory.appendingPathComponent("\(name).json")
        let balls = try JSONDecoder().decode([BallExportRow].self, from: Data(contentsOf: jsonURL))
        var ballAt = [Double: [Double]]()
        for row in balls {
            if let ball = row.ball {
                ballAt[row.seconds] = ball
            }
        }
        let auditAt = audit.filter { $0.video == name }
        let reader = try await VideoFrameReader(url: video)
        let detector = LineModelCourtRectangleDetector()
        var lastGrid = -1
        while let frame = reader.next() {
            guard let ball = ballAt[frame.seconds] else { continue }
            let grid = Int((frame.seconds * 2).rounded())
            let onGrid = abs(frame.seconds - Double(grid) / 2) < 0.009 && grid != lastGrid
            let auditIndex = auditAt.first { abs($0.seconds - frame.seconds) < 0.0005 }?.idx
            guard onGrid || auditIndex != nil else { continue }
            if onGrid {
                lastGrid = grid
            }
            let outcome = detector.detect(in: frame.pixelBuffer, orientation: .up)
            let quad = outcome.quads.first
            rows.append(BallCourtRow(
                video: name,
                seconds: frame.seconds,
                ball: ball,
                courtFound: quad != nil,
                margin: quad.map { margin(of: ball, in: $0) },
                auditIndex: auditIndex
            ))
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(rows).write(to: reportDirectory.appendingPathComponent("ball_court.json"))
}
