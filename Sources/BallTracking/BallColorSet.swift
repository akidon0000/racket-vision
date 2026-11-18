/// 球の色の組。球を探すときの色、コートの範囲で絞れるときの色、追っている球の近くを探すときの色の 3 つ。
///
/// 球の色は動画ごとに違う（黄緑、オレンジ、白っぽいもの）。動画の最初や場面が変わったときに、球の色を外から
/// 決めて（たとえば Jev に聞いて）、この組で検出器を切り替える。
public struct BallColorSet: Equatable, Sendable {
    public var ball: BallColor
    public var court: BallColor
    public var tracking: BallColor

    public init(ball: BallColor, court: BallColor, tracking: BallColor) {
        self.ball = ball
        self.court = court
        self.tracking = tracking
    }

    /// 黄緑の球（既定）。
    public static let yellowGreen = BallColorSet(ball: .yellowGreen, court: .yellowGreenPale, tracking: .yellowGreenWide)
    /// オレンジの球。
    public static let orange = BallColorSet(ball: .orange, court: .orangePale, tracking: .orangeWide)
    /// 白っぽい球。
    public static let pale = BallColorSet(ball: .pale, court: .pale, tracking: .paleWide)

    /// 色の名前（`yellow_green`、`orange`、`white`）から。知らない名前は nil。
    public init?(name: String) {
        switch name {
        case "yellow_green": self = .yellowGreen
        case "orange": self = .orange
        case "white": self = .pale
        default: return nil
        }
    }
}
