import CoreGraphics
import simd

/// 図面を当てはめた結果。`homography` は、図面（メートル）から、白線の芯の画像の画素への変換。
public struct CourtFit: Equatable, Sendable {
    public var homography: Homography
    /// 図面の線の上に、白線の芯がある割合（0〜1）。
    public var support: Double

    /// コートの外周の四隅（正規化座標、左下が原点）。`size` は、白線の芯の画像の大きさ。
    public func outline(in size: CGSize, model: CourtModel = .pickleball) -> DetectedQuad? {
        let corners: [CourtKeypoint] = [.farLeftCorner, .farRightCorner, .nearRightCorner, .nearLeftCorner]
        let points = corners.compactMap { corner -> CGPoint? in
            guard let pixel = homography.project(model.position(of: corner)) else { return nil }
            return CGPoint(x: pixel.x / Double(size.width), y: 1 - pixel.y / Double(size.height))
        }
        guard points.count == 4 else { return nil }
        return DetectedQuad(topLeft: points[0], topRight: points[1], bottomRight: points[2], bottomLeft: points[3])
    }
}

/// 白線の芯の画像から、図面（線 8 本）がいちばんよく重なる変換を探す。
///
/// 1. ハフ変換で直線を取り、白線の芯の画素に当てはめ直す。
/// 2. 直線を 2 本ずつ 2 組選び、図面の横の線（ベースライン、キッチンの線）と縦の線（サイドライン、センターライン）の
///    どれに当たるかを総当たりする。外周の 4 本が全部見えていなくても、見えている線の組で変換が決まる。
/// 3. カメラとしてありえる変換だけを残し、図面の線 8 本の上に白線の芯がある割合で採点する。
/// 4. 上位を、線への位置合わせ（`aligned`）で直して、いちばん点数の高いものを返す。
public struct CourtLineModelSearch: Sendable {
    public var model: CourtModel
    public var plausibility: CameraPlausibility
    /// 組にする直線の数の上限。
    public var maximumLines: Int
    /// 白線の芯とみなす強さ（0〜1）。
    public var ridgeThreshold: Float
    /// この支持率に届かない結果は、返さない。
    public var minimumSupport: Double
    /// 位置合わせで直す候補の数。
    public var refinedCandidates: Int

    /// 見えているとみなす線（8 本のうち）の下限。
    public var minimumSupportedLines = 5
    /// 向き（15 度ごと）ごとに選ぶ直線の上限。
    public var maximumLinesPerDirection = 6
    /// ハフ変換から取る直線の数（この中から、続く長さの順に `maximumLines` 本を選ぶ）。
    public var houghCandidates = 70

    public init(
        model: CourtModel = .pickleball,
        plausibility: CameraPlausibility = CameraPlausibility(),
        maximumLines: Int = 18,
        ridgeThreshold: Float = 0.3,
        minimumSupport: Double = 0.55,
        refinedCandidates: Int = 8
    ) {
        self.model = model
        self.plausibility = plausibility
        self.maximumLines = maximumLines
        self.ridgeThreshold = ridgeThreshold
        self.minimumSupport = minimumSupport
        self.refinedCandidates = refinedCandidates
    }

    /// 前の結果が無いときの探索。見つからなければ nil。
    public func search(_ ridge: EdgeMap) -> CourtFit? {
        let mask = RidgeMask(ridge, threshold: ridgeThreshold)
        let lines = fittedLines(ridge, mask: mask)
        let coarse = CourtSamples(model: model, pointsPerLine: 12)
        var best = [ScoredMatrix]()
        forEachHypothesis(lines: lines, size: mask.size) { matrix in
            guard let support = mask.support(of: matrix, samples: coarse, radius: 2) else { return }
            let score = support * sizeFactor(matrix, size: mask.size)
            if best.count >= 60, score <= (best.last?.score ?? 0) {
                return
            }
            guard isPlausible(matrix, size: mask.size) else { return }
            insertScored(ScoredMatrix(matrix: matrix, score: score), into: &best, limit: 60)
        }
        let distinct = distinctCourtCandidates(best, limit: refinedCandidates)
        return distinct.compactMap { refine(Homography(matrix: $0.matrix), ridge: ridge, mask: mask) }
            .filter { isAccepted($0, mask: mask) }
            .max {
                $0.support * sizeFactor($0.homography.matrix, size: mask.size) < $1.support * sizeFactor($1.homography.matrix, size: mask.size)
            }
    }

    /// 大きく写っているコートほど大きい重み（0.6〜1）。隣や奥のコートより、カメラが向いているコートを選ぶため。
    private func sizeFactor(_ matrix: simd_double3x3, size: CGSize) -> Double {
        var corners = [SIMD2<Double>]()
        for corner in CourtModel.corners {
            let position = model.position(of: corner)
            let value = matrix * SIMD3(position.x, position.y, 1)
            guard value.z > 1e-9 else { return 0.6 }
            corners.append(SIMD2(value.x / value.z, value.y / value.z))
        }
        let fraction = abs(signedQuadArea(corners)) / (Double(size.width) * Double(size.height))
        return 0.6 + 0.4 * min(1, fraction / 0.12)
    }

    /// 前のフレームの結果から出発して、今のフレームに合わせ直す。合わなくなっていたら nil。
    public func track(_ ridge: EdgeMap, from previous: Homography) -> CourtFit? {
        let mask = RidgeMask(ridge, threshold: ridgeThreshold)
        guard let fit = refine(previous, ridge: ridge, mask: mask), isAccepted(fit, mask: mask) else { return nil }
        return fit
    }

    /// 返してよい結果か。支持率が下限以上で、図面の線のうち `minimumSupportedLines` 本以上が見えていること。
    private func isAccepted(_ fit: CourtFit, mask: RidgeMask) -> Bool {
        fit.support >= minimumSupport && mask.supportedLineCount(of: fit.homography.matrix, model: model) >= minimumSupportedLines
    }

    /// まっすぐ続く白線の芯だけを残した画像（確認用）。
    func straightRidge(_ ridge: EdgeMap) -> EdgeMap? {
        RidgeMask(ridge, threshold: ridgeThreshold).edgeMap
    }

    /// 探索に使う直線（確認用）。法線と、原点からの距離。
    func candidateLines(_ ridge: EdgeMap) -> [(normal: SIMD2<Double>, offset: Double)] {
        fittedLines(ridge, mask: RidgeMask(ridge, threshold: ridgeThreshold)).map { ($0.normal, $0.offset) }
    }

    /// 縮めた画像で求めた結果を、元の大きさの白線の芯（`fullRidge`、`scale` 倍）で合わせ直す。
    /// 合わせ直した変換は、元の大きさの画素への変換。悪くなったときは、元の結果を拡大したものを返す。
    public func polish(_ fit: CourtFit, fullRidge: EdgeMap, scale: Double) -> CourtFit {
        let enlarge = simd_double3x3(diagonal: SIMD3(scale, scale, 1))
        let start = Homography(matrix: enlarge * fit.homography.matrix)
        var current = start
        for _ in 0..<2 {
            guard let result = aligned(fullRidge, from: current, model: model) else { break }
            current = result.homography
        }
        let size = CGSize(width: fullRidge.width, height: fullRidge.height)
        let moved = zip(projectedCorners(start), projectedCorners(current)).map { simd_length($0 - $1) }.max() ?? .infinity
        // 縮めた画像の 2 画素より大きく動いたら、別の線に吸い寄せられたとみなして使わない。
        guard moved <= 2 * scale, isPlausible(current.matrix, size: size) else {
            return CourtFit(homography: start, support: fit.support)
        }
        return CourtFit(homography: nearSideDown(current), support: fit.support)
    }

    private func projectedCorners(_ homography: Homography) -> [SIMD2<Double>] {
        CourtModel.corners.compactMap { homography.project(model.position(of: $0)) }
    }

    /// 位置合わせで直して、採点する。直した後がカメラとしてありえなければ nil。
    private func refine(_ start: Homography, ridge: EdgeMap, mask: RidgeMask) -> CourtFit? {
        let fine = CourtSamples(model: model, pointsPerLine: 40)
        var current = start
        // 位置合わせは、線から 8 画素までしか見ない。2 回かけて、少し遠い出発点からも届くようにする。
        for _ in 0..<2 {
            guard let result = aligned(ridge, from: current, model: model) else { break }
            current = result.homography
        }
        let refined = isPlausible(current.matrix, size: mask.size) ? mask.support(of: current.matrix, samples: fine, radius: 1) : nil
        let original = mask.support(of: start.matrix, samples: fine, radius: 1)
        if let refined, refined >= (original ?? 0) {
            return CourtFit(homography: nearSideDown(current), support: refined)
        }
        return original.map { CourtFit(homography: nearSideDown(start), support: $0) }
    }

    /// 図面の「手前」が、画面の下になるようにそろえる。コートは半回転しても同じ形なので、逆のときは図面を半回転する。
    private func nearSideDown(_ homography: Homography) -> Homography {
        guard let near = homography.project(model.position(of: .nearBaselineCenter)),
              let far = homography.project(model.position(of: .farBaselineCenter)),
              near.y < far.y else { return homography }
        let halfTurn = simd_double3x3(diagonal: SIMD3(-1, -1, 1))
        return Homography(matrix: homography.matrix * halfTurn)
    }

    private func isPlausible(_ matrix: simd_double3x3, size: CGSize) -> Bool {
        guard let estimate = CameraEstimate(homography: Homography(matrix: matrix), imageSize: size) else { return false }
        return plausibility.accepts(estimate, imageSize: size)
    }

    // MARK: - 直線

    /// ハフ変換の直線を、白線の芯の画素に当てはめ直し、途切れずに続く長さの順に `maximumLines` 本まで選ぶ。
    /// 文字や観客は、票が多くても細切れなので、続く長さで比べるとコートの線より下になる。
    /// 向き（15 度ごと）ごとに `maximumLinesPerDirection` 本までにする。字幕や観客席の横線で枠が埋まり、斜めのサイドラインが漏れるのを防ぐ。
    private func fittedLines(_ ridge: EdgeMap, mask: RidgeMask) -> [ImageLine] {
        let points = mask.points
        var lines = [(line: ImageLine, run: Double)]()
        for hough in houghLines(mask.edgeMap ?? ridge, threshold: 0.5).prefix(houghCandidates) {
            let radians = hough.theta * .pi / 180
            var line = ImageLine(normal: SIMD2(cos(radians), sin(radians)), offset: hough.rho)
            for tolerance in [4.0, 2.0] {
                guard let fitted = line.fitted(to: points, within: tolerance) else { break }
                line = fitted
            }
            // 当てはめ直した結果、すでにある直線と同じになったものは捨てる。
            let duplicate = lines.contains { $0.line.isClose(to: line, size: mask.size) }
            if !duplicate {
                lines.append((line, line.longestRun(in: points)))
            }
        }
        var perDirection = [Int: Int]()
        var chosen = [ImageLine]()
        for item in lines.sorted(by: { $0.run > $1.run }) where chosen.count < maximumLines {
            // 法線の向き（0〜180 度）を 15 度ごとに分ける。
            var degrees = atan2(item.line.normal.y, item.line.normal.x) * 180 / .pi
            if degrees < 0 {
                degrees += 180
            }
            let bin = Int(degrees / 15) % 12
            guard perDirection[bin, default: 0] < maximumLinesPerDirection else { continue }
            perDirection[bin, default: 0] += 1
            chosen.append(item.line)
        }
        return chosen
    }

    // MARK: - 対応の総当たり

    /// 直線の 2 組を、図面の横の線 2 本と縦の線 2 本に当てはめた変換を、順に渡す。
    private func forEachHypothesis(lines: [ImageLine], size: CGSize, _ body: (simd_double3x3) -> Void) {
        // 図面の横の線（手前のベースライン、手前のキッチン、奥のキッチン、奥のベースライン）と、縦の線（左、中央、右）。
        let rows = [-model.length / 2, -model.kitchenDepth, model.kitchenDepth, model.length / 2]
        let columns = [-model.width / 2, 0, model.width / 2]
        let minimumArea = 0.004 * Double(size.width) * Double(size.height)
        let pairs = courtIndexPairs(lines.count)
        for (h0, h1) in pairs {
            for (v0, v1) in pairs where v0 != h0 && v0 != h1 && v1 != h0 && v1 != h1 {
                guard let a = lines[h0].intersection(lines[v0], in: size),
                      let b = lines[h0].intersection(lines[v1], in: size),
                      let c = lines[h1].intersection(lines[v1], in: size),
                      let d = lines[h1].intersection(lines[v0], in: size) else { continue }
                var quad = [a, b, c, d]
                let area = signedQuadArea(quad)
                guard abs(area) >= minimumArea, isConvexQuad(quad) else { continue }
                // 図面を上から見た向き（左手前、右手前、右奥、左奥）は、画面では左回り（画素の座標では面積が負）。
                if area > 0 {
                    quad = [b, a, d, c]
                }
                for near in 0..<3 {
                    for far in (near + 1)..<4 {
                        for left in 0..<2 {
                            for right in (left + 1)..<3 {
                                let matrix = rectangleToQuad(
                                    x0: columns[left], x1: columns[right], y0: rows[near], y1: rows[far], quad: quad
                                )
                                if let matrix {
                                    body(matrix)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
