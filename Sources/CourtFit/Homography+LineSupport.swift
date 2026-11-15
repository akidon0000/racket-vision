import simd

/// 白線の支持率を測るときの、線の上の点の数（1 本の線あたり）。
private let supportPointsPerLine = 40
/// エッジの強さが、この値以上なら「線の上にある」とみなす。
private let supportEdgeThreshold: Float = 0.5
/// 点の周りのどれだけ離れていてもエッジを拾うか（画素）。少しのずれを許すため。
private let supportSearchRadius = 1
/// 画面の中に入っている点が、この割合に満たないときは測れないとみなす。
private let minimumInsideRatio = 0.6

public extension Homography {
    /// 図面の白線（`CourtModel.lines`）を、この変換で画面に写し、その上にエッジがある割合（0〜1）。
    ///
    /// 線の上の点のうち、画面の中に入っているものだけを数える。画面の中に入っている点が少なすぎるときは nil。
    /// コートの線が画像の上にあれば高くなり、スコアボードや、ずれた台形では低くなる。
    func lineSupport(in edges: EdgeMap, model: CourtModel = .pickleball) -> Double? {
        var total = 0
        var inside = 0
        var hits = 0
        for line in CourtModel.lines {
            let start = model.position(of: line.start)
            let end = model.position(of: line.end)
            for index in 0..<supportPointsPerLine {
                total += 1
                let fraction = Double(index) / Double(supportPointsPerLine - 1)
                let court = start + (end - start) * fraction
                guard let pixel = project(court),
                      pixel.x >= 0, pixel.y >= 0,
                      pixel.x <= Double(edges.width - 1), pixel.y <= Double(edges.height - 1) else { continue }
                inside += 1
                if edges.peak(around: pixel, radius: supportSearchRadius) >= supportEdgeThreshold {
                    hits += 1
                }
            }
        }
        guard total > 0, Double(inside) / Double(total) >= minimumInsideRatio, inside > 0 else { return nil }
        return Double(hits) / Double(inside)
    }
}

private extension EdgeMap {
    /// 点の周りの正方形の中で、一番強いエッジ。
    func peak(around point: SIMD2<Double>, radius: Int) -> Float {
        let centerX = Int(point.x.rounded())
        let centerY = Int(point.y.rounded())
        var best: Float = 0
        for dy in -radius...radius {
            let y = centerY + dy
            guard y >= 0, y < height else { continue }
            for dx in -radius...radius {
                let x = centerX + dx
                guard x >= 0, x < width else { continue }
                best = max(best, values[y * width + x])
            }
        }
        return best
    }
}
