import CoreGraphics
import simd

/// 図面から画面への変換から逆に計算した、カメラの状態。コートとしてありえる写り方かを確かめるために使う。
///
/// 前提: 画面の座標は左上が原点のピクセル。レンズの中心は画面の中心にあり、歪みは無いものとする。
public struct CameraEstimate: Equatable, Sendable {
    /// 焦点距離（ピクセル）。
    public var focalLength: Double
    /// カメラの高さ（コートの面からのメートル）。負の値は、コートを裏から見ていること（ありえない写り方）を表す。
    public var height: Double
    /// 左右の傾き（度）。0 が水平。
    public var rollDegrees: Double
    /// 下向きの角度（度）。0 が水平、90 が真下。
    public var pitchDegrees: Double
    /// 形のずれ（0 以上）。0 に近いほど、実際のカメラで写せる形に近い。
    public var shapeError: Double

    /// `knownFocalLength` を渡すと、その焦点距離を使う。渡さないときは、変換から求める。
    /// 求まらないとき（コートを真上から見ている、変換が潰れているなど）は nil。
    public init?(homography: Homography, imageSize: CGSize, knownFocalLength: Double? = nil) {
        let centerX = Double(imageSize.width) / 2
        let centerY = Double(imageSize.height) / 2
        let columns = homography.matrix.columns
        // レンズの中心が原点になるようにずらす。
        func centered(_ column: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(column.x - centerX * column.z, column.y - centerY * column.z, column.z)
        }
        let first = centered(columns.0)
        let second = centered(columns.1)
        let third = centered(columns.2)

        guard let focal = knownFocalLength ?? Self.focalLength(first, second), focal > 0 else {
            return nil
        }
        // 回転の 1 列目と 2 列目（大きさは、まだそろっていない）。
        var axisX = SIMD3(first.x / focal, first.y / focal, first.z)
        var axisY = SIMD3(second.x / focal, second.y / focal, second.z)
        var translation = SIMD3(third.x / focal, third.y / focal, third.z)
        let lengthX = simd_length(axisX)
        let lengthY = simd_length(axisY)
        guard lengthX > 1e-12, lengthY > 1e-12 else { return nil }

        // 2 列は、同じ長さで直角のはず。そこからのずれを、形のずれとする。
        let angleError = abs(simd_dot(axisX, axisY)) / (lengthX * lengthY)
        let lengthError = abs(lengthX - lengthY) / max(lengthX, lengthY)

        // 変換は符号を決められないので、画面の中心に写るコートの点がカメラの前にある向きを選ぶ。
        var scale = 2 / (lengthX + lengthY)
        let rowZ = SIMD3(columns.0.z, columns.1.z, columns.2.z)
        var depth = columns.2.z
        if let center = homography.inverse?.project(SIMD2(centerX, centerY)) {
            depth = simd_dot(rowZ, SIMD3(center.x, center.y, 1))
        }
        if depth < 0 {
            scale = -scale
        }
        axisX *= scale
        axisY *= scale
        translation *= scale
        let axisZ = simd_normalize(simd_cross(axisX, axisY))

        focalLength = focal
        height = -simd_dot(axisZ, translation)
        // axisZ は、コートの上向きをカメラから見た向き。カメラの座標は、右が x、下が y、前が z。
        rollDegrees = atan2(axisZ.x, -axisZ.y) * 180 / .pi
        pitchDegrees = asin(max(-1, min(1, -axisZ.z))) * 180 / .pi
        shapeError = max(angleError, lengthError)
    }

    /// 35mm 換算の焦点距離（mm）。画面の対角を 43.27mm として換算する。
    public func focalLength35mm(imageSize: CGSize) -> Double {
        let diagonal = (Double(imageSize.width * imageSize.width) + Double(imageSize.height * imageSize.height)).squareRoot()
        return diagonal > 0 ? focalLength / diagonal * 43.27 : 0
    }

    /// 回転の 2 列が、直角で同じ長さになる焦点距離を求める。2 つの式のうち、分母の大きいほうを使う。
    private static func focalLength(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double? {
        let fromAngle = first.z * second.z
        let fromLength = first.z * first.z - second.z * second.z
        let reference = first.z * first.z + second.z * second.z
        guard reference > 0, max(abs(fromAngle), abs(fromLength)) > 1e-9 * reference else {
            return nil
        }
        let squared: Double = if abs(fromAngle) >= abs(fromLength) {
            -(first.x * second.x + first.y * second.y) / fromAngle
        } else {
            (second.x * second.x + second.y * second.y - first.x * first.x - first.y * first.y) / fromLength
        }
        return squared > 0 ? squared.squareRoot() : nil
    }
}

/// カメラの状態が、撮影としてありえる範囲か。範囲の外なら、コートではないものを検出したとみなす。
public struct CameraPlausibility: Equatable, Sendable {
    /// 35mm 換算の焦点距離の範囲（mm）。iPhone のレンズは 13〜120mm。動画の切り出しの分だけ広げてある。
    public var focalLength35mm: ClosedRange<Double>
    /// カメラの高さの範囲（メートル）。
    public var height: ClosedRange<Double>
    /// 左右の傾きの上限（度）。
    public var maximumRollDegrees: Double
    /// 形のずれの上限。
    public var maximumShapeError: Double

    public init(
        focalLength35mm: ClosedRange<Double> = 10...200,
        height: ClosedRange<Double> = 0.3...10,
        maximumRollDegrees: Double = 20,
        maximumShapeError: Double = 0.1
    ) {
        self.focalLength35mm = focalLength35mm
        self.height = height
        self.maximumRollDegrees = maximumRollDegrees
        self.maximumShapeError = maximumShapeError
    }

    public func accepts(_ estimate: CameraEstimate, imageSize: CGSize) -> Bool {
        focalLength35mm.contains(estimate.focalLength35mm(imageSize: imageSize))
            && height.contains(estimate.height)
            && abs(estimate.rollDegrees) <= maximumRollDegrees
            && estimate.shapeError <= maximumShapeError
    }
}
