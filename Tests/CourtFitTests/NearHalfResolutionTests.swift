@testable import CourtFit
import CoreGraphics
import simd
import Testing

/// 低い位置から撮った映像で、手前の半面をコート全体と取り違えたときに、直せるか。
struct NearHalfResolutionTests {
    private let model = CourtModel.pickleball
    /// 白線の芯の画像の大きさ（映像の半分）。
    private let size = (width: 960, height: 540)

    /// ベースラインの 3 m 後ろ、高さ 1.5 m から、ネットのほうを見る。白線の芯の画像（半分の大きさ）への変換。
    private func lowCamera() -> Homography {
        let full = TestCamera.homography(camera: SIMD3(0.4, -9.7, 1.5), target: SIMD3(0, 0, 0.3), focalLength: 900)
        return Homography(matrix: simd_double3x3(diagonal: SIMD3(0.5, 0.5, 1)) * full.matrix)
    }

    /// コートの線 8 本と、ネットの下の線。低い位置から見ると、奥の半面はネットの向こうに詰まって写る。
    private var courtLines: [(SIMD2<Double>, SIMD2<Double>)] {
        CourtModel.lines.map { (model.position(of: $0.start), model.position(of: $0.end)) }
            + [(SIMD2(-model.width / 2, 0), SIMD2(model.width / 2, 0))]
    }

    /// 図面の線分（メートル）を、変換で写して、太さ 3 画素の芯として描く。
    private func ridge(_ segments: [(SIMD2<Double>, SIMD2<Double>)], _ homography: Homography) throws -> EdgeMap {
        var values = [Float](repeating: 0, count: size.width * size.height)
        for (start, end) in segments {
            for step in 0...2000 {
                let court = start + (end - start) * (Double(step) / 2000)
                guard let pixel = homography.project(court) else { continue }
                for dy in -1...1 {
                    for dx in -1...1 {
                        let x = Int(pixel.x.rounded()) + dx
                        let y = Int(pixel.y.rounded()) + dy
                        guard x >= 0, y >= 0, x < size.width, y < size.height else { continue }
                        values[y * size.width + x] = 1
                    }
                }
            }
        }
        return try #require(EdgeMap(width: size.width, height: size.height, values: values))
    }

    /// 本当の図面の y（-half〜0）を、図面の全体（-half〜half）に伸ばす変換。取り違えた変換は、正しい変換にこの逆をかけたもの。
    private var stretch: simd_double3x3 {
        let half = model.length / 2
        return simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, 2, half), SIMD3(0, 0, 1)])
    }

    @Test func correctsNearHalfMistakenForWholeCourt() throws {
        let truth = lowCamera()
        let edges = try ridge(courtLines, truth)
        let mistaken = Homography(matrix: truth.matrix * stretch.inverse)
        // 取り違えた変換は、ネットの下の線を奥のベースラインとして、手前の半面に重なる。
        let mistakenNet = try #require(mistaken.project(SIMD2(0, model.length / 2)))
        let truthNet = try #require(truth.project(SIMD2(0, 0)))
        #expect(simd_length(mistakenNet - truthNet) < 1)

        let fit = try #require(CourtLineModelSearch().track(edges, from: mistaken))
        // 手前のキッチンの線の中央（手前と奥の選手を分ける位置）は 3 画素以内、四隅は 8 画素以内に戻る。
        // 四隅の残りのずれは、正しい変換から合わせ直しても出る（画面の端の線への位置合わせの癖。合成の線でも 5 画素ほど動く）。
        try expectClose(fit.homography, truth, at: [.nearKitchenCenter, .nearBaselineCenter], within: 3)
        try expectClose(fit.homography, truth, at: [.nearLeftCorner, .nearRightCorner, .nearKitchenLeft, .nearKitchenRight], within: 8)
    }

    @Test func keepsCorrectFit() throws {
        let truth = lowCamera()
        let edges = try ridge(courtLines, truth)
        let fit = try #require(CourtLineModelSearch().track(edges, from: truth))
        try expectClose(fit.homography, truth, at: [.nearKitchenCenter, .nearBaselineCenter], within: 3)
        try expectClose(fit.homography, truth, at: [.nearLeftCorner, .nearRightCorner, .nearKitchenLeft, .nearKitchenRight], within: 8)
    }

    private func expectClose(_ found: Homography, _ truth: Homography, at keypoints: [CourtKeypoint], within limit: Double) throws {
        for keypoint in keypoints {
            let a = try #require(found.project(model.position(of: keypoint)))
            let b = try #require(truth.project(model.position(of: keypoint)))
            #expect(simd_length(a - b) < limit, "\(keypoint)")
        }
    }
}
