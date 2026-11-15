import CoreGraphics

/// 映像を画面に映すときの、大きさの合わせ方。
public enum AspectFit: Sendable {
    /// 画面いっぱいに広げ、はみ出した部分は切る（`resizeAspectFill`）。
    case fill
    /// 映像の全体を収め、余白を作る（`resizeAspect`）。
    case fit
}

/// 映像の正規化座標（左下が原点、0〜1）を、画面の座標（左上が原点、点）に変換する。
///
/// 映像は、表示の向きに合わせて回したあとの「上向き」の大きさで考える。
public struct AspectMapping: Equatable, Sendable {
    /// 映像の大きさ（表示の向きに回したあと）。
    public var imageSize: CGSize
    /// 画面（表示先のビュー）の大きさ。
    public var viewSize: CGSize
    /// 大きさの合わせ方。
    public var fit: AspectFit

    public init(imageSize: CGSize, viewSize: CGSize, fit: AspectFit = .fill) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.fit = fit
    }

    /// 正規化座標を、画面の座標に変換する。
    public func viewPoint(forNormalized point: CGPoint) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let widthScale = viewSize.width / imageSize.width
        let heightScale = viewSize.height / imageSize.height
        let scale = fit == .fill ? max(widthScale, heightScale) : min(widthScale, heightScale)
        let drawnWidth = imageSize.width * scale
        let drawnHeight = imageSize.height * scale
        let originX = (viewSize.width - drawnWidth) / 2
        let originY = (viewSize.height - drawnHeight) / 2
        return CGPoint(
            x: originX + point.x * drawnWidth,
            y: originY + (1 - point.y) * drawnHeight
        )
    }

    /// 四隅をまとめて画面の座標に変換する。
    public func viewQuad(for quad: DetectedQuad) -> [CGPoint] {
        quad.corners.map { viewPoint(forNormalized: $0) }
    }
}
