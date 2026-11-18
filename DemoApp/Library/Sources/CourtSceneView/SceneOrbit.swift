import CourtScene
import Foundation
import simd

/// 3D の視点。コートの中心のまわりを回る。
public struct SceneOrbit: Equatable {
    /// 真上から見た向き（ラジアン）。0 は、手前（z が正）から奥を見る向き。
    public var azimuth: Double
    /// 地面からの見上げの角度（ラジアン）。0 は真横、π/2 は真上。
    public var elevation: Double
    /// コートの中心からの距離（メートル）。
    public var distance: Double
    /// 横の画角（ラジアン）。画面の縦横比が変わっても、横に見える広さをそろえる（映像と見比べるため）。
    public var fieldOfView: Double

    /// 見上げの角度の範囲。真上と地面すれすれは、回し方が分からなくなるので避ける。
    public static let elevationRange = 0.03...1.55
    /// 距離の範囲（メートル）。
    public static let distanceRange = 3.0...80.0

    public init(azimuth: Double, elevation: Double, distance: Double, fieldOfView: Double) {
        self.azimuth = azimuth
        self.elevation = elevation
        self.distance = distance
        self.fieldOfView = fieldOfView
    }

    /// 映像のカメラの位置から、視点を作る。
    public init(camera: CourtCamera) {
        let position = camera.position
        let distance = simd_length(position)
        self.init(
            azimuth: atan2(position.x, position.z),
            elevation: asin(min(1, max(-1, position.y / max(distance, 1e-6)))),
            distance: distance,
            fieldOfView: 2 * atan(Double(camera.imageSize.width) / 2 / camera.focalLength)
        )
        clamp()
    }

    /// 最初の視点（コートを手前の斜め上から見る）。映像のカメラが分からないときに使う。
    public static let standard = SceneOrbit(azimuth: 0, elevation: 0.5, distance: 22, fieldOfView: 1.2)

    /// 画面の縦横比（横 ÷ 縦）での、縦の画角（ラジアン）。
    public func verticalFieldOfView(aspect: Double) -> Double {
        guard aspect > 0 else { return fieldOfView }
        return 2 * atan(tan(fieldOfView / 2) / aspect)
    }

    /// 視点の位置（3D の座標）。
    public var position: SIMD3<Double> {
        SIMD3(
            distance * cos(elevation) * sin(azimuth),
            distance * sin(elevation),
            distance * cos(elevation) * cos(azimuth)
        )
    }

    /// 画面のドラッグ（ポイント）で回す。横は向き、縦は見上げの角度。
    public mutating func rotate(byDrag translation: CGSize, sensitivity: Double = 0.008) {
        azimuth -= Double(translation.width) * sensitivity
        elevation += Double(translation.height) * sensitivity
        clamp()
    }

    /// 近づく・離れる。`scale` が 1 より大きいと近づく。
    public mutating func zoom(by scale: Double) {
        guard scale > 0 else { return }
        distance /= scale
        clamp()
    }

    private mutating func clamp() {
        elevation = min(max(elevation, Self.elevationRange.lowerBound), Self.elevationRange.upperBound)
        distance = min(max(distance, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
    }
}
