import AVFoundation
import Foundation
import SceneAdvisor
import Testing

// 本物の Jev に、動画ごとに 3 枚（長さの 25%、50%、75%）を見せて、選んだ球の色と線の色を出す。
// SCENE_ADVISOR_VIDEOS（動画のパスをコンマ区切り）を指定し、~/.config/racket-vision/jev.key に API キーを置いたときだけ動く。
// 映像の静止画を外部のサービス（TypeSafe AI）に送るので、送ってよい動画だけで動かす。
@Test(.enabled(if: ProcessInfo.processInfo.environment["SCENE_ADVISOR_VIDEOS"] != nil))
func advisesDemoVideos() async throws {
    let advisor = try #require(SceneAdvisor(keyFile: SceneAdvisor.defaultKeyFile))
    let videos = (ProcessInfo.processInfo.environment["SCENE_ADVISOR_VIDEOS"] ?? "").split(separator: ",").map { URL(fileURLWithPath: String($0)) }
    var lines = ["| 動画 | 球の色 | 線の色 | 球の色の重み | 線の色の重み |", "| --- | --- | --- | --- | --- |"]
    for video in videos {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        var summary = SceneAdviceSummary()
        for fraction in [0.25, 0.5, 0.75] {
            let image = try await generator.image(at: CMTime(seconds: duration * fraction, preferredTimescale: 600)).image
            summary.add(try await advisor.advise(on: image))
        }
        func describe(_ weights: [String: Double]) -> String {
            weights.sorted { $0.value > $1.value }.prefix(2).map { String(format: "%@ %.2f", $0.key, $0.value) }.joined(separator: ", ")
        }
        let ball = summary.ballColors().map { colors -> String in
            colors == .yellowGreen ? "yellow_green" : colors == .orange ? "orange" : colors == .pale ? "white" : "?"
        } ?? "（そのまま）"
        lines.append("| \(video.deletingPathExtension().lastPathComponent) | \(ball) | \(summary.lineColor()?.rawValue ?? "（そのまま）") | "
            + "\(describe(summary.ballColorWeights)) | \(describe(summary.lineColorWeights)) |")
    }
    print(lines.joined(separator: "\n"))
}
