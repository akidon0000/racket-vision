@testable import CourtFit
import Foundation
import simd

/// デモ動画 1 本ぶんの正解。人が、フレームの上で交点の位置を指定して作る（`tools/court-annotator/index.html`）。
/// ファイルは `Tests/CourtAnnotations/<動画の名前（拡張子なし）>.json` に置く。
struct CourtAnnotation: Codable {
    /// 1 フレームぶんの正解。
    struct Frame: Codable {
        /// 動画の先頭からの秒。
        var seconds: Double
        /// 交点の名前（`CourtKeypoint` の rawValue）から、画面の位置 [x, y]（ピクセル、左上が原点）。見えない交点は入れない。
        var points: [String: [Double]]

        /// 交点ごとの位置。名前が違うもの、座標が 2 つでないものは捨てる。
        var keypoints: [CourtKeypoint: SIMD2<Double>] {
            var result = [CourtKeypoint: SIMD2<Double>]()
            for (name, value) in points {
                guard let keypoint = CourtKeypoint(rawValue: name), value.count == 2 else { continue }
                result[keypoint] = SIMD2(value[0], value[1])
            }
            return result
        }
    }

    /// 動画のファイル名。
    var video: String
    /// 正解を付けたフレームの大きさ（ピクセル）。
    var imageWidth: Int
    var imageHeight: Int
    var frames: [Frame]

    /// 正解の置き場所（`mobile/ios/Library/Tests/CourtAnnotations/`）。
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("CourtAnnotations")

    /// 動画に対応する正解を読む。ファイルが無ければ nil。
    static func load(forVideo video: URL) throws -> CourtAnnotation? {
        let file = directory.appendingPathComponent(video.deletingPathExtension().lastPathComponent + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(CourtAnnotation.self, from: Data(contentsOf: file))
    }
}
