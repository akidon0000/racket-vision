import BallTracking
import CourtFit

/// 1 枚の絵から Jev に聞いた、場面の見立て（コートが写っているか、球の色、コートの線の色）。
///
/// 位置を細かく出すのは Jev の苦手なこと（コートの 4 隅は幅の 2% 以上ずれた）。種類を見分けるのは得意なので、
/// 検出の設定（球の色、拾う線の色）を選ぶのに使う。確かめた結果は docs/accuracy/scene-advice.md。
public struct SceneAdvice: Equatable, Sendable {
    /// コートが写っている確からしさ（0〜1）。
    public var courtVisible: Double
    /// 球が写っている確からしさ（0〜1）。
    public var ballVisible: Double
    /// 球の色の名前（`yellow_green`、`orange`、`white`、`pink`、`other`）ごとの確からしさ。
    public var ballColors: [String: Double]
    /// コートの線の色の名前（`white`、`yellow`、`green`、`orange`、`red`、`blue`、`other`）ごとの確からしさ。
    public var lineColors: [String: Double]

    public init(courtVisible: Double, ballVisible: Double, ballColors: [String: Double], lineColors: [String: Double]) {
        self.courtVisible = courtVisible
        self.ballVisible = ballVisible
        self.ballColors = ballColors
        self.lineColors = lineColors
    }

    /// 聞く質問。
    static let questions: [String: JevClient.Question] = [
        "court_visible": .yesNo("Is a pickleball court (its painted boundary lines) visible in `photo`?"),
        "ball_visible": .yesNo("Is a pickleball (the small ball used in play) visible somewhere in `photo`?"),
        "ball_color": .choice(
            "What color is the pickleball (the small plastic ball the players hit) used in this match in `photo`? "
                + "Look at the ball itself, in the air, on the court, or in a player's hand.",
            options: [
                "yellow_green": "optic yellow / neon yellow-green",
                "orange": "orange",
                "white": "white or very pale",
                "pink": "pink or magenta",
                "other": "another color, or no ball can be seen"
            ]
        ),
        "line_color": .choice(
            "What color are the painted boundary lines (baselines, sidelines, kitchen lines) of the pickleball "
                + "court the players are using in `photo`? Ignore lines of other sports on the same floor.",
            options: [
                "white": "white",
                "yellow": "yellow",
                "green": "green",
                "orange": "orange or tan",
                "red": "red",
                "blue": "blue",
                "other": "another color, or no pickleball court lines visible"
            ]
        )
    ]

    init(answers: [String: JevClient.Answer]) throws {
        func yesNo(_ name: String) throws -> Double {
            guard case let .yesNo(value) = answers[name] else { throw JevClient.Failure.malformed("\(name) が無い") }
            return value
        }
        func choice(_ name: String) throws -> [String: Double] {
            guard case let .choice(_, probabilities) = answers[name] else { throw JevClient.Failure.malformed("\(name) が無い") }
            return probabilities
        }
        try self.init(
            courtVisible: yesNo("court_visible"), ballVisible: yesNo("ball_visible"),
            ballColors: choice("ball_color"), lineColors: choice("line_color")
        )
    }
}

/// 何枚かの見立てをまとめて、検出の設定を決める。
///
/// 1 枚では、球が小さく写って見えないことが多い（見えないと `other` と答える）。そこで、球の色は「球が写っている
/// 確からしさ」で重みをつけて足し、線の色はそのまま足して、一番大きい色を採る。
public struct SceneAdviceSummary: Equatable, Sendable {
    public private(set) var advices: [SceneAdvice] = []

    public init(_ advices: [SceneAdvice] = []) {
        self.advices = advices
    }

    public mutating func add(_ advice: SceneAdvice) {
        advices.append(advice)
    }

    /// 球の色の重みの合計（`other` を除く）。
    public var ballColorWeights: [String: Double] {
        var weights = [String: Double]()
        for advice in advices {
            for (name, probability) in advice.ballColors where name != "other" {
                weights[name, default: 0] += probability * advice.ballVisible
            }
        }
        return weights
    }

    /// 線の色の重みの合計（`other` を除く）。コートが写っている確からしさで重みをつける。
    public var lineColorWeights: [String: Double] {
        var weights = [String: Double]()
        for advice in advices {
            for (name, probability) in advice.lineColors where name != "other" {
                weights[name, default: 0] += probability * advice.courtVisible
            }
        }
        return weights
    }

    /// 球の色の組。決めきれない（重みが `minimumWeight` に届かない、知らない色）ときは nil（今の設定のまま）。
    public func ballColors(minimumWeight: Double = 0.5) -> BallColorSet? {
        guard let best = ballColorWeights.max(by: { $0.value < $1.value }), best.value >= minimumWeight else { return nil }
        return BallColorSet(name: best.key)
    }

    /// 拾う線の色。決めきれない、または拾い方を持たない色（緑、オレンジなど）なら nil（今の設定のまま）。
    public func lineColor(minimumWeight: Double = 0.5) -> CourtLineColor? {
        guard let best = lineColorWeights.max(by: { $0.value < $1.value }), best.value >= minimumWeight else { return nil }
        return CourtLineColor(rawValue: best.key)
    }
}
