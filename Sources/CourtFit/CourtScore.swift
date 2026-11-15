import CoreGraphics
import simd

/// 検出した変換を、正解の交点と比べた結果。
public struct CourtScore: Equatable, Sendable {
    /// 交点 1 つのずれ。
    public struct PointError: Equatable, Sendable {
        /// 画面の上のずれ（ピクセル）。
        public var image: Double
        /// コートの面でのずれ（メートル）。
        public var court: Double
    }

    /// 正解のある交点ごとのずれ。
    public var errors: [CourtKeypoint: PointError]

    /// 図面から画面への変換 `estimated` を、正解の交点の位置 `truth`（画面のピクセル、左上が原点）と比べる。
    /// 変換できない点があるとき、正解が 1 つも無いときは nil。
    public init?(estimated: Homography, truth: [CourtKeypoint: SIMD2<Double>], model: CourtModel = .pickleball) {
        guard !truth.isEmpty, let inverse = estimated.inverse else { return nil }
        var errors = [CourtKeypoint: PointError]()
        for (keypoint, imagePoint) in truth {
            let courtPoint = model.position(of: keypoint)
            guard let projected = estimated.project(courtPoint), let unprojected = inverse.project(imagePoint) else {
                return nil
            }
            errors[keypoint] = PointError(
                image: simd_length(projected - imagePoint),
                court: simd_length(unprojected - courtPoint)
            )
        }
        self.errors = errors
    }

    /// 画面の上のずれの最大（ピクセル）。
    public var maximumImageError: Double {
        errors.values.map(\.image).max() ?? 0
    }

    /// コートの面でのずれの最大（メートル）。
    public var maximumCourtError: Double {
        errors.values.map(\.court).max() ?? 0
    }

    /// コートの面でのずれの平均（メートル）。
    public var meanCourtError: Double {
        errors.isEmpty ? 0 : errors.values.map(\.court).reduce(0, +) / Double(errors.count)
    }

    /// すべての交点のずれが、`tolerance`（メートル）以内か。既定は線の幅（約 5cm）。
    public func passes(tolerance: Double = 0.05) -> Bool {
        maximumCourtError <= tolerance
    }
}

public extension Homography {
    /// 検出した四角形を、コートの外枠とみなして、図面から画面（ピクセル、左上が原点）への変換を作る。
    ///
    /// 四角形のどの辺がベースラインかは分からないので、`quarterTurned` が false のときは上下の辺を、
    /// true のときは左右の辺をベースラインとみなす。採点では、両方を試して、ずれの小さいほうを使う。
    init?(courtOutline quad: DetectedQuad, imageSize: CGSize, quarterTurned: Bool, model: CourtModel = .pickleball) {
        // DetectedQuad は左下が原点の正規化座標。左上が原点のピクセルに直す。
        let pixels = [quad.bottomLeft, quad.bottomRight, quad.topRight, quad.topLeft].map {
            SIMD2(Double($0.x * imageSize.width), Double((1 - $0.y) * imageSize.height))
        }
        let rotated = quarterTurned ? Array(pixels[1...]) + [pixels[0]] : pixels
        self.init(from: CourtModel.corners.map { model.position(of: $0) }, to: rotated)
    }
}
