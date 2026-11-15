import CoreVideo
import Foundation

/// 連続するフレームから、球を探す。
///
/// 方式ごとに実装を分け、同じ入出力にする。実装は前のフレームを覚えるので、フレームは時刻の順に渡す。
/// 動画 1 本（撮影 1 回）ごとに作り直すか、`reset()` を呼ぶ。
public protocol BallDetector: Sendable {
    /// この実装の方式。
    var method: BallDetectionMethod { get }
    /// 1 フレームから球を探す。`pixelBuffer` は上向きの 32BGRA、`time` はそのフレームの時刻（秒）。
    func detect(in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> BallFrameOutcome
    /// 覚えているフレームと追跡を捨てる。
    func reset()
}
