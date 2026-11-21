import simd

/// ラリーごとの、軌跡の色。
public enum BallRallyPalette {
    /// 色の並び（赤・緑・青、0〜1）。青いコートと木の床の両方で見え、球の黄緑と紛れない色。
    public static let colors: [SIMD3<Double>] = [
        SIMD3(1.0, 0.22, 0.2),
        SIMD3(1.0, 1.0, 1.0),
        SIMD3(1.0, 0.25, 0.85),
        SIMD3(1.0, 0.6, 0.0),
        SIMD3(0.3, 1.0, 0.9),
        SIMD3(0.65, 0.4, 1.0)
    ]

    /// ラリーの番号の色。番号が色の数を超えたら、最初の色に戻る。
    public static func color(forRally index: Int) -> SIMD3<Double> {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}
