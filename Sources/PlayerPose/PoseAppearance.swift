import CoreGraphics
import CoreVideo
import simd

/// 選手の見た目（服の色）。同じ選手に同じ番号を付け続けるための手がかりにする。
public struct PoseAppearance: Equatable, Sendable {
    /// 胴（両肩と腰のあいだ）の色の平均（赤・緑・青、0〜1）。取れなければ nil。
    public var torso: SIMD3<Double>?
    /// 腿（腰と膝のあいだ）の色の平均。取れなければ nil。
    public var legs: SIMD3<Double>?

    public init(torso: SIMD3<Double>?, legs: SIMD3<Double>?) {
        self.torso = torso
        self.legs = legs
    }

    /// 2 人の見た目の違い（0 が同じ、1 が白と黒ほどの違い）。比べられる部分が無ければ nil。
    public func distance(to other: PoseAppearance) -> Double? {
        var distances = [Double]()
        if let a = torso, let b = other.torso {
            distances.append(simd_distance(a, b) / 3.0.squareRoot())
        }
        if let a = legs, let b = other.legs {
            distances.append(simd_distance(a, b) / 3.0.squareRoot())
        }
        return distances.isEmpty ? nil : distances.reduce(0, +) / Double(distances.count)
    }

    /// `other` へ、`rate`（0〜1）だけ近づける。片方にしか無い部分は、あるほうを使う。
    func blended(with other: PoseAppearance, rate: Double) -> PoseAppearance {
        func blend(_ a: SIMD3<Double>?, _ b: SIMD3<Double>?) -> SIMD3<Double>? {
            guard let a else { return b }
            guard let b else { return a }
            return a + (b - a) * rate
        }
        return PoseAppearance(torso: blend(torso, other.torso), legs: blend(legs, other.legs))
    }
}

extension PoseAppearance {
    /// 骨格の胴と腿のあたりの画素から、見た目を取る。32BGRA でないとき、関節が足りないときは nil。
    public init?(pose: BodyPose, in pixelBuffer: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        /// 4 点で囲んだ四角形の中を、5×5 の点で拾って平均する。正規化座標（左下が原点）で受ける。
        func mean(_ corners: [CGPoint?]) -> SIMD3<Double>? {
            let points = corners.compactMap { $0 }
            guard points.count == 4 else { return nil }
            var sum = SIMD3<Double>(0, 0, 0)
            var count = 0.0
            for row in 1...5 {
                for column in 1...5 {
                    // 縁は背景が混じるので、内側の点だけを拾う。
                    let u = Double(column) / 6
                    let v = Double(row) / 6
                    let top = SIMD2(Double(points[0].x), Double(points[0].y)) * (1 - u) + SIMD2(Double(points[1].x), Double(points[1].y)) * u
                    let bottom = SIMD2(Double(points[3].x), Double(points[3].y)) * (1 - u) + SIMD2(Double(points[2].x), Double(points[2].y)) * u
                    let point = top * (1 - v) + bottom * v
                    let x = Int(point.x * Double(width))
                    let y = Int((1 - point.y) * Double(height))
                    guard x >= 0, x < width, y >= 0, y < height else { continue }
                    let offset = y * stride + x * 4
                    sum += SIMD3(Double(bytes[offset + 2]), Double(bytes[offset + 1]), Double(bytes[offset])) / 255
                    count += 1
                }
            }
            return count > 0 ? sum / count : nil
        }
        let torso = mean([
            pose.position(of: .leftShoulder), pose.position(of: .rightShoulder),
            pose.position(of: .rightHip), pose.position(of: .leftHip)
        ])
        let legs = mean([
            pose.position(of: .leftHip), pose.position(of: .rightHip),
            pose.position(of: .rightKnee), pose.position(of: .leftKnee)
        ])
        guard torso != nil || legs != nil else { return nil }
        self.init(torso: torso, legs: legs)
    }
}
