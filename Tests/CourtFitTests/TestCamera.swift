@testable import CourtFit
import CoreGraphics
import simd

/// テスト用のカメラ。位置と、見る先と、焦点距離から、図面から画面への変換を作る。
enum TestCamera {
    static let imageSize = CGSize(width: 1920, height: 1080)

    /// `camera` と `target` は、コートの座標（メートル、z が上）。`rollDegrees` は、光軸のまわりの傾き。
    static func homography(
        camera: SIMD3<Double>,
        target: SIMD3<Double> = SIMD3(0, 0, 0),
        focalLength: Double,
        rollDegrees: Double = 0
    ) -> Homography {
        let forward = simd_normalize(target - camera)
        var right = simd_normalize(simd_cross(forward, SIMD3(0, 0, 1)))
        var down = simd_cross(forward, right)
        let roll = rollDegrees * .pi / 180
        (right, down) = (right * cos(roll) + down * sin(roll), down * cos(roll) - right * sin(roll))
        let rotation = simd_double3x3(rows: [right, down, forward])
        let translation = -(rotation * camera)
        let intrinsics = simd_double3x3(rows: [
            SIMD3(focalLength, 0, Double(imageSize.width) / 2),
            SIMD3(0, focalLength, Double(imageSize.height) / 2),
            SIMD3(0, 0, 1)
        ])
        let planar = simd_double3x3(columns: (rotation.columns.0, rotation.columns.1, translation))
        return Homography(matrix: intrinsics * planar)
    }

    /// 12 個の交点を、変換で画面に写した位置（正解の代わりに使う）。
    static func keypoints(_ homography: Homography) -> [CourtKeypoint: SIMD2<Double>] {
        var points = [CourtKeypoint: SIMD2<Double>]()
        for keypoint in CourtKeypoint.allCases {
            points[keypoint] = homography.project(CourtModel.pickleball.position(of: keypoint))
        }
        return points
    }
}
