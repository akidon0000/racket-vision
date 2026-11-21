import CoreGraphics

/// コートの線 1 本（コートの座標。横 0〜1、縦 0〜1。`CourtPlane` と同じ）。
public struct CourtSegment: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

extension CourtPlane {
    /// ピックルボールのコートの線（外周、ネット、キッチンの線、センターライン）。
    /// キッチン（ネットから 2.13 m）は、コートの長さ 13.41 m に対して 0.159。センターラインは、キッチンの線からベースラインまで。
    public static let pickleballLines: [CourtSegment] = {
        let kitchen = 2.1336 / 13.4112
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> CourtSegment {
            CourtSegment(start: CGPoint(x: x1, y: y1), end: CGPoint(x: x2, y: y2))
        }
        return [
            line(0, 0, 1, 0), line(1, 0, 1, 1), line(1, 1, 0, 1), line(0, 1, 0, 0),
            line(0, 0.5 - kitchen, 1, 0.5 - kitchen), line(0, 0.5 + kitchen, 1, 0.5 + kitchen),
            line(0.5, 0, 0.5, 0.5 - kitchen), line(0.5, 0.5 + kitchen, 0.5, 1)
        ]
    }()

    /// ネット（コートの縦 0.5 の線）。
    public static let net = CourtSegment(start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))
}
