import CoreGraphics
import simd

/// 選手かもしれない人 1 人（骨格と、追跡に使う量）。
struct PlayerCandidate {
    var pose: BodyPose
    /// 足元（映像の幅を 1 とした長さの座標。縦も同じ単位）。
    var foot: SIMD2<Double>
    /// 骨格を囲む四角形の高さ（映像の幅を 1 とした長さ）。
    var height: Double
    /// コートの上の位置。コートが分からないときは nil。
    var courtPosition: CGPoint?
    /// コートの外へどれだけ出ているか（m）。コートの中なら 0。コートが分からないときは 0。
    var outside: Double
    /// 見た目（服の色）。取れなければ nil。
    var appearance: PoseAppearance?

    var side: CourtSide? {
        courtPosition.map { $0.y < 0.5 ? .near : .far }
    }
}

/// 骨格の中から、コートにいる選手の候補を選ぶ。
struct PlayerCandidateFilter {
    /// コートの幅と長さ（m）。
    var courtWidth = 6.096
    var courtLength = 13.4112
    /// サイドラインの外、ベースラインの後ろへ、どこまでを選手とみるか（m）。
    var sideMargin = 2.0
    var backMargin = 2.5
    /// 映像の上で、足元がコートの矩形からこれ（身長に対する割合）より近ければ、m で測った距離が大きくても選手とみる。
    /// カメラが低いと、奥では足元の数画素のずれが数 m になるため。
    var imageMargin = 0.6
    /// 選手の身長の見込み（m）と、骨格の高さがその何倍までなら選手とみるか。
    var playerHeight = 1.7
    var heightRatio = 0.3...2.0

    /// `aspect` は、映像の横 ÷ 縦。コートが分からないときは、足元の分かる人を全員返す。
    /// 返す順は、コートの中の人が先、同じなら大きく写っている人が先。
    func candidates(from poses: [BodyPose], court: CourtPlane?, aspect: Double) -> [PlayerCandidate] {
        let candidates = poses.compactMap { candidate(from: $0, court: court, aspect: aspect) }
        return candidates.sorted { $0.outside == $1.outside ? $0.height > $1.height : $0.outside < $1.outside }
    }

    private func candidate(from pose: BodyPose, court: CourtPlane?, aspect: Double) -> PlayerCandidate? {
        guard let foot = pose.footPoint, let box = pose.boundingBox else { return nil }
        let height = Double(box.height) / aspect
        var candidate = PlayerCandidate(
            pose: pose, foot: SIMD2(Double(foot.x), Double(foot.y) / aspect), height: height, courtPosition: nil, outside: 0
        )
        guard let court else { return candidate }
        guard let position = court.courtPoint(for: foot) else { return nil }
        let x = Double(position.x) * courtWidth
        let y = Double(position.y) * courtLength
        let outsideX = max(0, -x, x - courtWidth)
        let outsideY = max(0, -y, y - courtLength)
        // 映像の上での、コートの矩形までの距離（身長に対する割合）。
        let imageOutside = imageDistance(from: candidate.foot, to: court, aspect: aspect) / max(height, 1e-6)
        guard (outsideX <= sideMargin && outsideY <= backMargin) || imageOutside <= imageMargin else { return nil }
        // その場所に立つ選手の、映像での身長の見込みと比べる（観客の上半身や、手前を横切る人を外す）。
        if let expected = expectedHeight(at: position, court: court, aspect: aspect), expected > 0 {
            guard heightRatio.contains(height / expected) else { return nil }
        }
        candidate.courtPosition = position
        candidate.outside = min(max(outsideX, outsideY), imageOutside * playerHeight)
        return candidate
    }

    /// 映像の上で、点からコートの矩形までの距離（映像の幅を 1 とした長さ）。矩形の中なら 0。
    private func imageDistance(from point: SIMD2<Double>, to court: CourtPlane, aspect: Double) -> Double {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
            .compactMap { court.imagePoint(for: $0) }
            .map { SIMD2(Double($0.x), Double($0.y) / aspect) }
        guard corners.count == 4 else { return .infinity }
        var isInside = true
        var nearest = Double.infinity
        var sign = 0.0
        for index in corners.indices {
            let a = corners[index]
            let b = corners[(index + 1) % corners.count]
            let edge = b - a
            let offset = point - a
            let cross = edge.x * offset.y - edge.y * offset.x
            if sign == 0 {
                sign = cross
            } else if cross * sign < 0 {
                isInside = false
            }
            // 辺の上の、いちばん近い点までの距離。
            let length = edge.x * edge.x + edge.y * edge.y
            let t = length > 0 ? min(1, max(0, (offset.x * edge.x + offset.y * edge.y) / length)) : 0
            let closest = a + edge * t
            let dx = point.x - closest.x
            let dy = point.y - closest.y
            nearest = min(nearest, (dx * dx + dy * dy).squareRoot())
        }
        return isInside ? 0 : nearest
    }

    /// コートの上の位置に立つ選手の、映像での身長（映像の幅を 1 とした長さ）。その奥行きでのコートの幅から見込む。
    private func expectedHeight(at position: CGPoint, court: CourtPlane, aspect: Double) -> Double? {
        guard let left = court.imagePoint(for: CGPoint(x: 0, y: position.y)),
              let right = court.imagePoint(for: CGPoint(x: 1, y: position.y)) else { return nil }
        let dx = Double(right.x - left.x)
        let dy = Double(right.y - left.y) / aspect
        return (dx * dx + dy * dy).squareRoot() * playerHeight / courtWidth
    }
}
