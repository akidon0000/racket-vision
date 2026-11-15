@testable import BallTracking
import CoreGraphics

/// フレームに、球の候補（白い細い輪）、今のラリーの軌跡（ラリーの色の点）、今の球（ラリーの色の輪）を描く。
/// `width` と `height` は、描いた画像の大きさ。
func renderBallPreview(_ frame: CGImage, outcome: BallFrameOutcome, rally: BallRallyTrajectory, width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    let size = CGSize(width: width, height: height)
    context.interpolationQuality = .low
    context.draw(frame, in: CGRect(origin: .zero, size: size))
    // 正規化座標は左下が原点。画像の描画も左下が原点なので、そのまま掛ける。
    func circle(_ center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x * size.width - radius, y: center.y * size.height - radius, width: radius * 2, height: radius * 2)
    }
    context.setLineWidth(1)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
    for candidate in outcome.candidates {
        context.strokeEllipse(in: circle(candidate.center, radius: candidate.radius * size.width + 3))
    }
    let color = BallRallyPalette.color(forRally: rally.rallyIndex)
    let rallyColor = CGColor(red: color.x, green: color.y, blue: color.z, alpha: 1)
    context.setFillColor(rallyColor)
    for sample in rally.samples {
        context.fillEllipse(in: circle(sample.center, radius: max(2.5, size.width / 320)))
    }
    if let ball = outcome.ball {
        context.setLineWidth(2)
        context.setStrokeColor(rallyColor)
        context.strokeEllipse(in: circle(ball.center, radius: max(8, ball.radius * size.width * 2)))
    }
    return context.makeImage()
}
