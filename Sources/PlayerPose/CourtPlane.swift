import CoreGraphics
import simd

/// コートの面と映像のあいだの変換。コートの矩形の四隅から作る。
///
/// コートの座標は、横が 0（左のサイドライン）〜1（右のサイドライン）、縦が 0（手前のベースライン）〜1（奥のベースライン）。
/// ネットは縦 0.5。映像の座標は、正規化座標（左下が原点）。
public struct CourtPlane: Equatable, Sendable {
    /// コートの座標から映像の座標への射影変換。
    private let toImage: simd_double3x3
    private let toCourt: simd_double3x3

    /// `corners` は、映像でのコートの四隅（奥の左、奥の右、手前の右、手前の左の順。`DetectedQuad.corners` と同じ）。
    /// 4 点でないとき、四隅がつぶれているときは nil。
    public init?(corners: [CGPoint]) {
        guard corners.count == 4 else { return nil }
        let points = corners.map { SIMD2(Double($0.x), Double($0.y)) }
        // 単位の正方形の (0,0)、(1,0)、(1,1)、(0,1) を、手前の左、手前の右、奥の右、奥の左に写す。
        let p0 = points[3], p1 = points[2], p2 = points[1], p3 = points[0]
        let d1 = p1 - p2
        let d2 = p3 - p2
        let sum = p0 - p1 + p2 - p3
        let denominator = d1.x * d2.y - d1.y * d2.x
        guard abs(denominator) > 1e-12 else { return nil }
        let g = (sum.x * d2.y - sum.y * d2.x) / denominator
        let h = (d1.x * sum.y - d1.y * sum.x) / denominator
        let matrix = simd_double3x3(rows: [
            SIMD3(p1.x - p0.x + g * p1.x, p3.x - p0.x + h * p3.x, p0.x),
            SIMD3(p1.y - p0.y + g * p1.y, p3.y - p0.y + h * p3.y, p0.y),
            SIMD3(g, h, 1)
        ])
        guard abs(matrix.determinant) > 1e-12 else { return nil }
        toImage = matrix
        toCourt = matrix.inverse
    }

    /// コートの座標の点が、映像のどこに写るか。カメラの後ろ側に当たる点は nil。
    public func imagePoint(for courtPoint: CGPoint) -> CGPoint? {
        project(courtPoint, with: toImage)
    }

    /// 映像の点（地面に接している点）が、コートのどこか。
    public func courtPoint(for imagePoint: CGPoint) -> CGPoint? {
        project(imagePoint, with: toCourt)
    }

    private func project(_ point: CGPoint, with matrix: simd_double3x3) -> CGPoint? {
        let value = matrix * SIMD3(Double(point.x), Double(point.y), 1)
        guard value.z > 1e-9 else { return nil }
        return CGPoint(x: value.x / value.z, y: value.y / value.z)
    }
}
