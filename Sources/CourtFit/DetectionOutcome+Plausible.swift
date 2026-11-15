import CoreGraphics

/// 白線の支持率の基準。
public enum CourtLineSupport {
    /// これ以上なら「確か」（実線で出す）。
    public static let strong = 0.5
    /// これ以上なら「候補」（点線で薄く出す）。これより低いものは出さない。
    public static let tentative = 0.1
}

/// 残した四角形の結果。支持率は、`edges` が無いときは nil。
private struct PlausibleQuad {
    let support: Double?
}

public extension DetectionOutcome {
    /// コートとしてありえる四角形だけを残す（面積の順は保つ）。
    ///
    /// 1. カメラとしてありえる写り方か（焦点距離、高さ、傾き、形）。
    /// 2. `edges` を渡したときは、コートの白線が画像のエッジの上にあるか（`lineSupport`）。支持率が
    ///    `CourtLineSupport.tentative` 以上のものを残し、支持率も一緒に持つ。
    ///
    /// 四角形のどの辺がベースラインかは分からないので、両方の向きを試す。どちらか一方で通れば残す。
    /// 変換やカメラの逆算が求まらない四角形は捨てる。
    func keepingPlausibleQuads(
        model: CourtModel = .pickleball,
        plausibility: CameraPlausibility = CameraPlausibility(),
        edges: EdgeMap? = nil
    ) -> DetectionOutcome {
        // 方式が自分で支持率を出しているときは、そのまま返す（白線の芯で測っていて、輝度の勾配より確か）。
        if !quads.isEmpty, supports.count == quads.count {
            return self
        }
        var copy = self
        var keptQuads = [DetectedQuad]()
        var keptSupports = [Double]()
        for quad in quads {
            guard let result = plausibleSupport(of: quad, model: model, plausibility: plausibility, edges: edges) else { continue }
            keptQuads.append(quad)
            if let support = result.support {
                keptSupports.append(support)
            }
        }
        copy.quads = keptQuads
        copy.supports = edges == nil ? [] : keptSupports
        return copy
    }

    /// 残すべき四角形なら、その結果を返す。残さないなら nil。
    /// 両方の向きのうち、どちらか一方で通れば残し、支持率はよいほうを使う。
    private func plausibleSupport(
        of quad: DetectedQuad,
        model: CourtModel,
        plausibility: CameraPlausibility,
        edges: EdgeMap?
    ) -> PlausibleQuad? {
        var bestSupport: Double?
        var passed = false
        for quarterTurned in [false, true] {
            guard let homography = Homography(courtOutline: quad, imageSize: imageSize, quarterTurned: quarterTurned, model: model),
                  let estimate = CameraEstimate(homography: homography, imageSize: imageSize),
                  plausibility.accepts(estimate, imageSize: imageSize) else { continue }
            guard let edges else {
                passed = true
                continue
            }
            guard let support = homography.lineSupport(in: edges, model: model), support >= CourtLineSupport.tentative else { continue }
            passed = true
            bestSupport = max(bestSupport ?? support, support)
        }
        return passed ? PlausibleQuad(support: bestSupport) : nil
    }
}
