/// 球の色。色相・鮮やかさ・明るさの範囲で表す。
///
/// 明るく写った球は、白に近づいて鮮やかさが落ちる（小さく写った球や、照明の強い会場）。
/// そこで、明るい画素（`brightBrightness` 以上）には、低い鮮やかさの下限（`brightSaturation`）を使える。
public struct BallColor: Equatable, Sendable {
    /// 色相の範囲（度、0〜360）。赤をまたぐ範囲（350〜10 など）は表せない。
    public var hueRange: ClosedRange<Double>
    /// 鮮やかさ（彩度）の下限（0〜1）。
    public var minimumSaturation: Double
    /// 明るさの下限（0〜1）。
    public var minimumBrightness: Double
    /// 明るい画素に使う、鮮やかさの下限（0〜1）。nil なら、明るい画素も `minimumSaturation` で見る。
    public var brightSaturation: Double?
    /// 「明るい画素」とみなす、明るさの下限（0〜1）。
    public var brightBrightness: Double
    /// 鮮やかさの上限（0〜1）。白っぽい球のように、色の薄さで見分けるときに使う。
    public var maximumSaturation: Double

    public init(
        hueRange: ClosedRange<Double>, minimumSaturation: Double, minimumBrightness: Double,
        brightSaturation: Double? = nil, brightBrightness: Double = 0.8, maximumSaturation: Double = 1
    ) {
        self.hueRange = hueRange
        self.minimumSaturation = minimumSaturation
        self.minimumBrightness = minimumBrightness
        self.brightSaturation = brightSaturation
        self.brightBrightness = brightBrightness
        self.maximumSaturation = maximumSaturation
    }

    /// 黄緑の球（屋内外でよく使われる色）。
    public static let yellowGreen = BallColor(
        hueRange: 55...105, minimumSaturation: 0.5, minimumBrightness: 0.45, brightSaturation: 0.25
    )

    /// 黄緑の球を、薄く写ったものまで取る色。小さく写った球や、速くてぶれた球は、白や背景の色が混じって、
    /// 薄い緑になる。観客や服も拾いやすくなるので、コートの範囲で絞れるときに使う。
    public static let yellowGreenPale = BallColor(
        hueRange: 55...150, minimumSaturation: 0.5, minimumBrightness: 0.45, brightSaturation: 0.15, brightBrightness: 0.7
    )

    /// 黄緑の球を、広めに取る色。追っている球の近くだけを探すときに使う（ぶれたり、小さく写ったりして薄くなった球も通す）。
    public static let yellowGreenWide = BallColor(
        hueRange: 45...150, minimumSaturation: 0.3, minimumBrightness: 0.35, brightSaturation: 0.15, brightBrightness: 0.7
    )

    /// オレンジの球。色相 13〜16 度、鮮やかさ 0.68〜0.78 に写る（1min-09）。黄色い壁（色相 44 度）と、
    /// 顔や肌（色相 24 度前後、鮮やかさ 0.6 前後）は外す。
    public static let orange = BallColor(
        hueRange: 5...20, minimumSaturation: 0.64, minimumBrightness: 0.45, brightSaturation: 0.5
    )

    /// オレンジの球を、薄く写ったものまで取る色。コートの範囲で絞れるときに使う。
    public static let orangePale = BallColor(
        hueRange: 3...22, minimumSaturation: 0.58, minimumBrightness: 0.4, brightSaturation: 0.45, brightBrightness: 0.7
    )

    /// オレンジの球を、広めに取る色。追っている球の近くだけを探すときに使う。
    public static let orangeWide = BallColor(
        hueRange: 0...26, minimumSaturation: 0.45, minimumBrightness: 0.35, brightSaturation: 0.35, brightBrightness: 0.7
    )

    /// 白っぽい球。色がほとんど無く（鮮やかさ 0.3 以下）、明るい。白線や白い服とも同じ色なので、動きと大きさで見分ける。
    public static let pale = BallColor(
        hueRange: 0...360, minimumSaturation: 0, minimumBrightness: 0.55, maximumSaturation: 0.3
    )

    /// 白っぽい球を、広めに取る色。追っている球の近くだけを探すときに使う。
    public static let paleWide = BallColor(
        hueRange: 0...360, minimumSaturation: 0, minimumBrightness: 0.45, maximumSaturation: 0.35
    )

    /// 画素が、この色に入るか。
    func matches(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        let r = Int(red)
        let g = Int(green)
        let b = Int(blue)
        let high = max(r, g, b)
        let chroma = high - min(r, g, b)
        var saturation = minimumSaturation
        if let brightSaturation, Double(high) >= brightBrightness * 255 {
            saturation = min(saturation, brightSaturation)
        }
        guard Double(high) >= minimumBrightness * 255, Double(chroma) >= saturation * Double(high),
              Double(chroma) <= maximumSaturation * Double(high) else {
            return false
        }
        // 色の無い画素は色相が決まらない。色相を全部通す色（白っぽい球）だけが受け入れる。
        guard chroma > 0 else {
            return hueRange.lowerBound <= 0 && hueRange.upperBound >= 360
        }
        var hue: Double
        if high == r {
            hue = 60 * Double(g - b) / Double(chroma)
        } else if high == g {
            hue = 60 * Double(b - r) / Double(chroma) + 120
        } else {
            hue = 60 * Double(r - g) / Double(chroma) + 240
        }
        if hue < 0 {
            hue += 360
        }
        return hueRange.contains(hue)
    }
}
