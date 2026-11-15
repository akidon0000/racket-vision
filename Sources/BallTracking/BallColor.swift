/// 球の色。色相・鮮やかさ・明るさの範囲で表す。
public struct BallColor: Equatable, Sendable {
    /// 色相の範囲（度、0〜360）。赤をまたぐ範囲（350〜10 など）は表せない。
    public var hueRange: ClosedRange<Double>
    /// 鮮やかさ（彩度）の下限（0〜1）。
    public var minimumSaturation: Double
    /// 明るさの下限（0〜1）。
    public var minimumBrightness: Double

    public init(hueRange: ClosedRange<Double>, minimumSaturation: Double, minimumBrightness: Double) {
        self.hueRange = hueRange
        self.minimumSaturation = minimumSaturation
        self.minimumBrightness = minimumBrightness
    }

    /// 黄緑の球（屋内外でよく使われる色）。
    public static let yellowGreen = BallColor(hueRange: 40...110, minimumSaturation: 0.3, minimumBrightness: 0.45)

    /// 画素が、この色に入るか。
    func matches(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        let r = Int(red)
        let g = Int(green)
        let b = Int(blue)
        let high = max(r, g, b)
        let chroma = high - min(r, g, b)
        guard chroma > 0, Double(high) >= minimumBrightness * 255, Double(chroma) >= minimumSaturation * Double(high) else {
            return false
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
