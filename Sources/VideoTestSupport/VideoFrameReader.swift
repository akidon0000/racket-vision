import AVFoundation
import CoreVideo

/// 動画の 1 フレーム。
public struct VideoFrame {
    /// 32BGRA の画素。次のフレームを読むと、中身が使い回されることがある。
    public let pixelBuffer: CVPixelBuffer
    /// 動画の先頭からの秒。
    public let seconds: Double
}

public enum VideoFrameReaderError: Error {
    case noVideoTrack
    /// 回して表示する動画（撮影の向きが記録されている動画）は読めない。
    case rotated
    case cannotRead
}

/// 動画のフレームを、先頭から順に、間を飛ばさずに読む。
public final class VideoFrameReader {
    /// フレームの大きさ（ピクセル）。
    public let size: CGSize
    /// 1 秒あたりのフレームの数（動画に書かれている値）。
    public let frameRate: Double
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    public init(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoFrameReaderError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rate = try await track.load(.nominalFrameRate)
        guard transform.isIdentity else {
            throw VideoFrameReaderError.rotated
        }
        size = naturalSize
        frameRate = Double(rate)
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw VideoFrameReaderError.cannotRead
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? VideoFrameReaderError.cannotRead
        }
    }

    /// 次のフレーム。最後まで読んだら nil。
    public func next() -> VideoFrame? {
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            return VideoFrame(pixelBuffer: buffer, seconds: CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        return nil
    }
}
