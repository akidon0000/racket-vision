import CoreVideo

public extension EdgeMap {
    /// 32BGRA の画素バッファから、輝度の勾配（Sobel）の大きさを 0〜1 にしたエッジの画像を作る。
    /// 32BGRA 以外のときは nil。
    init?(bgraPixelBuffer buffer: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 2, height > 2 else { return nil }

        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var luma = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = bytes + y * stride
            for x in 0..<width {
                let pixel = row + x * 4
                let blue = Float(pixel[0])
                let green = Float(pixel[1])
                let red = Float(pixel[2])
                luma[y * width + x] = 0.114 * blue + 0.587 * green + 0.299 * red
            }
        }

        // Sobel の大きさを、約 400 で割って 0〜1 にする（コートの白線は、芝との差がこれより十分大きい）。
        let scale: Float = 1 / 400
        var values = [Float](repeating: 0, count: width * height)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let gx = (luma[index - width + 1] + 2 * luma[index + 1] + luma[index + width + 1])
                    - (luma[index - width - 1] + 2 * luma[index - 1] + luma[index + width - 1])
                let gy = (luma[index + width - 1] + 2 * luma[index + width] + luma[index + width + 1])
                    - (luma[index - width - 1] + 2 * luma[index - width] + luma[index - width + 1])
                values[index] = min(1, (gx * gx + gy * gy).squareRoot() * scale)
            }
        }
        self.init(width: width, height: height, values: values)
    }
}
