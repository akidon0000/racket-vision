import CoreFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// 白線の芯から直線を取り、図面の線（8 本）との対応を総当たりして、コートを探す（`CourtLineModelSearch`）。
/// フレームごとに、最初から探す。
public struct LineModelCourtRectangleDetector: CourtRectangleDetector {
    public var search: CourtLineModelSearch
    /// 見つけた後に、元の大きさの画像で合わせ直すか。
    public var polishes: Bool

    public init(search: CourtLineModelSearch = CourtLineModelSearch(), polishes: Bool = false) {
        self.search = search
        self.polishes = polishes
    }

    public var method: CourtDetectionMethod { polishes ? .lineModelPolished : .lineModel }

    public func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> DetectionOutcome {
        let started = CFAbsoluteTimeGetCurrent()
        // 画素のまま使えるのは `.up` のときだけ。
        let ridge = orientation == .up ? EdgeMap(whiteRidgeOf: pixelBuffer) : nil
        var fit = ridge.flatMap { search.search($0) }
        if polishes, let found = fit, let full = EdgeMap(whiteRidgeOf: pixelBuffer, downscale: 1) {
            fit = search.polish(found, fullRidge: full, scale: Double(full.width) / Double(ridge?.width ?? full.width))
        }
        let size = polishes && fit != nil
            ? CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            : ridge.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        return search.outcome(method, fit: fit, size: size, started: started, imageSize: uprightImageSize(of: pixelBuffer, orientation: orientation))
    }
}

/// `LineModelCourtRectangleDetector` と同じ探し方で、見つけた後は前のフレームの結果から合わせ直す（追従）。
/// 合わなくなったとき（カメラの切り替えなど）だけ、最初から探す。映像の解析のキューから呼ばれるので、ロックで守る。
public final class TrackingLineModelCourtRectangleDetector: CourtRectangleDetector, @unchecked Sendable {
    public let method = CourtDetectionMethod.lineModelTracking
    public let search: CourtLineModelSearch
    /// 見失ってから、最初から探すまでに空けるフレームの数（探索は重いので、毎フレームは探さない）。
    public let searchInterval: Int
    private let lock = NSLock()
    private var previous: Homography?
    private var framesSinceSearch: Int

    public init(search: CourtLineModelSearch = CourtLineModelSearch(), searchInterval: Int = 5) {
        self.search = search
        self.searchInterval = searchInterval
        framesSinceSearch = searchInterval
    }

    public func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> DetectionOutcome {
        let started = CFAbsoluteTimeGetCurrent()
        let ridge = orientation == .up ? EdgeMap(whiteRidgeOf: pixelBuffer) : nil
        let fit = ridge.flatMap { next($0) }
        let size = ridge.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        return search.outcome(method, fit: fit, size: size, started: started, imageSize: uprightImageSize(of: pixelBuffer, orientation: orientation))
    }

    private func next(_ ridge: EdgeMap) -> CourtFit? {
        let (last, waited) = lock.withLock { (previous, framesSinceSearch) }
        var fit = last.flatMap { search.track(ridge, from: $0) }
        var searched = false
        if fit == nil, waited >= searchInterval {
            fit = search.search(ridge)
            searched = true
        }
        lock.withLock {
            previous = fit?.homography
            framesSinceSearch = searched ? 0 : (fit == nil ? framesSinceSearch + 1 : searchInterval)
        }
        return fit
    }
}

extension CourtLineModelSearch {
    /// 結果を、検出の結果の形にする。`size` は、`fit` の変換が写す先の画像の大きさ。
    func outcome(_ method: CourtDetectionMethod, fit: CourtFit?, size: CGSize, started: CFAbsoluteTime, imageSize: CGSize) -> DetectionOutcome {
        let quad = fit.flatMap { $0.outline(in: size, model: model) }
        return DetectionOutcome(
            method: method,
            quads: quad.map { [$0] } ?? [],
            confidence: fit.map { Float($0.support) },
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000,
            imageSize: imageSize,
            parameters: [
                "組にする直線 \(maximumLines) 本",
                "白線の芯の強さ \(String(format: "%.2f", ridgeThreshold))",
                "支持率の下限 \(String(format: "%.2f", minimumSupport))、見える線 \(minimumSupportedLines) 本以上"
            ],
            supports: quad == nil ? [] : [fit?.support ?? 0]
        )
    }
}
