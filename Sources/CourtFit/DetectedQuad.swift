import CoreGraphics

/// 映像から見つけた四角形（コートの矩形）。
///
/// 四隅は、映像の大きさに対する 0〜1 の正規化座標で持つ。原点は左下（Vision と同じ）。
/// 映像は、表示の向きに合わせて回したあとの「上向き」の大きさで考える。
public struct DetectedQuad: Equatable, Sendable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// 四隅を、描く順（左上、右上、右下、左下）に並べた配列。
    public var corners: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }
}
