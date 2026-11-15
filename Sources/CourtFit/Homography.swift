import simd

/// 平面から平面への射影変換（3×3 の行列）。図面（メートル）から画面（ピクセル）への変換に使う。
public struct Homography: Equatable, Sendable {
    public var matrix: simd_double3x3

    public init(matrix: simd_double3x3) {
        self.matrix = matrix
    }

    /// 対応する点の組から、最小二乗で求める。点は 4 組以上要る。求まらないとき（点が足りない、一直線に並ぶなど）は nil。
    public init?(from source: [SIMD2<Double>], to destination: [SIMD2<Double>]) {
        guard source.count >= 4, source.count == destination.count,
              let sourceNormalization = Self.normalization(of: source),
              let destinationNormalization = Self.normalization(of: destination) else {
            return nil
        }
        // 桁の違う座標（メートルとピクセル）をそのまま解くと誤差が大きいので、先に重心と大きさをそろえる。
        let from = source.map { Self.apply(sourceNormalization, to: $0) }
        let to = destination.map { Self.apply(destinationNormalization, to: $0) }

        // 未知数は 8 個（右下の要素を 1 に固定する）。正規方程式（8×8）を作って解く。
        var normal = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var right = [Double](repeating: 0, count: 8)
        for (point, target) in zip(from, to) {
            let rows: [([Double], Double)] = [
                ([point.x, point.y, 1, 0, 0, 0, -target.x * point.x, -target.x * point.y], target.x),
                ([0, 0, 0, point.x, point.y, 1, -target.y * point.x, -target.y * point.y], target.y)
            ]
            for (row, value) in rows {
                for i in 0..<8 {
                    right[i] += row[i] * value
                    for j in 0..<8 {
                        normal[i][j] += row[i] * row[j]
                    }
                }
            }
        }
        guard let solution = Self.solve(normal, right) else {
            return nil
        }
        let normalized = simd_double3x3(rows: [
            SIMD3(solution[0], solution[1], solution[2]),
            SIMD3(solution[3], solution[4], solution[5]),
            SIMD3(solution[6], solution[7], 1)
        ])
        matrix = destinationNormalization.inverse * normalized * sourceNormalization
    }

    /// 点を変換する。無限遠に飛ぶとき（分母が 0 に近いとき）は nil。
    public func project(_ point: SIMD2<Double>) -> SIMD2<Double>? {
        let projected = matrix * SIMD3(point.x, point.y, 1)
        guard abs(projected.z) > 1e-12 else { return nil }
        return SIMD2(projected.x / projected.z, projected.y / projected.z)
    }

    /// 逆の変換。行列が潰れているときは nil。
    public var inverse: Homography? {
        guard abs(matrix.determinant) > 1e-12 else { return nil }
        return Homography(matrix: matrix.inverse)
    }

    /// 点の重心を原点に、原点からの平均の距離を √2 にそろえる行列。点が 1 か所に集まっているときは nil。
    private static func normalization(of points: [SIMD2<Double>]) -> simd_double3x3? {
        let count = Double(points.count)
        let center = points.reduce(SIMD2<Double>(0, 0), +) / count
        let meanDistance = points.reduce(0) { $0 + simd_length($1 - center) } / count
        guard meanDistance > 1e-12 else { return nil }
        let scale = 2.0.squareRoot() / meanDistance
        return simd_double3x3(rows: [
            SIMD3(scale, 0, -scale * center.x),
            SIMD3(0, scale, -scale * center.y),
            SIMD3(0, 0, 1)
        ])
    }

    private static func apply(_ matrix: simd_double3x3, to point: SIMD2<Double>) -> SIMD2<Double> {
        let moved = matrix * SIMD3(point.x, point.y, 1)
        return SIMD2(moved.x, moved.y)
    }

    /// 連立一次方程式を、部分ピボットつきの掃き出し法で解く。解けないときは nil。
    private static func solve(_ coefficients: [[Double]], _ constants: [Double]) -> [Double]? {
        let size = constants.count
        var rows = coefficients
        var values = constants
        for column in 0..<size {
            var pivot = column
            for row in (column + 1)..<size where abs(rows[row][column]) > abs(rows[pivot][column]) {
                pivot = row
            }
            guard abs(rows[pivot][column]) > 1e-12 else { return nil }
            rows.swapAt(column, pivot)
            values.swapAt(column, pivot)
            for row in 0..<size where row != column {
                let factor = rows[row][column] / rows[column][column]
                guard factor != 0 else { continue }
                for index in column..<size {
                    rows[row][index] -= factor * rows[column][index]
                }
                values[row] -= factor * values[column]
            }
        }
        return (0..<size).map { values[$0] / rows[$0][$0] }
    }
}
