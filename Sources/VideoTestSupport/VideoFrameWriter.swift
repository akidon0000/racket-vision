import AVFoundation
import CoreGraphics
import Foundation

public enum VideoFrameWriterError: Error {
    case cannotWrite
}

/// 画像を 1 枚ずつ足して、動画（H.264 の mp4）にする。実時間ではなく、できるだけ速く書く。
public final class VideoFrameWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor

    /// `width` と `height` は偶数であること。同じ場所にファイルがあれば、置き換える。
    public init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else {
            throw VideoFrameWriterError.cannotWrite
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? VideoFrameWriterError.cannotWrite
        }
        writer.startSession(atSourceTime: .zero)
    }

    /// 1 枚足す。`image` の大きさは、`init` に渡した大きさと同じであること。`seconds` は、前に足したものより後であること。
    public func append(_ image: CGImage, at seconds: Double) throws {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }
        let buffer = try makePixelBuffer(from: image)
        guard adaptor.append(buffer, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 60000)) else {
            throw writer.error ?? VideoFrameWriterError.cannotWrite
        }
    }

    /// 書き終える。
    public func finish() async {
        input.markAsFinished()
        await writer.finishWriting()
    }
}
