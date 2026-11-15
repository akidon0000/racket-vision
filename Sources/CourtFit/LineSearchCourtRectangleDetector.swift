import CoreFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

/// 水平に近い直線（ベースラインなど）と、垂直に近い直線（サイドラインなど）の組から四角形を作り、白線の支持率で採点する。
///
/// 1. エッジの画像から、ハフ変換で直線を取る。
/// 2. 水平に近いものと垂直に近いものを、それぞれ上位から数本ずつ選ぶ。
/// 3. 2 本ずつの組で四隅を作り、カメラとして自然で、白線の支持率が高いものを残す。
/// 結果は、支持率の高い順。
public struct LineSearchCourtRectangleDetector: CourtRectangleDetector {
    public let method = CourtDetectionMethod.lineSearch
    /// エッジとみなす強さ（0〜1）。
    public var edgeThreshold: Float
    /// 水平・垂直の判定の許容（度）。水平は 90 度から、垂直は 0 度か 180 度から、この角度以内。
    public var orientationTolerance: Double
    /// 水平・垂直それぞれで、組にする直線の数の上限。
    public var candidateLinesPerDirection: Int
    /// 返す四角形の数の上限。
    public var maximumQuads: Int
    public var model: CourtModel
    public var plausibility: CameraPlausibility

    public init(
        edgeThreshold: Float = 0.5,
        orientationTolerance: Double = 35,
        candidateLinesPerDirection: Int = 12,
        maximumQuads: Int = 2,
        model: CourtModel = .pickleball,
        plausibility: CameraPlausibility = CameraPlausibility()
    ) {
        self.edgeThreshold = edgeThreshold
        self.orientationTolerance = orientationTolerance
        self.candidateLinesPerDirection = candidateLinesPerDirection
        self.maximumQuads = maximumQuads
        self.model = model
        self.plausibility = plausibility
    }

    public func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> DetectionOutcome {
        let started = CFAbsoluteTimeGetCurrent()
        let imageSize = uprightImageSize(of: pixelBuffer, orientation: orientation)
        let parameters = [
            "エッジの強さ \(String(format: "%.2f", edgeThreshold))",
            "直線の向きの許容 \(String(format: "%.0f", orientationTolerance))度",
            "組にする直線 各 \(candidateLinesPerDirection) 本、返す数 \(maximumQuads)"
        ]
        // 画素のまま使えるのは `.up` のときだけ。
        guard orientation == .up, let edges = EdgeMap(bgraPixelBuffer: pixelBuffer) else {
            return DetectionOutcome(
                method: method, quads: [], confidence: nil,
                durationMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000,
                imageSize: imageSize, parameters: parameters
            )
        }

        let lines = houghLines(edges, threshold: edgeThreshold)
        let horizontal = lines.filter { isNear($0.theta, 90, within: orientationTolerance) }
            .prefix(candidateLinesPerDirection)
        let vertical = lines.filter { isNear($0.theta, 0, within: orientationTolerance) || isNear($0.theta, 180, within: orientationTolerance) }
            .prefix(candidateLinesPerDirection)

        let scored = scoredCandidates(horizontal: Array(horizontal), vertical: Array(vertical), edges: edges, imageSize: imageSize, pixelBuffer: pixelBuffer)
        let chosen = nonOverlapping(scored, limit: maximumQuads).map { refined($0, edges: edges, imageSize: imageSize) }
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
        return DetectionOutcome(
            method: method,
            quads: chosen.map(\.quad),
            confidence: chosen.first.map { Float($0.support) },
            durationMilliseconds: elapsed,
            imageSize: imageSize,
            parameters: parameters
        )
    }

    /// 水平と垂直の直線の組から四隅を作り、採点して、点数の高い順に並べる。
    private func scoredCandidates(
        horizontal: [HoughLine],
        vertical: [HoughLine],
        edges: EdgeMap,
        imageSize: CGSize,
        pixelBuffer: CVPixelBuffer
    ) -> [Candidate] {
        let feet = humanFeet(in: pixelBuffer)
        var scored = [Candidate]()
        for (top, bottom) in pairs(horizontal) {
            for (left, right) in pairs(vertical) {
                guard let quad = courtQuad(top: top, bottom: bottom, left: left, right: right, size: edges.size),
                      let best = bestSupport(of: quad, edges: edges, imageSize: imageSize) else { continue }
                scored.append(Candidate(
                    quad: quad,
                    support: best.support,
                    quarterTurned: best.quarterTurned,
                    rank: best.support * feetFactor(quad, feet: feet)
                ))
            }
        }
        return scored.sorted { $0.rank > $1.rank }
    }

    /// 両方の向きで、白線の支持率が高いほうを返す。どちらも求まらなければ nil。
    private func bestSupport(of quad: DetectedQuad, edges: EdgeMap, imageSize: CGSize) -> (support: Double, quarterTurned: Bool)? {
        [false, true].compactMap { quarterTurned -> (support: Double, quarterTurned: Bool)? in
            guard let homography = Homography(courtOutline: quad, imageSize: imageSize, quarterTurned: quarterTurned, model: model),
                  let estimate = CameraEstimate(homography: homography, imageSize: imageSize),
                  plausibility.accepts(estimate, imageSize: imageSize),
                  let support = homography.lineSupport(in: edges, model: model) else { return nil }
            return (support, quarterTurned)
        }.max { $0.support < $1.support }
    }

    /// 選んだ四隅を、白線の位置合わせ（`aligned`）で直す。直したほうの支持率が高いときだけ採用する。
    private func refined(_ candidate: Candidate, edges: EdgeMap, imageSize: CGSize) -> Candidate {
        guard let initial = Homography(courtOutline: candidate.quad, imageSize: imageSize, quarterTurned: candidate.quarterTurned, model: model),
              let inverse = initial.inverse,
              let result = aligned(edges, from: initial, model: model),
              let refinedSupport = result.homography.lineSupport(in: edges, model: model),
              refinedSupport > candidate.support else {
            return candidate
        }
        // 元の四隅を、図面の上の点に戻し、直した変換で画面に写し直す。
        func move(_ corner: CGPoint) -> CGPoint {
            let pixel = SIMD2(Double(corner.x) * Double(imageSize.width), (1 - Double(corner.y)) * Double(imageSize.height))
            guard let court = inverse.project(pixel), let moved = result.homography.project(court) else { return corner }
            return CGPoint(x: moved.x / Double(imageSize.width), y: 1 - moved.y / Double(imageSize.height))
        }
        let quad = DetectedQuad(
            topLeft: move(candidate.quad.topLeft),
            topRight: move(candidate.quad.topRight),
            bottomRight: move(candidate.quad.bottomRight),
            bottomLeft: move(candidate.quad.bottomLeft)
        )
        return Candidate(quad: quad, support: refinedSupport, quarterTurned: candidate.quarterTurned, rank: candidate.rank)
    }

    private func isNear(_ theta: Double, _ target: Double, within tolerance: Double) -> Bool {
        abs(theta - target) <= tolerance
    }
}

/// ハフ変換の直線。`theta` は度（0〜180）、`rho` は画素。直線は `x cos θ + y sin θ = ρ`（画素の座標、左上が原点）。
struct HoughLine {
    let theta: Double
    let rho: Double
    let votes: Int
}

/// ハフ変換で、票の多い直線を取る。近い直線（角度 4 度、距離 8px 以内）は、一番票の多いものだけ残す。
func houghLines(_ edges: EdgeMap, threshold: Float) -> [HoughLine] {
    let angleBins = 180
    // 票が少ない直線は、コートの線ではない（人や背景の断片）とみなして捨てる。
    let minimumVotes = 60
    let diagonal = Int(Double(edges.width * edges.width + edges.height * edges.height).squareRoot().rounded(.up))
    let cosines = (0..<angleBins).map { cos(Double($0) * .pi / 180) }
    let sines = (0..<angleBins).map { sin(Double($0) * .pi / 180) }
    var accumulator = [Int](repeating: 0, count: angleBins * (2 * diagonal + 1))
    // 点を間引いて（2 画素ごと）、速さを保つ。直線は長いので、間引いても票は十分残る。
    for y in stride(from: 0, to: edges.height, by: 2) {
        for x in stride(from: 0, to: edges.width, by: 2) where edges.values[y * edges.width + x] >= threshold {
            for angle in 0..<angleBins {
                let rho = Int((Double(x) * cosines[angle] + Double(y) * sines[angle]).rounded()) + diagonal
                accumulator[angle * (2 * diagonal + 1) + rho] += 1
            }
        }
    }

    var peaks = [(angle: Int, rho: Int, votes: Int)]()
    for angle in 0..<angleBins {
        for rho in 0...(2 * diagonal) {
            let votes = accumulator[angle * (2 * diagonal + 1) + rho]
            if votes >= minimumVotes {
                peaks.append((angle, rho, votes))
            }
        }
    }
    peaks.sort { $0.votes > $1.votes }

    var chosen = [HoughLine]()
    for peak in peaks.prefix(4000) {
        let theta = Double(peak.angle)
        let rho = Double(peak.rho - diagonal)
        let nearExisting = chosen.contains { line in
            let angleGap = min(abs(line.theta - theta), 180 - abs(line.theta - theta))
            return angleGap <= 4 && abs(line.rho - rho) <= 8
        }
        if !nearExisting {
            chosen.append(HoughLine(theta: theta, rho: rho, votes: peak.votes))
        }
        if chosen.count >= 300 {
            break
        }
    }
    return chosen
}

private extension EdgeMap {
    var size: CGSize { CGSize(width: width, height: height) }
}

/// 候補の四隅、白線の支持率、採った向き。
struct Candidate {
    var quad: DetectedQuad
    var support: Double
    var quarterTurned: Bool
    /// 並べ替えに使う点数（支持率に、足元の入る割合で重みを掛けたもの）。
    var rank: Double
}

/// 人の足元（人の枠の下の真ん中）の位置。正規化座標（左下が原点）。人が見つからないときは空。
private func humanFeet(in buffer: CVPixelBuffer) -> [CGPoint] {
    let request = VNDetectHumanRectanglesRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
    guard (try? handler.perform([request])) != nil else { return [] }
    let observations: [VNHumanObservation] = request.results ?? []
    return observations.map { CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.minY) }
}

/// 足元の入る割合で、点数に掛ける重み。人がいないときは 1（何も変えない）。
/// 人がいるのに足元が 1 人も入らない四角形は、半分に下げる（人の立つ場所はコートの中のことが多い）。
private func feetFactor(_ quad: DetectedQuad, feet: [CGPoint]) -> Double {
    guard !feet.isEmpty else { return 1 }
    let inside = feet.filter { pointInQuad($0, quad) }.count
    return 0.5 + 0.5 * Double(inside) / Double(feet.count)
}

private func pointInQuad(_ point: CGPoint, _ quad: DetectedQuad) -> Bool {
    let corners = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
    var signs = Set<Bool>()
    for index in corners.indices {
        let a = corners[index]
        let b = corners[(index + 1) % 4]
        let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
        signs.insert(cross >= 0)
    }
    return signs.count == 1
}

private func pairs<T>(_ items: [T]) -> [(T, T)] {
    var result = [(T, T)]()
    for i in items.indices {
        for j in items.indices where j > i {
            result.append((items[i], items[j]))
        }
    }
    return result
}

/// 水平の 2 本（上と下）と、垂直の 2 本（左と右）から四隅を作る。順序が合わないもの、画面から大きく外れるものは nil。
private func courtQuad(top: HoughLine, bottom: HoughLine, left: HoughLine, right: HoughLine, size: CGSize) -> DetectedQuad? {
    let centerX = Double(size.width) / 2
    let centerY = Double(size.height) / 2
    // 水平の線は画面の中央の x での y で、上下を決める。垂直の線は中央の y での x で、左右を決める。
    let (upper, lower) = yAtCenter(top, centerX) <= yAtCenter(bottom, centerX) ? (top, bottom) : (bottom, top)
    let (leftLine, rightLine) = xAtCenter(left, centerY) <= xAtCenter(right, centerY) ? (left, right) : (right, left)

    guard let topLeft = intersection(upper, leftLine),
          let topRight = intersection(upper, rightLine),
          let bottomRight = intersection(lower, rightLine),
          let bottomLeft = intersection(lower, leftLine) else { return nil }
    let corners = [topLeft, topRight, bottomRight, bottomLeft]
    let margin = 0.2
    let inside = corners.allSatisfy {
        $0.x >= -margin * size.width && $0.x <= (1 + margin) * size.width
            && $0.y >= -margin * size.height && $0.y <= (1 + margin) * size.height
    }
    guard inside, topLeft.y < bottomLeft.y, topRight.y < bottomRight.y, topLeft.x < topRight.x, bottomLeft.x < bottomRight.x else {
        return nil
    }
    // DetectedQuad は左下が原点の正規化座標。
    func normalized(_ point: SIMD2<Double>) -> CGPoint {
        CGPoint(x: point.x / Double(size.width), y: 1 - point.y / Double(size.height))
    }
    return DetectedQuad(
        topLeft: normalized(topLeft),
        topRight: normalized(topRight),
        bottomRight: normalized(bottomRight),
        bottomLeft: normalized(bottomLeft)
    )
}

private func yAtCenter(_ line: HoughLine, _ x: Double) -> Double {
    let radians = line.theta * .pi / 180
    return (line.rho - x * cos(radians)) / sin(radians)
}

private func xAtCenter(_ line: HoughLine, _ y: Double) -> Double {
    let radians = line.theta * .pi / 180
    return (line.rho - y * sin(radians)) / cos(radians)
}

private func intersection(_ first: HoughLine, _ second: HoughLine) -> SIMD2<Double>? {
    let a = first.theta * .pi / 180
    let b = second.theta * .pi / 180
    let determinant = cos(a) * sin(b) - sin(a) * cos(b)
    guard abs(determinant) > 0.2 else { return nil }
    let x = (first.rho * sin(b) - second.rho * sin(a)) / determinant
    let y = (cos(a) * second.rho - cos(b) * first.rho) / determinant
    return SIMD2(x, y)
}

/// 採点の順に、外接矩形の重なりが大きくないものを `limit` 件まで選ぶ。
private func nonOverlapping(_ scored: [Candidate], limit: Int) -> [Candidate] {
    var chosen = [Candidate]()
    for item in scored {
        guard chosen.count < limit else { break }
        let overlaps = chosen.contains { overlapRatio($0.quad, item.quad) > 0.3 }
        if !overlaps {
            chosen.append(item)
        }
    }
    return chosen
}

private func overlapRatio(_ first: DetectedQuad, _ second: DetectedQuad) -> CGFloat {
    let a = boundingBox(first)
    let b = boundingBox(second)
    let intersection = a.intersection(b)
    guard !intersection.isNull else { return 0 }
    let intersectionArea = intersection.width * intersection.height
    let unionArea = a.width * a.height + b.width * b.height - intersectionArea
    return unionArea > 0 ? intersectionArea / unionArea : 0
}

private func boundingBox(_ quad: DetectedQuad) -> CGRect {
    let xs = quad.corners.map(\.x)
    let ys = quad.corners.map(\.y)
    let minX = xs.min() ?? 0
    let minY = ys.min() ?? 0
    return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
}
