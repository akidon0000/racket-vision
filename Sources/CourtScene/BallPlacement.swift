import BallTracking
import CoreGraphics
import simd

/// 球の軌跡を 3D に置く。
///
/// 1 台のカメラでは、球までの距離（高さ）は分からない。そこで、打ってから次に何かに当たる（打たれる、弾む）までの
/// ひと続き（飛行）のあいだ、球は地面の上をまっすぐ進み、高さは重力の放物線になる、とみて当てはめる。
///
/// 軌跡を、先頭から順に、放物線に当てはまるあいだだけ伸ばして、飛行に分ける。当てはまらなくなったところ（打球、バウンド）で
/// 区切り、そこから次の飛行を始める。1 つの飛行には、点が多く入るので、1 点ずつの揺れに強い。当てはめは、写った位置から
/// 外れる量の二乗の和を最小にする（未知数は、飛行の始まりの位置と速さの 6 つ）。外れの大きい 1 点（誤検出）は、除いて当てはめ直す。
public struct BallPlacement: Sendable {
    /// 1 つの飛行に要る、点の数。
    public var minimumSamples = 6
    /// 写った位置からの外れの許容（映像の幅に対する割合、二乗平均）。これより外れたら、その飛行は伸ばさない。
    public var maximumError = 0.006
    /// 当てはまらない点が、これだけ続いたら、飛行を区切る。
    public var breakAfter = 3
    /// 点と点のあいだが、これより空いたら（秒）、別の飛行とする。
    public var maximumGap = 0.3
    /// 高さとしてありえる範囲（メートル）。
    public var heightRange: ClosedRange<Double> = -0.3...8
    /// コートの中心からの、横（x）と縦（z）の範囲（メートル）。コートの外 5 m・後ろ 6 m まで。
    /// これより外は、当てはめが外れた（カメラのそばに置いてしまった）とみて、出さない。
    public var groundRange = (x: 3.048 + 5.0, z: 6.7056 + 6.0)
    /// 重力の加速度（メートル毎秒毎秒）。
    public var gravity = 9.81
    /// 球の半径（メートル）。ピックルボールの球は直径 7.4 cm。
    public var ballRadius = 0.037
    /// 写った球の大きさから見込んだ、カメラからの距離を、どれだけ重く見るか。0 なら使わない。
    /// カメラの向きに沿って飛ぶ球は、写った位置だけでは距離が決まりにくいので、その手がかりになる見込みで足した。
    /// ただし、サンプル動画（01、02、04、05）では、置ける点は増えたが、ネットを越える高さに収まる割合は動画によって
    /// 上がったり下がったりして、良くならなかった（写った大きさが、ぶれやにじみで数画素ずれるため）。既定では使わない。
    public var depthWeight = 0.0

    public init() {}

    /// 当てはめた飛行 1 つ。
    public struct Flight: Equatable, Sendable {
        /// 飛行の始まりの時刻（秒）と、そのときの位置と速さ（3D の座標）。
        public var startTime: Double
        public var position: SIMD3<Double>
        public var velocity: SIMD3<Double>
        /// 飛行の終わりの時刻（秒）。
        public var endTime: Double
        /// 重力の加速度。
        public var gravity: Double

        /// 時刻 `time` での位置。
        public func position(at time: Double) -> SIMD3<Double> {
            let dt = time - startTime
            return position + velocity * dt + SIMD3(0, -gravity / 2 * dt * dt, 0)
        }
    }

    /// 軌跡の点ごとの 3D の位置。当てはまらない点は nil。並びは `samples` と同じ（`samples` は時刻の順）。
    public func place(_ samples: [BallSample], camera: CourtCamera) -> [SIMD3<Double>?] {
        var positions = [SIMD3<Double>?](repeating: nil, count: samples.count)
        for (range, flight) in flights(samples, camera: camera) {
            for index in range {
                positions[index] = flight.position(at: samples[index].time)
            }
        }
        return positions
    }

    /// 軌跡を飛行に分けて当てはめる。飛行ごとに、入る点の番号の範囲と、当てはめた飛行を返す。
    public func flights(_ samples: [BallSample], camera: CourtCamera) -> [(ClosedRange<Int>, Flight)] {
        let projector = Projector(camera: camera, gravity: gravity, ballRadius: ballRadius, depthWeight: depthWeight)
        var fitted = [FittedFlight]()
        var start = 0
        while start + minimumSamples <= samples.count {
            if let (end, flight, accepted) = grow(from: start, samples: samples, projector: projector) {
                fitted.append(FittedFlight(range: start...end, accepted: accepted, flight: flight))
                // 区切りの点（打球やバウンドの点）は、次の飛行の始まりにも使う。
                start = max(end, start + 1)
            } else {
                start += 1
            }
        }
        if joinsFlights {
            fitted = joined(fitted, samples: samples, projector: projector)
        }
        return fitted.map { ($0.range, $0.flight) }
    }

    /// 当てはめた飛行と、当てはめに使った点（見込みから外れた点は入れない）。
    private struct FittedFlight {
        var range: ClosedRange<Int>
        var accepted: [Int]
        var flight: Flight
    }

    /// 続いている飛行（前の飛行の終わりの点から、次の飛行が始まる）を、まとめて当てはめ直す。
    ///
    /// 飛行を 1 つずつ当てはめると、点の少ない飛行は奥行きが決まらず、コートの外や高いところに置かれる。
    /// また、同じ打球やバウンドの点なのに、前の飛行の終わりと次の飛行の始まりが、別の位置になる。
    /// そこで、つなぎ目で位置が同じになる式と、飛行の始まりと終わり（打つ、弾む）は低いところにある、という弱い見込みの式を
    /// 足して、まとめて解く。まとめると写った位置から外れすぎる（誤検出の飛行が混じる）ときは、1 つずつのまま使う。
    private func joined(_ fitted: [FittedFlight], samples: [BallSample], projector: Projector) -> [FittedFlight] {
        var chains = [[FittedFlight]]()
        for flight in fitted {
            if let last = chains.last?.last, last.range.upperBound == flight.range.lowerBound {
                chains[chains.count - 1].append(flight)
            } else {
                chains.append([flight])
            }
        }
        return chains.flatMap { solveChain($0, samples: samples, projector: projector) ?? $0 }
    }

    private func solveChain(_ chain: [FittedFlight], samples: [BallSample], projector: Projector) -> [FittedFlight]? {
        var equations = NormalEquations(size: 6 * chain.count)
        let focal = projector.camera.focalLength
        for (k, fitted) in chain.enumerated() {
            for index in fitted.accepted {
                equations.add(projector.rows(for: samples[index], since: fitted.flight.startTime), offset: 6 * k)
            }
        }
        // つなぎ目で、前の飛行の終わりと、次の飛行の始まりが同じ位置。
        let weight = continuityWeight * focal
        for k in chain.indices.dropLast() {
            let time = samples[chain[k].range.upperBound].time
            let dtA = time - chain[k].flight.startTime
            let dtB = time - chain[k + 1].flight.startTime
            for axis in 0..<3 {
                let fall = axis == 1 ? gravity / 2 * (dtA * dtA - dtB * dtB) : 0
                equations.add(
                    terms: [(6 * k + axis, weight), (6 * k + 3 + axis, weight * dtA), (6 * (k + 1) + axis, -weight), (6 * (k + 1) + 3 + axis, -weight * dtB)],
                    target: weight * fall
                )
            }
        }
        func flights(from solution: [Double]) -> [Flight] {
            chain.enumerated().map { k, fitted in
                var flight = fitted.flight
                flight.position = SIMD3(solution[6 * k], solution[6 * k + 1], solution[6 * k + 2])
                flight.velocity = SIMD3(solution[6 * k + 3], solution[6 * k + 4], solution[6 * k + 5])
                return flight
            }
        }
        /// 飛行 `k` の、時刻 `dt`（飛行の始まりから）での `axis`（0 が横、1 が高さ、2 が奥行き）の値を、`value` に寄せる式を足す。
        func pull(_ k: Int, axis: Int, dt: Double, to value: Double, weight: Double) {
            let fall = axis == 1 ? gravity / 2 * dt * dt : 0
            equations.add(terms: [(6 * k + axis, weight), (6 * k + 3 + axis, weight * dt)], target: weight * (value + fall))
        }
        func pullHeight(_ k: Int, dt: Double, to height: Double, weight: Double) {
            pull(k, axis: 1, dt: dt, to: height, weight: weight)
        }
        let bounds = [(0, boundaryGroundRange.x), (2, boundaryGroundRange.z)]
        guard var solution = equations.solve() else { return nil }
        // ありえない高さになったところだけ、見込みの式を足して解き直す（正しく当てはまっている飛行は動かさない）。
        // - 飛行の始まりと終わり（打つ、弾む）が、`boundaryHeightRange` の外。
        // - ネットをまたぐところが、ネットより低い（ラリーの球はネットを越える）。
        for _ in 0..<3 {
            var added = false
            for (k, flight) in flights(from: solution).enumerated() {
                let boundaryWeight = boundaryHeightWeight * focal
                for time in [flight.startTime, flight.endTime] where boundaryWeight > 0 {
                    let point = flight.position(at: time)
                    if !boundaryHeightRange.contains(point.y) {
                        let target = min(max(point.y, boundaryHeightRange.lowerBound), boundaryHeightRange.upperBound)
                        pullHeight(k, dt: time - flight.startTime, to: target, weight: boundaryWeight)
                        added = true
                    }
                    for (axis, limit) in bounds where abs(point[axis]) > limit {
                        pull(k, axis: axis, dt: time - flight.startTime, to: point[axis] > 0 ? limit : -limit, weight: boundaryWeight)
                        added = true
                    }
                }
                let netWeight = netClearanceWeight * focal
                guard netWeight > 0, abs(flight.velocity.z) > 1e-6 else { continue }
                let dt = -flight.position.z / flight.velocity.z
                guard dt > 0, flight.startTime + dt < flight.endTime, flight.position(at: flight.startTime + dt).y < netClearance else { continue }
                pullHeight(k, dt: dt, to: netTarget, weight: netWeight)
                added = true
            }
            guard added, let resolved = equations.solve() else { break }
            solution = resolved
        }
        var result = [FittedFlight]()
        for (fitted, flight) in zip(chain, flights(from: solution)) {
            let rms = rootMeanSquare(fitted.accepted.map { projector.error(of: flight, for: samples[$0]) })
            guard rms <= maximumError * joinedErrorScale, isPlausible(flight, until: flight.endTime) else { return nil }
            var updated = fitted
            updated.flight = flight
            result.append(updated)
        }
        return result
    }

    /// ネットの上を通る見込み。ネットをまたぐところの高さが `netClearance`（メートル）より低ければ、`netTarget` を通る式を
    /// 重さ `netClearanceWeight`（焦点距離に対する割合）で足す。0 なら使わない。ネットの高さは中央で 0.86 m、端で 0.91 m。
    public var netClearance = 0.95
    public var netTarget = 1.15
    public var netClearanceWeight = 0.2

    /// 続いている飛行を、まとめて当てはめ直すか。
    public var joinsFlights = true
    /// つなぎ目で位置を合わせる式の重さ（焦点距離に対する割合）。1 なら、つなぎ目の 1 m のずれを、その奥行きで写した画素のずれと
    /// 同じ重さで見る。
    public var continuityWeight = 1.0
    /// 飛行の始まりと終わり（打つ、弾む）の高さの範囲（メートル）。外に出たら、範囲の端へ寄せる式を、重さ
    /// `boundaryHeightWeight`（焦点距離に対する割合）で足す。0 なら使わない。
    public var boundaryHeightRange: ClosedRange<Double> = 0...2.0
    /// 飛行の始まりと終わりの、コートの中心からの横（x）と縦（z）の範囲（メートル）。選手が打つのは、コートの横 1.5 m、
    /// 後ろ 3 m まで、とみる。外に出たら、同じように範囲の端へ寄せる。
    public var boundaryGroundRange = (x: 3.048 + 1.5, z: 6.7056 + 3.0)
    public var boundaryHeightWeight = 0.05
    /// まとめて当てはめたとき、写った位置からの外れを、1 つずつのときの上限（`maximumError`）の何倍まで許すか。
    public var joinedErrorScale = 1.5

    /// `start` から、当てはまるあいだ飛行を伸ばす。最後に入れた点と、そのときの飛行と、当てはめに使った点を返す。当てはまらなければ nil。
    ///
    /// 最初の `minimumSamples` 点で当てはめ、そのあとは 1 点ずつ、今の飛行で見込んだ位置の近くにあれば入れて当てはめ直す。
    /// 見込みから外れた点は入れない（誤検出なら、そのまま飛ばす）。外れた点が `breakAfter` 続いたら（打球やバウンドで向きが
    /// 変わった）、そこで区切る。
    private func grow(from start: Int, samples: [BallSample], projector: Projector) -> (Int, Flight, [Int])? {
        let startTime = samples[start].time
        let first = Array(start..<(start + minimumSamples))
        guard zip(first, first.dropFirst()).allSatisfy({ samples[$1].time - samples[$0].time <= maximumGap }) else { return nil }
        var equations = NormalEquations()
        for index in first {
            equations.add(projector.rows(for: samples[index], since: startTime))
        }
        guard var flight = solve(equations, startTime: startTime) else { return nil }
        var accepted = first
        var rms = rootMeanSquare(accepted.map { projector.error(of: flight, for: samples[$0]) })
        guard rms <= maximumError, isPlausible(flight, until: samples[first[first.count - 1]].time) else { return nil }
        var misses = 0
        var last = first[first.count - 1]
        for index in (last + 1)..<max(last + 1, samples.count) {
            if samples[index].time - samples[last].time > maximumGap {
                break
            }
            let gate = max(gateFloor, gateScale * rms)
            var extended = equations
            extended.add(projector.rows(for: samples[index], since: startTime))
            guard projector.error(of: flight, for: samples[index]) <= gate,
                  let refit = solve(extended, startTime: startTime),
                  case let refitRMS = rootMeanSquare((accepted + [index]).map { projector.error(of: refit, for: samples[$0]) }),
                  refitRMS <= maximumError, isPlausible(refit, until: samples[index].time) else {
                misses += 1
                if misses >= breakAfter {
                    break
                }
                continue
            }
            equations = extended
            flight = refit
            rms = refitRMS
            accepted.append(index)
            last = index
            misses = 0
        }
        flight.endTime = samples[last].time
        return (last, flight, accepted)
    }

    /// 見込みの位置から、次の点がどれだけ外れてよいか（映像の幅に対する割合）。今の外れ（二乗平均）の `gateScale` 倍。
    /// ただし `gateFloor` 以上。
    public var gateScale = 3.0
    public var gateFloor = 0.003

    private func rootMeanSquare(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : (values.map { $0 * $0 }.reduce(0, +) / Double(values.count)).squareRoot()
    }

    private func solve(_ equations: NormalEquations, startTime: Double) -> Flight? {
        guard let solution = equations.solve() else { return nil }
        return Flight(
            startTime: startTime, position: SIMD3(solution[0], solution[1], solution[2]),
            velocity: SIMD3(solution[3], solution[4], solution[5]), endTime: startTime, gravity: gravity
        )
    }

    /// 飛行の始まりと終わりが、ありえる場所にあるか。
    private func isPlausible(_ flight: Flight, until endTime: Double) -> Bool {
        [flight.position, flight.position(at: endTime)].allSatisfy { point in
            heightRange.contains(point.y) && abs(point.x) <= groundRange.x && abs(point.z) <= groundRange.z
        }
    }
}

/// 3D の点を映像に写す式を、飛行の未知数（始まりの位置と速さ）について 1 次の式にする。
private struct Projector {
    let camera: CourtCamera
    let gravity: Double
    let rows: [SIMD3<Double>]
    let width: Double
    let height: Double

    let ballRadius: Double
    let depthWeight: Double

    init(camera: CourtCamera, gravity: Double, ballRadius: Double, depthWeight: Double) {
        self.camera = camera
        self.gravity = gravity
        self.ballRadius = ballRadius
        self.depthWeight = depthWeight
        let rotation = camera.rotation.transpose // 行を列として取り出すため。
        rows = [rotation.columns.0, rotation.columns.1, rotation.columns.2]
        width = Double(camera.imageSize.width)
        height = Double(camera.imageSize.height)
    }

    /// 1 点ぶんの式（x と y の 2 本）。写る式 f * カメラの x - 画素の x * カメラの z = 0 は、位置について 1 次。
    func rows(for sample: BallSample, since startTime: Double) -> [(coefficients: [Double], target: Double)] {
        let dt = sample.time - startTime
        let pixel = SIMD2((Double(sample.center.x) - 0.5) * width, (0.5 - Double(sample.center.y)) * height)
        let fall = SIMD3(0, -gravity / 2, 0)
        let shift = camera.translation
        var equations = [(rows[0], pixel.x, shift.x), (rows[1], pixel.y, shift.y)].map { axis, value, offset in
            let a = camera.focalLength * axis - value * rows[2]
            let constant = camera.focalLength * offset - value * shift.z
            return (coefficients: [a.x, a.y, a.z, a.x * dt, a.y * dt, a.z * dt], target: -constant - simd_dot(a, fall) * dt * dt)
        }
        // 写った大きさからの距離: カメラの z = f * 半径 / 写った半径（画素）。
        let radius = Double(sample.radius) * width
        if depthWeight > 0, radius > 0.5 {
            let depth = camera.focalLength * ballRadius / radius
            let a = rows[2] * depthWeight
            equations.append((
                coefficients: [a.x, a.y, a.z, a.x * dt, a.y * dt, a.z * dt],
                target: depthWeight * (depth - shift.z) - simd_dot(a, fall) * dt * dt
            ))
        }
        return equations
    }

    /// 写った位置からの外れ（映像の幅に対する割合）。
    func error(of flight: BallPlacement.Flight, for sample: BallSample) -> Double {
        guard let image = camera.project(flight.position(at: sample.time)) else { return .infinity }
        let dx = Double(image.x - sample.center.x)
        let dy = Double(image.y - sample.center.y) * height / width
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// 最小二乗の正規方程式（6 元）。点を足すたびに、行列とベクトルを足し込む。
private struct NormalEquations {
    private var matrix: [[Double]]
    private var vector: [Double]

    /// 未知数の数は `size`（飛行 1 つなら 6、つないだ飛行 K 個なら 6K）。
    init(size: Int = 6) {
        matrix = [[Double]](repeating: [Double](repeating: 0, count: size), count: size)
        vector = [Double](repeating: 0, count: size)
    }

    /// 式を足す。`offset` は、式の係数を置き始める未知数の番号（つないだ飛行の、何番目の飛行か）。
    mutating func add(_ rows: [(coefficients: [Double], target: Double)], offset: Int = 0) {
        for (coefficients, target) in rows {
            for (i, a) in coefficients.enumerated() where a != 0 {
                for (j, b) in coefficients.enumerated() where b != 0 {
                    matrix[offset + i][offset + j] += a * b
                }
                vector[offset + i] += a * target
            }
        }
    }

    /// 係数が、飛び飛びの未知数にかかる式を足す（`terms` は、未知数の番号と係数）。
    mutating func add(terms: [(Int, Double)], target: Double) {
        for (i, a) in terms {
            for (j, b) in terms {
                matrix[i][j] += a * b
            }
            vector[i] += a * target
        }
    }

    /// 部分ピボットのガウスの消去法で解く。解けない（行列が潰れている）ときは nil。
    func solve() -> [Double]? {
        var a = matrix
        var b = vector
        let size = b.count
        let scale = a.flatMap { $0 }.map(abs).max() ?? 0
        guard scale > 0 else { return nil }
        for column in 0..<size {
            guard let pivot = (column..<size).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }),
                  abs(a[pivot][column]) > scale * 1e-12 else { return nil }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)
            for row in (column + 1)..<size {
                let factor = a[row][column] / a[column][column]
                for index in column..<size {
                    a[row][index] -= factor * a[column][index]
                }
                b[row] -= factor * b[column]
            }
        }
        var x = [Double](repeating: 0, count: size)
        for row in stride(from: size - 1, through: 0, by: -1) {
            var sum = b[row]
            for index in (row + 1)..<size {
                sum -= a[row][index] * x[index]
            }
            x[row] = sum / a[row][row]
        }
        return x
    }
}
