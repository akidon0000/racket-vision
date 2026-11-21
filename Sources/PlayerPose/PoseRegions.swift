import CoreGraphics

/// 骨格の検出をかける範囲を、コートの矩形から作る。
///
/// 奥の選手は小さく写るので、奥の半面と手前の半面で範囲を分け、範囲の中で選手が十分に大きく見えるようにする。
/// 範囲が横に長いときは、重なりを持たせて左右に分ける。
public struct PoseRegions: Sendable {
    /// 選手の身長の見込み（コートの幅 6.1 m に対する割合。0.3 で約 1.8 m）。
    public var playerHeight: Double
    /// サイドラインの外へ、範囲を広げる幅（コートの幅に対する割合）。
    public var sideMargin: Double
    /// ベースラインの後ろへ、範囲を広げる奥行き（コートの長さに対する割合）。
    public var backMargin: Double
    /// 範囲の横 ÷ 縦（画素）がこれを超えたら、左右に分ける。
    public var maximumAspect: Double
    /// 左右に分けた範囲どうしの重なり（範囲の幅に対する割合）。
    public var overlap: Double

    public init(
        playerHeight: Double = 0.3, sideMargin: Double = 0.35, backMargin: Double = 0.25,
        maximumAspect: Double = 1.4, overlap: Double = 0.35
    ) {
        self.playerHeight = playerHeight
        self.sideMargin = sideMargin
        self.backMargin = backMargin
        self.maximumAspect = maximumAspect
        self.overlap = overlap
    }

    /// 奥の半面と手前の半面の範囲（正規化座標、左下が原点）。`aspect` は、映像の横 ÷ 縦。
    public func tiles(for court: CourtPlane, aspect: Double) -> [CGRect] {
        band(from: 0.5, to: 1 + backMargin, in: court, aspect: aspect)
            + band(from: -backMargin, to: 0.5, in: court, aspect: aspect)
    }

    /// コートが分からないときの範囲。画面の全体と、画面を格子に分けた範囲（重なりあり）。
    /// 格子の 1 つは、映像の短い辺の `size` 倍くらいの正方形にする。
    public func grid(aspect: Double, size: Double = 0.6) -> [CGRect] {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        // 映像の短い辺を 1 とした、横と縦の長さ。
        let width = max(1, aspect)
        let height = max(1, 1 / aspect)
        func count(_ length: Double) -> Int {
            // 幅 size の範囲を n 個、重なり overlap で並べると、全体は size * (n - (n - 1) * overlap)。
            max(1, Int(((length / size - overlap) / (1 - overlap)).rounded(.up)))
        }
        let columns = count(width)
        let rows = count(height)
        guard columns * rows > 1 else { return [whole] }
        let tileWidth = 1 / (Double(columns) - Double(columns - 1) * overlap)
        let tileHeight = 1 / (Double(rows) - Double(rows - 1) * overlap)
        var tiles = [whole]
        for row in 0..<rows {
            for column in 0..<columns {
                tiles.append(CGRect(
                    x: Double(column) * tileWidth * (1 - overlap), y: Double(row) * tileHeight * (1 - overlap),
                    width: tileWidth, height: tileHeight
                ))
            }
        }
        return tiles
    }

    /// コートの縦 `near`〜`far` に立つ選手が入る範囲。足元と、そこから身長の分だけ上までを囲む。
    private func band(from near: Double, to far: Double, in court: CourtPlane, aspect: Double) -> [CGRect] {
        var minX = Double.infinity
        var maxX = -Double.infinity
        var minY = Double.infinity
        var maxY = -Double.infinity
        // カメラが低くコートに近いと、ベースラインの後ろに広げた先がカメラの後ろになり、写せない。そのときは、写せるところまで
        // 奥へ寄せ、それより手前は画面の下の端まで続くとみなす（カメラに近いほど、地面は画面の下に写る）。
        var reachesBottom = false
        for requested in [near, far] {
            var depth = requested
            while depth < far, !isVisible(depth, in: court) {
                depth = min(far, depth + 0.02)
                reachesBottom = true
            }
            guard let left = court.imagePoint(for: CGPoint(x: -sideMargin, y: depth)),
                  let right = court.imagePoint(for: CGPoint(x: 1 + sideMargin, y: depth)),
                  let lineLeft = court.imagePoint(for: CGPoint(x: 0, y: depth)),
                  let lineRight = court.imagePoint(for: CGPoint(x: 1, y: depth)) else { continue }
            // その奥行きでのコートの幅（画素の比で測る）から、選手の身長を見込む。縦の長さは、映像の高さを 1 とした長さに直す。
            let dx = Double(lineRight.x - lineLeft.x)
            let dy = Double(lineRight.y - lineLeft.y) / aspect
            let height = (dx * dx + dy * dy).squareRoot() * playerHeight * aspect
            for point in [left, right] {
                minX = min(minX, Double(point.x))
                maxX = max(maxX, Double(point.x))
                minY = min(minY, Double(point.y))
                maxY = max(maxY, Double(point.y) + height)
            }
        }
        if reachesBottom {
            minY = min(minY, 0)
        }
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(whole)
        guard minX.isFinite, !rect.isNull, rect.width > 0, rect.height > 0 else { return [] }
        return split(rect, aspect: aspect)
    }

    /// コートの縦 `depth` の線（サイドラインの外まで）が、カメラの前にあって写せるか。
    private func isVisible(_ depth: Double, in court: CourtPlane) -> Bool {
        [-sideMargin, 0, 1, 1 + sideMargin].allSatisfy { court.imagePoint(for: CGPoint(x: $0, y: depth)) != nil }
    }

    /// 横に長い範囲を、重なりを持たせて左右に分ける。
    private func split(_ rect: CGRect, aspect: Double) -> [CGRect] {
        let ratio = Double(rect.width) * aspect / Double(rect.height)
        let count = max(1, Int((ratio / maximumAspect).rounded(.up)))
        guard count > 1 else { return [rect] }
        // 幅 w の範囲を count 個、重なり overlap で並べると、全体の幅は w * (count - (count - 1) * overlap)。
        let width = Double(rect.width) / (Double(count) - Double(count - 1) * overlap)
        return (0..<count).map { index in
            CGRect(
                x: Double(rect.minX) + Double(index) * width * (1 - overlap), y: Double(rect.minY),
                width: width, height: Double(rect.height)
            )
        }
    }
}
