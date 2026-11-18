import CoreGraphics
import simd

/// 球を探す範囲（凸な多角形、正規化座標、左下が原点）。範囲から `margin` より遠く外れた候補は、球として扱わない。
///
/// コートの矩形は地面の上の形で、空中の球は、映像ではその上に写る。そこで、矩形を上へ持ち上げた形も合わせて、
/// 両方を囲む凸な多角形を範囲にする。
struct BallRegion {
    /// 範囲の頂点（反時計回り）。
    let corners: [SIMD2<Double>]
    let margin: Double

    /// `corners` は、コートの矩形の四隅（左上、右上、右下、左下の順）。
    /// `airHeight` は、球の高さの見込み。上の 2 点は上の辺の長さ、下の 2 点は下の辺の長さに、これを掛けた分だけ上へ持ち上げる
    /// （コートの幅 6.1 m に対する割合。0.6 で約 3.7 m）。`aspect` は、映像の横 ÷ 縦。
    init(corners: [CGPoint], margin: Double, airHeight: Double = 0, aspect: Double = 1) {
        var points = corners.map { SIMD2(Double($0.x), Double($0.y)) }
        if points.count == 4, airHeight > 0 {
            // 辺の長さは、映像の幅を 1 とした長さで測る。持ち上げる量は、映像の高さを 1 とした長さに直す。
            func lift(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
                simd_length(SIMD2(b.x - a.x, (b.y - a.y) / aspect)) * airHeight * aspect
            }
            let top = lift(points[0], points[1])
            let bottom = lift(points[2], points[3])
            points += [
                points[0] + SIMD2(0, top), points[1] + SIMD2(0, top),
                points[2] + SIMD2(0, bottom), points[3] + SIMD2(0, bottom)
            ]
        }
        self.corners = BallRegion.convexHull(points)
        self.margin = margin
    }

    /// 点の、範囲の辺からの符号つき距離（内側が正）。範囲が空のときは無限大。
    func signedDistance(to point: SIMD2<Double>) -> Double {
        var best = Double.infinity
        for i in corners.indices {
            let a = corners[i]
            let edge = corners[(i + 1) % corners.count] - a
            let length = simd_length(edge)
            guard length > 0 else { continue }
            let cross = edge.x * (point.y - a.y) - edge.y * (point.x - a.x)
            best = min(best, cross / length)
        }
        return best
    }

    /// 点が範囲の中（`margin` の分だけ外まで）にあるか。範囲が空のときは、どの点も入らない。
    func contains(_ point: SIMD2<Double>) -> Bool {
        !corners.isEmpty && signedDistance(to: point) >= -margin
    }

    /// 点を囲む凸な多角形（反時計回り）。3 点に満たないときは、そのまま返す。
    private static func convexHull(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count >= 3 else { return sorted }
        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func chain(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
            var hull = [SIMD2<Double>]()
            for point in points {
                while hull.count >= 2, cross(hull[hull.count - 2], hull[hull.count - 1], point) <= 0 {
                    hull.removeLast()
                }
                hull.append(point)
            }
            return hull
        }
        let lower = chain(sorted)
        let upper = chain(sorted.reversed())
        return Array(lower.dropLast() + upper.dropLast())
    }
}
