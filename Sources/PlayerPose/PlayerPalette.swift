/// 選手ごとの色。番号ごとに違う色にする。
public enum PlayerPalette {
    /// 色の並び（赤・緑・青、0〜1）。番号 0 と 1 が手前の選手、2 と 3 が奥の選手。
    public static let colors: [SIMD3<Double>] = [
        SIMD3(1.0, 0.25, 0.25), SIMD3(0.2, 0.9, 0.3), SIMD3(0.3, 0.6, 1.0), SIMD3(1.0, 0.85, 0.1), SIMD3(1.0, 0.4, 0.9),
        SIMD3(0.2, 0.9, 0.9)
    ]

    /// 選手の番号の色。番号が色の数を超えたら、最初の色に戻る。
    public static func color(forPlayer id: Int) -> SIMD3<Double> {
        let count = colors.count
        return colors[((id % count) + count) % count]
    }
}
