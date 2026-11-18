import CoreGraphics
import CourtFit
import simd

/// コートの 3D の座標（メートル）。原点はコートの中心（ネットの真ん中の真下）、y が上。
/// x は、手前から見て右が正。z は、手前（カメラのある側）が正。手前のベースラインは z = 長さ / 2。
public enum CourtSpace {
    /// コートの面の座標（横 0〜1、縦 0〜1。`CourtPlane` と同じ。縦 0 が手前）を、3D の座標（地面の上、y = 0）にする。
    public static func point(onCourt position: CGPoint, model: CourtModel = .pickleball) -> SIMD3<Double> {
        SIMD3((Double(position.x) - 0.5) * model.width, 0, (0.5 - Double(position.y)) * model.length)
    }
}

/// 映像を写したカメラの、位置と向きと焦点距離。コートの四隅の写り方から求める。
///
/// 前提: レンズの中心は映像の中心にあり、歪みは無い。画素は正方形。
public struct CourtCamera: Equatable, Sendable {
    /// 3D の座標からカメラの座標への回転。カメラの座標は、x が右、y が下、z が前（見ている向き）。
    public let rotation: simd_double3x3
    /// 3D の座標からカメラの座標への平行移動。
    public let translation: SIMD3<Double>
    /// 焦点距離（画素）。
    public let focalLength: Double
    /// 映像の大きさ（画素）。
    public let imageSize: CGSize

    /// `corners` は、コートの四隅（正規化座標、左下が原点。奥の左、奥の右、手前の右、手前の左の順。`DetectedQuad.corners` と同じ）。
    /// `focalLength` を渡すと、その焦点距離（画素）を使う。渡さないときは、四隅の写り方から求める。
    /// 求まらないとき（四隅がつぶれている、コートを真上や真横から見ているなど）は nil。
    public init?(corners: [CGPoint], imageSize: CGSize, model: CourtModel = .pickleball, focalLength: Double? = nil) {
        guard corners.count == 4, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let width = Double(imageSize.width)
        let height = Double(imageSize.height)
        // 地面の座標 (x, z) と、映像の画素（中心が原点、y が下）の組。
        let ground = [
            SIMD2(-model.width / 2, -model.length / 2), SIMD2(model.width / 2, -model.length / 2),
            SIMD2(model.width / 2, model.length / 2), SIMD2(-model.width / 2, model.length / 2)
        ]
        let pixels = corners.map { SIMD2(Double($0.x) * width - width / 2, (1 - Double($0.y)) * height - height / 2) }
        guard let homography = Homography(from: ground, to: pixels) else { return nil }
        let columns = homography.matrix.columns
        guard let focal = focalLength ?? CourtCamera.focalLength(columns.0, columns.1), focal > 0 else { return nil }
        func unproject(_ column: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(column.x / focal, column.y / focal, column.z)
        }
        var axisX = unproject(columns.0)
        var axisZ = unproject(columns.1)
        var shift = unproject(columns.2)
        let scale = 2 / (simd_length(axisX) + simd_length(axisZ))
        guard scale.isFinite, scale > 0 else { return nil }
        axisX *= scale
        axisZ *= scale
        shift *= scale
        // 変換は符号を決められない。コートがカメラの前にある向きを選ぶ。
        if shift.z < 0 {
            axisX = -axisX
            axisZ = -axisZ
            shift = -shift
        }
        // 2 列を直交させる（グラム・シュミット）。y の軸は、右手系になるように外積で決める（z × x = y）。
        let unitX = simd_normalize(axisX)
        let unitZ = simd_normalize(axisZ - simd_dot(axisZ, unitX) * unitX)
        let unitY = simd_cross(unitZ, unitX)
        rotation = simd_double3x3(columns: (unitX, unitY, unitZ))
        translation = shift
        self.focalLength = focal
        self.imageSize = imageSize
        // カメラは、コートの上にあるはず。下にあれば、向きの選び方が合っていない。
        guard position.y > 0 else { return nil }
    }

    /// カメラの位置（3D の座標）。
    public var position: SIMD3<Double> {
        -(rotation.transpose * translation)
    }

    /// カメラが見ている向き（3D の座標、長さ 1）。
    public var forward: SIMD3<Double> {
        rotation.transpose * SIMD3(0, 0, 1)
    }

    /// カメラの上の向き（3D の座標、長さ 1）。
    public var up: SIMD3<Double> {
        rotation.transpose * SIMD3(0, -1, 0)
    }

    /// 縦の画角（ラジアン）。
    public var verticalFieldOfView: Double {
        2 * atan(Double(imageSize.height) / 2 / focalLength)
    }

    /// 映像の点（正規化座標、左下が原点）を通る、カメラからの向き（3D の座標、長さ 1）。
    public func direction(through point: CGPoint) -> SIMD3<Double> {
        let x = (Double(point.x) - 0.5) * Double(imageSize.width) / focalLength
        let y = (0.5 - Double(point.y)) * Double(imageSize.height) / focalLength
        return simd_normalize(rotation.transpose * SIMD3(x, y, 1))
    }

    /// 3D の点が、映像のどこに写るか（正規化座標、左下が原点）。カメラの後ろなら nil。
    public func project(_ point: SIMD3<Double>) -> CGPoint? {
        let camera = rotation * point + translation
        guard camera.z > 1e-9 else { return nil }
        let x = focalLength * camera.x / camera.z / Double(imageSize.width) + 0.5
        let y = 0.5 - focalLength * camera.y / camera.z / Double(imageSize.height)
        return CGPoint(x: x, y: y)
    }

    /// 映像の点を通る向きが、地面（y = 0）と交わる点。地面と交わらない（水平より上を向く）ときは nil。
    public func groundPoint(for point: CGPoint) -> SIMD3<Double>? {
        intersect(point, plane: SIMD3(0, 0, 0), normal: SIMD3(0, 1, 0))
    }

    /// 映像の点を通る向きが、`origin` を通り `normal` に直交する面と交わる点。交わらない、カメラの後ろで交わるときは nil。
    public func intersect(_ point: CGPoint, plane origin: SIMD3<Double>, normal: SIMD3<Double>) -> SIMD3<Double>? {
        let direction = direction(through: point)
        let denominator = simd_dot(direction, normal)
        guard abs(denominator) > 1e-9 else { return nil }
        let distance = simd_dot(origin - position, normal) / denominator
        guard distance > 0 else { return nil }
        return position + direction * distance
    }

    /// 地面から映像への変換の 2 列（中心が原点の画素）から、焦点距離を求める。2 列が直交し、長さがそろう焦点距離。
    /// 2 つの式のうち、分母の大きいほうを使う。
    static func focalLength(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double? {
        let orthogonalNumerator = -(first.x * second.x + first.y * second.y)
        let orthogonalDenominator = first.z * second.z
        let lengthNumerator = first.x * first.x + first.y * first.y - second.x * second.x - second.y * second.y
        let lengthDenominator = second.z * second.z - first.z * first.z
        let candidates = [(orthogonalNumerator, orthogonalDenominator), (lengthNumerator, lengthDenominator)]
            .filter { abs($0.1) > 1e-15 && $0.0 / $0.1 > 0 }
            .sorted { abs($0.1) > abs($1.1) }
        guard let best = candidates.first else { return nil }
        return (best.0 / best.1).squareRoot()
    }
}
