import CoreGraphics
import CoreVideo
import CourtFit
import Foundation

/// フレームごとのコートの矩形（四隅）を、順に返す。
///
/// アプリと同じ追従の検出で求める。検出は遅いので、`cacheDirectory` を渡すと、求めた矩形を `<動画>-court.json` に残し、
/// 次からはそれを読む（球の検出だけを直して測り直すときに使う）。
public struct CourtQuadSource {
    private let tracker = TrackingLineModelCourtRectangleDetector(searchInterval: 0)
    private let cacheFile: URL?
    /// フレームごとの四隅（x, y を 4 つ並べた 8 個の数）。矩形が無いフレームは nil。
    private var quads: [[Double]?]
    private let isCached: Bool
    private var index = 0

    public init(video: String, cacheDirectory: String?) {
        cacheFile = cacheDirectory.map { URL(fileURLWithPath: $0).appendingPathComponent("\(video)-court.json") }
        if let cacheFile, let data = try? Data(contentsOf: cacheFile),
           let cached = try? JSONDecoder().decode([[Double]?].self, from: data) {
            quads = cached
            isCached = true
        } else {
            quads = []
            isCached = false
        }
    }

    /// 次のフレームの四隅（左上、右上、右下、左下の順）。矩形が無ければ nil。フレームは先頭から順に渡す。
    public mutating func next(in pixelBuffer: CVPixelBuffer) -> [CGPoint]? {
        defer { index += 1 }
        if isCached {
            guard index < quads.count, let values = quads[index] else { return nil }
            return stride(from: 0, to: values.count, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) }
        }
        let corners = tracker.detect(in: pixelBuffer, orientation: .up).quads.first?.corners
        quads.append(corners.map { $0.flatMap { [Double($0.x), Double($0.y)] } })
        return corners
    }

    /// 求めた矩形を残す（読んだものを使ったときは、何もしない）。
    public func save() throws {
        guard let cacheFile, !isCached else { return }
        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(quads).write(to: cacheFile)
    }
}
