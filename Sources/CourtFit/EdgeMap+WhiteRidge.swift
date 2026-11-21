import CoreVideo

/// 白さの差が、この値（0〜255）以上なら、白線の芯の強さを 1 にする。
private let ridgeFullContrast: Float = 50
/// 線の両側を見る距離（縮めた後の画素）。細い線と太い線の両方を拾うため、2 つ使う。
private let ridgeOffsets = [2, 5]

/// コートの線の色。体育館では、別の競技の線（白、黄、緑など）と同じ床に引かれるので、ピックルボールの線の色だけを拾う。
public enum CourtLineColor: String, CaseIterable, Sendable {
    /// 白（赤・緑・青の一番小さい値で測る）。
    case white
    /// 黄（赤と緑の小さいほうから、青を引いた値で測る。白や灰色の床は小さくなる）。
    case yellow
}

public extension EdgeMap {
    /// 32BGRA の画素バッファから、白線の芯で大きくなる画像（0〜1）を作る。大きさは `downscale` 分の 1。
    /// `downscale` を省くと、横幅が 1600px 以上（横長の 1080p など）なら 2、それより小さければ（縦長の動画など）1 にする。
    /// 縦長の動画を半分にすると、コートの線が短くなりすぎて直線として拾えないため。
    ///
    /// 白さは、赤・緑・青の一番小さい値で測る（白は 3 つとも大きく、青い床は赤が小さい）。
    /// 両側より白い画素だけが残るので、面（白い服、看板）の縁は残らず、線の芯が残る。
    /// 32BGRA 以外のとき、小さすぎるときは nil。
    init?(whiteRidgeOf buffer: CVPixelBuffer, downscale requested: Int? = nil) {
        self.init(ridgeOf: buffer, lineColor: .white, downscale: requested)
    }

    /// `lineColor` の線の芯で大きくなる画像（0〜1）を作る。ほかは `init(whiteRidgeOf:downscale:)` と同じ。
    init?(ridgeOf buffer: CVPixelBuffer, lineColor: CourtLineColor, downscale requested: Int? = nil) {
        let downscale = requested ?? (CVPixelBufferGetWidth(buffer) >= 1600 ? 2 : 1)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA, downscale >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer) / downscale
        let height = CVPixelBufferGetHeight(buffer) / downscale
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let margin = ridgeOffsets.max() ?? 0
        guard width > 2 * margin + 2, height > 2 * margin + 2 else { return nil }

        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let white = whiteness(bytes, stride: stride, width: width, height: height, downscale: downscale, lineColor: lineColor)
        let ridge = ridgeStrength(white, width: width, height: height, margin: margin)
        self.init(width: width, height: height, values: smoothed(ridge, width: width, height: height))
    }
}

/// 1 画素の、線の色らしさ（0〜255）。並びは 32BGRA。
@inline(__always)
private func lineness(_ pixel: UnsafePointer<UInt8>, _ lineColor: CourtLineColor) -> Int {
    switch lineColor {
    case .white:
        Int(min(pixel[0], pixel[1], pixel[2]))
    case .yellow:
        max(0, Int(min(pixel[1], pixel[2])) - Int(pixel[0]))
    }
}

/// 縮めた画像の、画素ごとの白さ（線の色らしさ、0〜255）。
private func whiteness(
    _ bytes: UnsafePointer<UInt8>, stride: Int, width: Int, height: Int, downscale: Int, lineColor: CourtLineColor
) -> [Float] {
    var white = [Float](repeating: 0, count: width * height)
    let scale = 1 / Float(downscale * downscale)
    white.withUnsafeMutableBufferPointer { output in
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0
                for dy in 0..<downscale {
                    let row = bytes + (y * downscale + dy) * stride
                    for dx in 0..<downscale {
                        let pixel = row + (x * downscale + dx) * 4
                        sum += lineness(pixel, lineColor)
                    }
                }
                output[y * width + x] = Float(sum) * scale
            }
        }
    }
    return white
}

/// 左右の両方、または上下の両方より白い度合い（0〜1）。
private func ridgeStrength(_ white: [Float], width: Int, height: Int, margin: Int) -> [Float] {
    var ridge = [Float](repeating: 0, count: width * height)
    white.withUnsafeBufferPointer { input in
        ridge.withUnsafeMutableBufferPointer { output in
            for y in margin..<(height - margin) {
                for x in margin..<(width - margin) {
                    let index = y * width + x
                    let center = input[index]
                    var best: Float = 0
                    for offset in ridgeOffsets {
                        let sideways = min(center - input[index - offset], center - input[index + offset])
                        let upDown = min(center - input[index - offset * width], center - input[index + offset * width])
                        best = max(best, sideways, upDown)
                    }
                    output[index] = min(1, best / ridgeFullContrast)
                }
            }
        }
    }
    return ridge
}

/// 1:2:1 の重みで、縦と横にならす。太い線でも、芯がいちばん大きくなるようにする。
private func smoothed(_ values: [Float], width: Int, height: Int) -> [Float] {
    var horizontal = values
    var result = values
    values.withUnsafeBufferPointer { input in
        horizontal.withUnsafeMutableBufferPointer { output in
            for y in 0..<height {
                for x in 1..<(width - 1) {
                    let index = y * width + x
                    output[index] = (input[index - 1] + 2 * input[index] + input[index + 1]) / 4
                }
            }
        }
    }
    horizontal.withUnsafeBufferPointer { input in
        result.withUnsafeMutableBufferPointer { output in
            for y in 1..<(height - 1) {
                for x in 0..<width {
                    let index = y * width + x
                    output[index] = (input[index - width] + 2 * input[index] + input[index + width]) / 4
                }
            }
        }
    }
    return result
}
