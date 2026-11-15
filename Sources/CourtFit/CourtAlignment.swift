// swiftlint:disable:this file_name
import simd

/// エッジの画像。値は 0〜1。線の上ほど大きい。行優先で、左上が原点（画素の中心は整数の座標）。
public struct EdgeMap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let values: [Float]

    /// 値の数が `width * height` と違うとき、または幅か高さが 0 以下のときは nil。
    public init?(width: Int, height: Int, values: [Float]) {
        guard width > 0, height > 0, values.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.values = values
    }

    /// 双線形補間。範囲の外は 0。
    public func value(atX x: Double, y: Double) -> Double {
        guard x >= 0, y >= 0, x <= Double(width - 1), y <= Double(height - 1) else { return 0 }
        let x0 = Int(x.rounded(.down))
        let y0 = Int(y.rounded(.down))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let fx = x - Double(x0)
        let fy = y - Double(y0)
        let top = Double(values[y0 * width + x0]) * (1 - fx) + Double(values[y0 * width + x1]) * fx
        let bottom = Double(values[y1 * width + x0]) * (1 - fx) + Double(values[y1 * width + x1]) * fx
        return top * (1 - fy) + bottom * fy
    }
}

/// 線への位置合わせの結果。
public struct CourtAlignmentResult: Equatable, Sendable {
    /// 合わせた後の変換（図面から画面へ）。
    public var homography: Homography
    /// 残差が 3px 以内の点の割合（0〜1）。
    public var inlierRatio: Double
    /// 実行した反復の回数。
    public var iterations: Int
}

/// 図面の線の上の 1 点。両端は、向きを決めるのに使う。
private struct AlignmentSample {
    let court: SIMD2<Double>
    let lineStart: SIMD2<Double>
    let lineEnd: SIMD2<Double>
}

/// 反復の中で決めた、線の上の 1 点の目標。法線に沿って、エッジの最大の位置。
private struct AlignmentTarget {
    let court: SIMD2<Double>
    let normal: SIMD2<Double>
    let point: SIMD2<Double>
}

private let pointsPerLine = 40
private let searchRange = 8.0
private let searchStep = 0.5
private let minimumEdgeValue = 0.1
private let huberThreshold = 3.0
private let maximumIterations = 20
private let maximumLambda = 1e6
private let initialLambda = 1e-6
private let perturbation = 1e-6
private let parameterCount = 8

/// 図面の線を、エッジの画像に合わせて、変換を直す。出発点は `initial`（図面から画面への変換）。
/// 出発点から求まらない（点が 1 つも使えない）ときは nil。
public func aligned(
    _ edges: EdgeMap,
    from initial: Homography,
    model: CourtModel = .pickleball
) -> CourtAlignmentResult? {
    let samples = alignmentSamples(model: model)
    let refined = refine(samples, from: parameters(of: initial), edges)

    // 最後の目標で、残差が 3px 以内の点の割合を数える。
    let finalTargets = alignmentTargets(samples, refined.parameters, edges)
    let residuals = finalTargets.compactMap { target -> Double? in
        guard let target else { return nil }
        return residual(refined.parameters, target)
    }
    guard !residuals.isEmpty else { return nil }
    let inliers = residuals.filter { abs($0) <= huberThreshold }.count
    return CourtAlignmentResult(
        homography: homography(refined.parameters),
        inlierRatio: Double(inliers) / Double(residuals.count),
        iterations: refined.iterations
    )
}

/// Gauss-Newton（Levenberg-Marquardt）で、変換の 8 要素を直す。
private func refine(
    _ samples: [AlignmentSample],
    from start: [Double],
    _ edges: EdgeMap
) -> (parameters: [Double], iterations: Int) {
    var parameters = start
    var lambda = initialLambda
    var iterations = 0
    var previousCost = Double.infinity

    for _ in 0..<maximumIterations {
        iterations += 1
        let targets = alignmentTargets(samples, parameters, edges)
        guard let system = linearize(targets, parameters) else { break }
        let cost = system.cost

        var accepted: [Double]?
        var acceptedCost = cost
        while lambda <= maximumLambda {
            if let delta = system.step(lambda: lambda) {
                let candidate = zip(parameters, delta).map { $0 + $1 }
                let candidateCost = weightedCost(system.targets, system.weights, candidate)
                if let candidateCost, candidateCost < cost {
                    accepted = candidate
                    acceptedCost = candidateCost
                    lambda /= 3
                    break
                }
            }
            lambda *= 10
        }
        guard let next = accepted else { break }
        parameters = next
        if previousCost - acceptedCost < 1e-6 * previousCost {
            break
        }
        previousCost = acceptedCost
    }
    return (parameters, iterations)
}

// MARK: - 準備

private func alignmentSamples(model: CourtModel) -> [AlignmentSample] {
    var samples = [AlignmentSample]()
    for line in CourtModel.lines {
        let start = model.position(of: line.start)
        let end = model.position(of: line.end)
        for index in 0..<pointsPerLine {
            let fraction = Double(index) / Double(pointsPerLine - 1)
            samples.append(AlignmentSample(
                court: start + (end - start) * fraction,
                lineStart: start,
                lineEnd: end
            ))
        }
    }
    return samples
}

/// 変換の 8 つの要素（右下の 1 は固定）。行優先。
private func parameters(of homography: Homography) -> [Double] {
    let matrix = homography.matrix
    let scale = matrix[2][2]
    // simd_double3x3 は列優先。行 r、列 c の要素は matrix[c][r]。
    return [
        matrix[0][0] / scale, matrix[1][0] / scale, matrix[2][0] / scale,
        matrix[0][1] / scale, matrix[1][1] / scale, matrix[2][1] / scale,
        matrix[0][2] / scale, matrix[1][2] / scale
    ]
}

private func homography(_ parameters: [Double]) -> Homography {
    Homography(matrix: simd_double3x3(rows: [
        SIMD3(parameters[0], parameters[1], parameters[2]),
        SIMD3(parameters[3], parameters[4], parameters[5]),
        SIMD3(parameters[6], parameters[7], 1)
    ]))
}

private func project(_ parameters: [Double], _ point: SIMD2<Double>) -> SIMD2<Double>? {
    let denominator = parameters[6] * point.x + parameters[7] * point.y + 1
    guard abs(denominator) > 1e-12 else { return nil }
    return SIMD2(
        (parameters[0] * point.x + parameters[1] * point.y + parameters[2]) / denominator,
        (parameters[3] * point.x + parameters[4] * point.y + parameters[5]) / denominator
    )
}

// MARK: - 1 回の反復

/// 各点の目標を決める。法線の向きは現在の変換から求め、法線に沿って −8px から +8px の間で、エッジが最大の位置を選ぶ。
private func alignmentTargets(_ samples: [AlignmentSample], _ parameters: [Double], _ edges: EdgeMap) -> [AlignmentTarget?] {
    samples.map { sample in
        guard let start = project(parameters, sample.lineStart),
              let end = project(parameters, sample.lineEnd),
              let center = project(parameters, sample.court) else { return nil }
        let direction = end - start
        let length = simd_length(direction)
        guard length > 1e-9 else { return nil }
        let normal = SIMD2(-direction.y, direction.x) / length
        var bestOffset = 0.0
        var bestValue = -Double.infinity
        let steps = Int((2 * searchRange) / searchStep)
        for step in 0...steps {
            let offset = -searchRange + Double(step) * searchStep
            let value = edges.value(atX: center.x + offset * normal.x, y: center.y + offset * normal.y)
            if value > bestValue {
                bestValue = value
                bestOffset = offset
            }
        }
        guard bestValue >= minimumEdgeValue else { return nil }
        return AlignmentTarget(court: sample.court, normal: normal, point: center + bestOffset * normal)
    }
}

/// 残差（ピクセル）。法線の向きに、変換した点と目標の差を取る。
private func residual(_ parameters: [Double], _ target: AlignmentTarget) -> Double? {
    guard let projected = project(parameters, target.court) else { return nil }
    return simd_dot(target.normal, projected - target.point)
}

/// Huber 型の重み。3px 以内は 1、それ以外は 3 / |r|。
private func huberWeight(_ residual: Double) -> Double {
    abs(residual) <= huberThreshold ? 1 : huberThreshold / abs(residual)
}

/// 重みつきの二乗和。`targets` と `weights` は同じ順序。どれかの点が変換できないときは nil。
private func weightedCost(_ targets: [AlignmentTarget], _ weights: [Double], _ parameters: [Double]) -> Double? {
    var total = 0.0
    for (target, weight) in zip(targets, weights) {
        guard let value = residual(parameters, target) else { return nil }
        total += weight * value * value
    }
    return total
}

/// 1 回の反復で使う、線形化した最小二乗の問題。`targets` は、出発点で残差が出た点だけ。
private struct LinearSystem {
    let targets: [AlignmentTarget]
    let jacobian: [[Double]]
    let residuals: [Double]
    let weights: [Double]
    let cost: Double
    let columnScale: [Double]

    /// 正規方程式を解いて、変換の更新量を返す。Jacobi の列の正規化をしてから、λ を足す（Levenberg-Marquardt）。
    func step(lambda: Double) -> [Double]? {
        var normal = [[Double]](repeating: [Double](repeating: 0, count: parameterCount), count: parameterCount)
        var right = [Double](repeating: 0, count: parameterCount)
        for row in 0..<residuals.count {
            let weight = weights[row]
            for col in 0..<parameterCount {
                let scaled = jacobian[row][col] / columnScale[col]
                right[col] -= weight * scaled * residuals[row]
                for other in 0..<parameterCount {
                    normal[col][other] += weight * scaled * jacobian[row][other] / columnScale[other]
                }
            }
        }
        for col in 0..<parameterCount {
            normal[col][col] += lambda
        }
        guard let solution = solveLinear(normal, right) else { return nil }
        return zip(solution, columnScale).map { $0 / $1 }
    }
}

/// 出発点の変換の周りで、残差と Jacobi 行列（差分）を作る。
private func linearize(_ targets: [AlignmentTarget?], _ parameters: [Double]) -> LinearSystem? {
    var rows = [(target: AlignmentTarget, residual: Double)]()
    for target in targets {
        guard let target, let value = residual(parameters, target) else { continue }
        rows.append((target, value))
    }
    guard !rows.isEmpty else { return nil }

    var jacobian = [[Double]](repeating: [Double](repeating: 0, count: parameterCount), count: rows.count)
    for col in 0..<parameterCount {
        var moved = parameters
        moved[col] += perturbation
        for (index, row) in rows.enumerated() {
            guard let movedResidual = residual(moved, row.target) else { return nil }
            jacobian[index][col] = (movedResidual - row.residual) / perturbation
        }
    }

    let weights = rows.map { huberWeight($0.residual) }
    var cost = 0.0
    for (index, row) in rows.enumerated() {
        cost += weights[index] * row.residual * row.residual
    }
    var columnScale = [Double](repeating: 1, count: parameterCount)
    for col in 0..<parameterCount {
        var sum = 0.0
        for index in 0..<rows.count {
            sum += weights[index] * jacobian[index][col] * jacobian[index][col]
        }
        columnScale[col] = sum > 0 ? sum.squareRoot() : 1
    }
    return LinearSystem(
        targets: rows.map(\.target),
        jacobian: jacobian,
        residuals: rows.map(\.residual),
        weights: weights,
        cost: cost,
        columnScale: columnScale
    )
}

/// 部分ピボットつきのガウス消去法。解けないときは nil。
private func solveLinear(_ coefficients: [[Double]], _ constants: [Double]) -> [Double]? {
    var matrix = coefficients
    var values = constants
    let count = values.count
    for column in 0..<count {
        var pivot = column
        for row in (column + 1)..<count where abs(matrix[row][column]) > abs(matrix[pivot][column]) {
            pivot = row
        }
        guard abs(matrix[pivot][column]) > 1e-300 else { return nil }
        matrix.swapAt(column, pivot)
        values.swapAt(column, pivot)
        for row in (column + 1)..<count {
            let factor = matrix[row][column] / matrix[column][column]
            guard factor != 0 else { continue }
            for k in column..<count {
                matrix[row][k] -= factor * matrix[column][k]
            }
            values[row] -= factor * values[column]
        }
    }
    var solution = [Double](repeating: 0, count: count)
    for row in stride(from: count - 1, through: 0, by: -1) {
        var sum = values[row]
        for k in (row + 1)..<count {
            sum -= matrix[row][k] * solution[k]
        }
        solution[row] = sum / matrix[row][row]
    }
    return solution
}
