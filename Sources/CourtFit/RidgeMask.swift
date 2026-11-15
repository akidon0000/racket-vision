import CoreGraphics
import simd

// `CourtLineModelSearch` の部品（候補の並べ替え、四角形の計算、画面の直線、白線の芯の画像）。

struct ScoredMatrix {
    let matrix: simd_double3x3
    let score: Double
}

func insertScored(_ item: ScoredMatrix, into list: inout [ScoredMatrix], limit: Int) {
    let index = list.firstIndex { $0.score < item.score } ?? list.count
    list.insert(item, at: index)
    if list.count > limit {
        list.removeLast()
    }
}

/// 点数の高い順に、コートの四隅が互いに離れているものだけを選ぶ。
func distinctCourtCandidates(_ sorted: [ScoredMatrix], limit: Int) -> [ScoredMatrix] {
    let corners = CourtModel.corners.map { CourtModel.pickleball.position(of: $0) }
    func projected(_ matrix: simd_double3x3) -> [SIMD2<Double>] {
        corners.map { corner in
            let value = matrix * SIMD3(corner.x, corner.y, 1)
            return SIMD2(value.x / value.z, value.y / value.z)
        }
    }
    var chosen = [(item: ScoredMatrix, corners: [SIMD2<Double>])]()
    for item in sorted {
        let points = projected(item.matrix)
        let duplicate = chosen.contains { other in
            zip(other.corners, points).allSatisfy { simd_length($0 - $1) < 12 }
        }
        if !duplicate {
            chosen.append((item, points))
        }
        if chosen.count >= limit {
            break
        }
    }
    return chosen.map(\.item)
}

func courtIndexPairs(_ count: Int) -> [(Int, Int)] {
    var result = [(Int, Int)]()
    for first in 0..<count {
        for second in (first + 1)..<count {
            result.append((first, second))
        }
    }
    return result
}

func signedQuadArea(_ quad: [SIMD2<Double>]) -> Double {
    var sum = 0.0
    for index in quad.indices {
        let current = quad[index]
        let next = quad[(index + 1) % quad.count]
        sum += current.x * next.y - next.x * current.y
    }
    return sum / 2
}

func isConvexQuad(_ quad: [SIMD2<Double>]) -> Bool {
    var positive = 0
    var negative = 0
    for index in quad.indices {
        let first = quad[(index + 1) % 4] - quad[index]
        let second = quad[(index + 2) % 4] - quad[(index + 1) % 4]
        let cross = first.x * second.y - first.y * second.x
        if cross > 0 {
            positive += 1
        } else if cross < 0 {
            negative += 1
        }
    }
    return positive == 4 || negative == 4
}

/// 図面の長方形（x0〜x1、y0〜y1）を、画面の四角形（左手前、右手前、右奥、左奥の順）へ写す変換。
func rectangleToQuad(x0: Double, x1: Double, y0: Double, y1: Double, quad: [SIMD2<Double>]) -> simd_double3x3? {
    let p0 = quad[0]
    let p1 = quad[1]
    let p2 = quad[2]
    let p3 = quad[3]
    let d1 = p1 - p2
    let d2 = p3 - p2
    let sum = p0 - p1 + p2 - p3
    let denominator = d1.x * d2.y - d2.x * d1.y
    guard abs(denominator) > 1e-9 else { return nil }
    let g = (sum.x * d2.y - d2.x * sum.y) / denominator
    let h = (d1.x * sum.y - sum.x * d1.y) / denominator
    // 単位の正方形から四角形への変換。
    let square = simd_double3x3(rows: [
        SIMD3(p1.x - p0.x + g * p1.x, p3.x - p0.x + h * p3.x, p0.x),
        SIMD3(p1.y - p0.y + g * p1.y, p3.y - p0.y + h * p3.y, p0.y),
        SIMD3(g, h, 1)
    ])
    // 図面の長方形から、単位の正方形への変換。
    let width = x1 - x0
    let height = y1 - y0
    let toSquare = simd_double3x3(rows: [
        SIMD3(1 / width, 0, -x0 / width),
        SIMD3(0, 1 / height, -y0 / height),
        SIMD3(0, 0, 1)
    ])
    return square * toSquare
}

/// 画面の上の直線。`normal · p = offset`。
struct ImageLine {
    var normal: SIMD2<Double>
    var offset: Double

    /// 直線から `tolerance` 画素以内の点に、当てはめ直す（主成分）。点が少ないときは nil。
    func fitted(to points: [SIMD2<Double>], within tolerance: Double) -> ImageLine? {
        var count = 0.0
        var mean = SIMD2<Double>(0, 0)
        for point in points where abs(simd_dot(normal, point) - offset) <= tolerance {
            count += 1
            mean += point
        }
        guard count >= 20 else { return nil }
        mean /= count
        var xx = 0.0
        var xy = 0.0
        var yy = 0.0
        for point in points where abs(simd_dot(normal, point) - offset) <= tolerance {
            let delta = point - mean
            xx += delta.x * delta.x
            xy += delta.x * delta.y
            yy += delta.y * delta.y
        }
        // 散らばりのいちばん大きい向きが、直線の向き。
        let angle = 0.5 * atan2(2 * xy, xx - yy)
        let fittedNormal = SIMD2(-sin(angle), cos(angle))
        return ImageLine(normal: fittedNormal, offset: simd_dot(fittedNormal, mean))
    }

    /// 直線の上（1.5 画素以内）の点が、途切れずに続くいちばん長い区間の長さ（画素）。8 画素までの切れ目は、続いているとみなす。
    func longestRun(in points: [SIMD2<Double>]) -> Double {
        let direction = SIMD2(-normal.y, normal.x)
        var positions = [Double]()
        for point in points where abs(simd_dot(normal, point) - offset) <= 1.5 {
            positions.append(simd_dot(direction, point))
        }
        positions.sort()
        guard var start = positions.first else { return 0 }
        var previous = start
        var best = 0.0
        for position in positions.dropFirst() {
            if position - previous > 8 {
                best = max(best, previous - start)
                start = position
            }
            previous = position
        }
        return max(best, previous - start)
    }

    /// 2 本の直線の交点。平行に近いとき、画面から大きく外れるときは nil。
    func intersection(_ other: ImageLine, in size: CGSize) -> SIMD2<Double>? {
        let determinant = normal.x * other.normal.y - normal.y * other.normal.x
        guard abs(determinant) > 0.15 else { return nil }
        let x = (offset * other.normal.y - other.offset * normal.y) / determinant
        let y = (normal.x * other.offset - other.normal.x * offset) / determinant
        let width = Double(size.width)
        let height = Double(size.height)
        guard x >= -width, x <= 2 * width, y >= -height, y <= 2 * height else { return nil }
        return SIMD2(x, y)
    }

    /// 画面の中で、ほぼ同じ直線か（画面の中央の近くで 3 画素、向きで 2 度以内）。
    func isClose(to other: ImageLine, size: CGSize) -> Bool {
        let cosine = abs(simd_dot(normal, other.normal))
        guard cosine > cos(2 * Double.pi / 180) else { return false }
        let center = SIMD2(Double(size.width) / 2, Double(size.height) / 2)
        let sign = simd_dot(normal, other.normal) >= 0 ? 1.0 : -1.0
        let first = simd_dot(normal, center) - offset
        let second = sign * (simd_dot(other.normal, center) - other.offset)
        return abs(first - second) < 3
    }
}

/// 図面の線の上の点（同次座標）。
struct CourtSamples {
    let points: [SIMD3<Double>]

    init(model: CourtModel, pointsPerLine: Int) {
        var points = [SIMD3<Double>]()
        for line in CourtModel.lines {
            let start = model.position(of: line.start)
            let end = model.position(of: line.end)
            for index in 0..<pointsPerLine {
                let point = start + (end - start) * (Double(index) / Double(pointsPerLine - 1))
                points.append(SIMD3(point.x, point.y, 1))
            }
        }
        self.points = points
    }
}

/// 白線の芯があるか無いかの画像。近くに芯があるかを、1 回の参照で調べられるように、広げたものも持つ。
struct RidgeMask {
    let width: Int
    let height: Int
    /// 添字は、広げた画素の数（0、1、2）。
    private let dilated: [[UInt8]]
    /// 芯の画素の位置。
    let points: [SIMD2<Double>]

    var size: CGSize { CGSize(width: width, height: height) }

    init(_ ridge: EdgeMap, threshold: Float) {
        width = ridge.width
        height = ridge.height
        var raw = [UInt8](repeating: 0, count: width * height)
        for index in raw.indices where ridge.values[index] >= threshold {
            raw[index] = 1
        }
        let mask = RidgeMask.straightOnly(raw, width: width, height: height)
        var points = [SIMD2<Double>]()
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] != 0 {
                points.append(SIMD2(Double(x), Double(y)))
            }
        }
        let once = RidgeMask.dilate(mask, width: width, height: height)
        dilated = [mask, once, RidgeMask.dilate(once, width: width, height: height)]
        self.points = points
    }

    /// 芯の画素だけを 1 にした画像（ハフ変換に渡す）。
    var edgeMap: EdgeMap? {
        EdgeMap(width: width, height: height, values: dilated[0].map { Float($0) })
    }

    /// まっすぐ続いている画素だけを残す。どれかの向きで、前後 15 画素のほとんどが芯の上にあるものを残す。
    /// 文字、観客、服の模様は、短いか曲がっているので消える。
    private static func straightOnly(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        let near = dilate(mask, width: width, height: height)
        let reach = 15
        let directions = (0..<16).map { index -> (Double, Double) in
            let angle = Double(index) * .pi / 16
            return (cos(angle), sin(angle))
        }
        // 向きごとの、前後の画素の位置のずれ。
        let offsets = directions.map { direction in
            (-reach...reach).map { step in
                (Int((Double(step) * direction.0).rounded()), Int((Double(step) * direction.1).rounded()))
            }
        }
        let needed = Int(Double(2 * reach + 1) * 0.9)
        var result = [UInt8](repeating: 0, count: width * height)
        for y in reach..<(height - reach) {
            for x in reach..<(width - reach) where mask[y * width + x] != 0 {
                for steps in offsets {
                    var count = 0
                    for (dx, dy) in steps {
                        count += Int(near[(y + dy) * width + x + dx])
                    }
                    if count >= needed {
                        result[y * width + x] = 1
                        break
                    }
                }
            }
        }
        return result
    }

    /// 図面の線の上の点のうち、近く（`radius` 画素以内）に白線の芯がある割合。
    /// 画面の外の点が多すぎるときは nil。外の点は、一部を外れとして数える（図面を大きく当てはめて逃げるのを防ぐ）。
    func support(of matrix: simd_double3x3, samples: CourtSamples, radius: Int) -> Double? {
        let mask = dilated[min(max(radius, 0), 2)]
        var inside = 0
        var hits = 0
        for sample in samples.points {
            let value = matrix * sample
            guard value.z > 1e-9 else { continue }
            let x = Int((value.x / value.z).rounded())
            let y = Int((value.y / value.z).rounded())
            guard x >= 0, y >= 0, x < width, y < height else { continue }
            inside += 1
            hits += Int(mask[y * width + x])
        }
        let total = samples.points.count
        guard Double(inside) >= 0.35 * Double(total) else { return nil }
        return Double(hits) / max(Double(inside), 0.6 * Double(total))
    }

    /// 図面の線 8 本のうち、白線の芯が見えている線の数。画面の中にある点の半分以上で近く（1 画素以内）に芯があり、
    /// 4 分の 1 以上で「線として」（芯の外側の両脇に、別の芯が無い）見えていること。
    /// 観客席や看板の文字のように芯が細かく散らばっている場所は、どこに線を引いても近くに芯があるので、両脇で弾く。
    /// 画面の中に 3 割も入っていない線は数えない。
    func supportedLineCount(of matrix: simd_double3x3, model: CourtModel) -> Int {
        CourtModel.lines.filter { line in
            let start = model.position(of: line.start)
            let end = model.position(of: line.end)
            let points = 30
            let pixels = (0..<points).map { index -> SIMD2<Double>? in
                let court = start + (end - start) * (Double(index) / Double(points - 1))
                let value = matrix * SIMD3(court.x, court.y, 1)
                return value.z > 1e-9 ? SIMD2(value.x / value.z, value.y / value.z) : nil
            }
            var inside = 0
            var hits = 0
            var cleanHits = 0
            for index in pixels.indices {
                guard let pixel = pixels[index], isInside(pixel) else { continue }
                inside += 1
                guard value(dilated[1], at: pixel) else { continue }
                hits += 1
                let neighbor = pixels[index < points - 1 ? index + 1 : index - 1]
                if let neighbor, hasClearSides(at: pixel, along: neighbor - pixel) {
                    cleanHits += 1
                }
            }
            return Double(inside) >= 0.3 * Double(points) && Double(hits) >= 0.5 * Double(inside)
                && Double(cleanHits) >= 0.25 * Double(inside)
        }.count
    }

    private func isInside(_ pixel: SIMD2<Double>) -> Bool {
        pixel.x >= 0 && pixel.y >= 0 && pixel.x < Double(width) && pixel.y < Double(height)
    }

    /// 線の両脇に芯が無いか。線の芯の太さを測り、その外側 4 画素に芯が無ければ、両脇が空いているとみなす。
    private func hasClearSides(at pixel: SIMD2<Double>, along direction: SIMD2<Double>) -> Bool {
        let length = simd_length(direction)
        guard length > 1e-9 else { return false }
        let normal = SIMD2(-direction.y, direction.x) / length
        return [1.0, -1.0].allSatisfy { sign in
            var edge = 0.0
            // 芯の縁まで進む（太い線でも 12 画素まで）。
            while edge < 12, value(dilated[1], at: pixel + sign * (edge + 1) * normal) {
                edge += 1
            }
            return (1...4).allSatisfy { gap in !value(dilated[0], at: pixel + sign * (edge + Double(gap)) * normal) }
        }
    }

    private func value(_ mask: [UInt8], at pixel: SIMD2<Double>) -> Bool {
        let x = Int(pixel.x.rounded())
        let y = Int(pixel.y.rounded())
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return mask[y * width + x] != 0
    }

    private static func dilate(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        var result = mask
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) where mask[y * width + x] == 0 {
                let index = y * width + x
                let above = mask[index - width - 1] | mask[index - width] | mask[index - width + 1]
                let beside = mask[index - 1] | mask[index + 1]
                let below = mask[index + width - 1] | mask[index + width] | mask[index + width + 1]
                result[index] = above | beside | below
            }
        }
        return result
    }
}
