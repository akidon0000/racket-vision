import AVFoundation
import CoreVideo

/// 動画のフレームを、機種の上限まで縮め、コマを間引いて、先頭から順に読む。
public final class DeviceFrameSource {
    /// 読むフレームの大きさ（画素）。
    public let size: CGSize
    /// 動画のコマ数（1 秒あたり）。
    public let sourceFrameRate: Double
    /// 読むコマ数（1 秒あたり）。
    public let frameRate: Double
    /// 動画の長さ（秒）。
    public let duration: Double
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var nextTime = 0.0

    /// `maximumWidth` などは、機種の上限。縦長の動画は、縦と横を入れ替えて比べる。
    public init(url: URL, maximumWidth: Int, maximumHeight: Int, maximumFrameRate: Double) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw DeviceFrameSourceError.noVideoTrack
        }
        let natural = try await track.load(.naturalSize)
        let rate = Double(try await track.load(.nominalFrameRate))
        duration = try await asset.load(.duration).seconds
        let longSide = Double(max(natural.width, natural.height))
        let shortSide = Double(min(natural.width, natural.height))
        let scale = min(1, Double(max(maximumWidth, maximumHeight)) / longSide, Double(min(maximumWidth, maximumHeight)) / shortSide)
        // H.264 などの都合で、偶数にそろえる。
        let width = Int(Double(natural.width) * scale / 2) * 2
        let height = Int(Double(natural.height) * scale / 2) * 2
        size = CGSize(width: width, height: height)
        sourceFrameRate = rate
        frameRate = min(rate > 0 ? rate : maximumFrameRate, maximumFrameRate)
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw DeviceFrameSourceError.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? DeviceFrameSourceError.cannotRead }
    }

    /// 次のフレーム（画素と、動画の先頭からの秒）。コマを間引くので、間のフレームは飛ばす。最後まで読んだら nil。
    public func next() -> (pixelBuffer: CVPixelBuffer, seconds: Double)? {
        let step = 1 / frameRate
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            // 少し早めに受ける（コマの時刻の揺れの分）。
            guard seconds >= nextTime - step * 0.25 else { continue }
            nextTime = max(nextTime + step, seconds + step * 0.75)
            return (buffer, seconds)
        }
        return nil
    }
}

public enum DeviceFrameSourceError: Error {
    case noVideoTrack
    case cannotRead
}
