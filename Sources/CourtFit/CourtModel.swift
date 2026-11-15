import simd

/// コートの線の交点（12 個）。採点と、図面を画面に合わせる計算で使う。
///
/// near はカメラに近い側（画面の下側）、far は遠い側。left と right は、near の側に立ってコートを見たときの左右。
/// コートは 180 度回しても同じ形なので、どちらを near にしても図面は同じになる。
public enum CourtKeypoint: String, CaseIterable, Codable, Sendable {
    case nearLeftCorner
    case nearRightCorner
    case farRightCorner
    case farLeftCorner
    case nearKitchenLeft
    case nearKitchenRight
    case farKitchenRight
    case farKitchenLeft
    case nearBaselineCenter
    case nearKitchenCenter
    case farKitchenCenter
    case farBaselineCenter
}

/// コートの線の 1 本。両端を交点で持つ。
public struct CourtLine: Equatable, Sendable {
    public var start: CourtKeypoint
    public var end: CourtKeypoint

    public init(start: CourtKeypoint, end: CourtKeypoint) {
        self.start = start
        self.end = end
    }
}

/// コートの図面。座標はコートの面の上のメートル。原点はコートの中心、x は幅の向き（右が正）、y は長さの向き（far が正）。
public struct CourtModel: Equatable, Sendable {
    /// 幅（サイドラインの間）。
    public var width: Double
    /// 長さ（ベースラインの間）。
    public var length: Double
    /// ネットからキッチンの線までの距離。
    public var kitchenDepth: Double

    public init(width: Double, length: Double, kitchenDepth: Double) {
        self.width = width
        self.length = length
        self.kitchenDepth = kitchenDepth
    }

    /// ピックルボールのコート（20 × 44 フィート、キッチンは 7 フィート）。
    public static let pickleball = CourtModel(width: 6.096, length: 13.4112, kitchenDepth: 2.1336)

    /// 四隅。順は、near の左、near の右、far の右、far の左。
    public static let corners: [CourtKeypoint] = [.nearLeftCorner, .nearRightCorner, .farRightCorner, .farLeftCorner]

    /// 線の一覧（8 本）。外枠が 4 本、キッチンの線が 2 本、センターラインが 2 本。
    public static let lines: [CourtLine] = [
        CourtLine(start: .nearLeftCorner, end: .nearRightCorner),
        CourtLine(start: .farLeftCorner, end: .farRightCorner),
        CourtLine(start: .nearLeftCorner, end: .farLeftCorner),
        CourtLine(start: .nearRightCorner, end: .farRightCorner),
        CourtLine(start: .nearKitchenLeft, end: .nearKitchenRight),
        CourtLine(start: .farKitchenLeft, end: .farKitchenRight),
        CourtLine(start: .nearBaselineCenter, end: .nearKitchenCenter),
        CourtLine(start: .farKitchenCenter, end: .farBaselineCenter)
    ]

    /// 交点の、図面の上の位置（メートル）。
    public func position(of keypoint: CourtKeypoint) -> SIMD2<Double> {
        SIMD2(horizontal(of: keypoint), vertical(of: keypoint))
    }

    private func horizontal(of keypoint: CourtKeypoint) -> Double {
        switch keypoint {
        case .nearLeftCorner, .farLeftCorner, .nearKitchenLeft, .farKitchenLeft: -width / 2
        case .nearRightCorner, .farRightCorner, .nearKitchenRight, .farKitchenRight: width / 2
        case .nearBaselineCenter, .nearKitchenCenter, .farKitchenCenter, .farBaselineCenter: 0
        }
    }

    private func vertical(of keypoint: CourtKeypoint) -> Double {
        switch keypoint {
        case .nearLeftCorner, .nearRightCorner, .nearBaselineCenter: -length / 2
        case .nearKitchenLeft, .nearKitchenRight, .nearKitchenCenter: -kitchenDepth
        case .farKitchenLeft, .farKitchenRight, .farKitchenCenter: kitchenDepth
        case .farLeftCorner, .farRightCorner, .farBaselineCenter: length / 2
        }
    }
}
