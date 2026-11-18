import CoreFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Vision の骨格検出（`VNDetectHumanBodyPoseRequest`）で、人ごとの骨格を求める。
///
/// iOS のシミュレーターでは、この検出は動かない（"Unable to setup request in VNDetectHumanBodyPoseRequest"）。
/// 計算装置を CPU に指定しても、古い版（revision 1）でも、新しい API（`DetectHumanBodyPoseRequest`、
/// "No available compute device"）でも動かなかった。動かなかったときは、結果の `failure` に理由が入る。macOS では動く。
///
/// `regions` を渡すと、その範囲ごとに検出をかけて、結果を合わせる。Vision は映像を小さくしてから見るので、
/// 画面の全体にかけると、小さく写った選手を取りこぼす。範囲を絞ると、その中の人が大きく見える。
public struct VisionBodyPoseDetector: BodyPoseDetector {
    public var method: PoseDetectionMethod { regions.isEmpty ? .vision : .visionTiled }
    /// 検出をかける範囲（正規化座標、左下が原点）。空なら、画面の全体に 1 回かける。
    public var regions: [CGRect]
    /// 関節として残す、確からしさの下限。
    public var minimumJointConfidence: Float
    /// 人として残すのに要る、関節の数。
    public var minimumJoints: Int
    /// 関節が、体の中央から、ほかの関節の何倍より遠ければ、外れた関節とみて外すか。
    public var strayRatio: CGFloat = 3.5

    public init(regions: [CGRect] = [], minimumJointConfidence: Float = 0.1, minimumJoints: Int = 5) {
        self.regions = regions
        self.minimumJointConfidence = minimumJointConfidence
        self.minimumJoints = minimumJoints
    }

    public func detect(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> PoseFrameOutcome {
        let started = CFAbsoluteTimeGetCurrent()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        var poses = [BodyPose]()
        var failure: String?
        for region in regions.isEmpty ? [whole] : regions {
            let clipped = region.intersection(whole)
            guard clipped.width > 0, clipped.height > 0 else { continue }
            let request = VNDetectHumanBodyPoseRequest()
            request.regionOfInterest = clipped
            do {
                try handler.perform([request])
            } catch {
                failure = failure ?? error.localizedDescription
                continue
            }
            poses += (request.results ?? []).compactMap { pose(from: $0, in: clipped) }
        }
        return PoseFrameOutcome(
            method: method,
            time: time,
            poses: PoseDeduplicator().merge(poses),
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000,
            imageSize: CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)),
            failure: failure
        )
    }

    /// Vision の結果を、映像の全体に対する正規化座標の骨格にする。
    private func pose(from observation: VNHumanBodyPoseObservation, in region: CGRect) -> BodyPose? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        var joints = [PoseJoint: PoseKeypoint]()
        for (name, joint) in VisionBodyPoseDetector.jointNames {
            guard let point = points[name], point.confidence >= minimumJointConfidence else { continue }
            // Vision の座標は、範囲の中での 0〜1。
            let position = CGPoint(
                x: region.minX + point.location.x * region.width,
                y: region.minY + point.location.y * region.height
            )
            joints[joint] = PoseKeypoint(position: position, confidence: point.confidence)
        }
        joints = removingStrayJoints(from: joints)
        return joints.count >= minimumJoints ? BodyPose(joints: joints) : nil
    }

    /// 体から大きく外れた関節（別の人や背景に付いた関節）を外す。関節の位置の中央から、中央値の `strayRatio` 倍より遠い関節を外す。
    private func removingStrayJoints(from joints: [PoseJoint: PoseKeypoint]) -> [PoseJoint: PoseKeypoint] {
        guard joints.count >= 4 else { return joints }
        func median(_ values: [CGFloat]) -> CGFloat {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        let center = CGPoint(x: median(joints.values.map(\.position.x)), y: median(joints.values.map(\.position.y)))
        func distance(_ keypoint: PoseKeypoint) -> CGFloat {
            let dx = keypoint.position.x - center.x
            let dy = keypoint.position.y - center.y
            return (dx * dx + dy * dy).squareRoot()
        }
        let typical = median(joints.values.map(distance))
        guard typical > 0 else { return joints }
        return joints.filter { distance($0.value) <= typical * strayRatio }
    }

    private static let jointNames: [(VNHumanBodyPoseObservation.JointName, PoseJoint)] = [
        (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye), (.leftEar, .leftEar), (.rightEar, .rightEar),
        (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.root, .root), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle)
    ]
}
