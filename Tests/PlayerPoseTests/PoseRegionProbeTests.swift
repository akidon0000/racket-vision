// 1 枚のフレームの、指定した範囲に骨格の検出をかけて、取れた人の数を書き出す（範囲の取り方を調べるため）。
// COURT_DEMO_DIR、POSE_ROI_VIDEO（動画の名前の一部）、POSE_ROI_SECONDS（秒）、
// POSE_ROIS（「x,y,幅,高さ」を ; で区切る。画素、左上が原点）を指定したときだけ動く。
import CoreGraphics
import Foundation
import PlayerPose
import Testing
import VideoTestSupport

@Test(.enabled(if: ProcessInfo.processInfo.environment["COURT_DEMO_DIR"] != nil
        && ProcessInfo.processInfo.environment["POSE_ROIS"] != nil))
func probesPoseInRegions() async throws {
    let environment = ProcessInfo.processInfo.environment
    let demoDirectory = URL(fileURLWithPath: environment["COURT_DEMO_DIR"] ?? "")
    let name = environment["POSE_ROI_VIDEO"] ?? ""
    let seconds = Double(environment["POSE_ROI_SECONDS"] ?? "") ?? 0
    let video = try #require(
        try FileManager.default.contentsOfDirectory(at: demoDirectory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "mp4" && $0.lastPathComponent.contains(name) }
    )
    let reader = try await VideoFrameReader(url: video)
    while let frame = reader.next() {
        guard frame.seconds >= seconds else { continue }
        let width = Double(reader.size.width)
        let height = Double(reader.size.height)
        for text in (environment["POSE_ROIS"] ?? "").split(separator: ";") {
            let values = text.split(separator: ",").compactMap { Double($0) }
            guard values.count == 4 else { continue }
            // 画素（左上が原点）を、正規化座標（左下が原点）にする。
            let region = CGRect(
                x: values[0] / width, y: 1 - (values[1] + values[3]) / height, width: values[2] / width, height: values[3] / height
            )
            let outcome = VisionBodyPoseDetector(regions: [region], minimumJoints: 1).detect(in: frame.pixelBuffer, at: frame.seconds)
            let joints = outcome.poses.map { "\($0.joints.count)(\(String(format: "%.2f", $0.confidence)))" }.joined(separator: " ")
            print("ROI \(text): \(outcome.poses.count) poses, joints \(joints)")
        }
        break
    }
}
