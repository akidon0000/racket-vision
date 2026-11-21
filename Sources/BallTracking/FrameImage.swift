import CoreVideo

/// 1 フレームの画素を写したもの。前のフレームと比べるために、検出器が 2 枚まで覚える。
struct FrameImage {
    let width: Int
    let height: Int
    /// BGRA の画素。行の詰め物は無く、1 行は `width * 4` バイト。
    let bytes: [UInt8]
}

extension FrameImage {
    /// 32BGRA の画素バッファを写す。32BGRA でないとき、縦か横が 8 画素より小さいときは nil。
    init?(bgraPixelBuffer buffer: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width >= 8, height >= 8, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = width * 4
        let bytes = [UInt8](unsafeUninitializedCapacity: rowBytes * height) { destination, count in
            if let start = destination.baseAddress {
                for row in 0..<height {
                    UnsafeMutableRawPointer(start + row * rowBytes).copyMemory(from: base + row * stride, byteCount: rowBytes)
                }
            }
            count = rowBytes * height
        }
        self.init(width: width, height: height, bytes: bytes)
    }
}
