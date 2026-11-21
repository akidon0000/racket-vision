@testable import BallTracking
import CoreVideo
import Testing

/// 合成フレームの色。
struct SyntheticColor {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    /// 青いコート。
    static let court = SyntheticColor(red: 40, green: 80, blue: 200)
    /// 黄緑の球。
    static let ball = SyntheticColor(red: 210, green: 230, blue: 80)
    static let gray = SyntheticColor(red: 120, green: 120, blue: 120)
    /// オレンジの球。
    static let orangeBall = SyntheticColor(red: 204, green: 94, blue: 57)
}

/// 合成したフレーム（1 色の背景に、円や四角を置く）。座標は画素で、左上が原点。
struct SyntheticFrame {
    let width: Int
    let height: Int
    /// BGRA の画素（行の詰め物なし）。
    private(set) var bytes: [UInt8]

    init(width: Int = 640, height: Int = 360, background: SyntheticColor = .court) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 255, count: width * height * 4)
        fillRect(x: 0, y: 0, width: width, height: height, color: background)
    }

    mutating func fillRect(x: Int, y: Int, width rectWidth: Int, height rectHeight: Int, color: SyntheticColor) {
        for row in max(0, y)..<min(height, y + rectHeight) {
            for column in max(0, x)..<min(width, x + rectWidth) {
                set(column, row, color)
            }
        }
    }

    /// 円を塗る。画素の中心（番号 + 0.5）が円の中にある画素を塗る。
    mutating func fillCircle(centerX: Double, centerY: Double, radius: Double, color: SyntheticColor) {
        for row in 0..<height {
            for column in 0..<width {
                let dx = Double(column) + 0.5 - centerX
                let dy = Double(row) + 0.5 - centerY
                if dx * dx + dy * dy <= radius * radius {
                    set(column, row, color)
                }
            }
        }
    }

    private mutating func set(_ x: Int, _ y: Int, _ color: SyntheticColor) {
        let offset = (y * width + x) * 4
        bytes[offset] = color.blue
        bytes[offset + 1] = color.green
        bytes[offset + 2] = color.red
        bytes[offset + 3] = 255
    }

    var image: FrameImage {
        FrameImage(width: width, height: height, bytes: bytes)
    }

    /// 32BGRA の画素バッファにする。
    func pixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        let created = try #require(buffer)
        CVPixelBufferLockBaseAddress(created, [])
        defer { CVPixelBufferUnlockBaseAddress(created, []) }
        let base = try #require(CVPixelBufferGetBaseAddress(created))
        let stride = CVPixelBufferGetBytesPerRow(created)
        bytes.withUnsafeBytes { source in
            guard let start = source.baseAddress else { return }
            for row in 0..<height {
                (base + row * stride).copyMemory(from: start + row * width * 4, byteCount: width * 4)
            }
        }
        return created
    }
}
