import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 映像の 1 枚を Jev に見せて、場面の見立て（`SceneAdvice`）をもらう。
///
/// 動画の最初と、場面が大きく変わったときにだけ呼ぶ（1 回 0.3〜0.8 秒、入力は約 4,000 トークン）。
/// 毎フレームは呼ばない。
public struct SceneAdvisor: Sendable {
    public var client: JevClient

    public init(client: JevClient) {
        self.client = client
    }

    /// API キーを、ファイルから読んで作る。読めない、空のときは nil。
    public init?(keyFile: URL) {
        guard let text = try? String(contentsOf: keyFile, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        self.init(client: JevClient(apiKey: key))
    }

    #if os(macOS)
    /// 開発用の Mac で、API キーを置く場所（`~/.config/racket-vision/jev.key`）。
    public static var defaultKeyFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/racket-vision/jev.key")
    }
    #endif

    public func advise(on image: CGImage) async throws -> SceneAdvice {
        guard let jpeg = Self.jpeg(image) else { throw JevClient.Failure.malformed("画像を JPEG にできない") }
        return try SceneAdvice(answers: await client.ask(jpeg: jpeg, questions: SceneAdvice.questions))
    }

    /// Jev が受ける大きさ（長い辺 1568 画素まで）に縮めた JPEG。
    static func jpeg(_ image: CGImage, longestSide: Int = 1568) -> Data? {
        let scale = min(1, Double(longestSide) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, resized, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
