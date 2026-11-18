import CoreGraphics
import PlayerPose

/// 描く骨格 1 つ。`color` は選手の番号（`PlayerPalette` の色で描く）。nil なら、白い細い線（選手として選ばなかった人）。
struct PosePreviewItem {
    var pose: BodyPose
    var color: Int?
    /// 少し前の骨格をそのまま出しているか（細い線で描く）。
    var isHeld = false
}

/// フレームに、骨格（骨の線と関節の点）と、コートの矩形（あれば）を描く。`width` と `height` は、描いた画像の大きさ。
/// `regions` は、検出をかけた範囲（黄色い細い枠で描く）。
func renderPosePreview(
    _ frame: CGImage, items: [PosePreviewItem], court: [CGPoint]?, width: Int, height: Int, regions: [CGRect] = []
) -> CGImage? {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    let size = CGSize(width: width, height: height)
    context.interpolationQuality = .medium
    context.draw(frame, in: CGRect(origin: .zero, size: size))
    // 正規化座標は左下が原点。画像の描画も左下が原点なので、そのまま掛ける。
    if let court, court.count == 4 {
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))
        context.setLineWidth(1.5)
        context.addLines(between: court.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
        context.closePath()
        context.strokePath()
    }
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 0, alpha: 0.6))
    context.setLineWidth(1)
    for region in regions {
        context.stroke(CGRect(
            x: region.minX * size.width, y: region.minY * size.height, width: region.width * size.width,
            height: region.height * size.height
        ))
    }
    for item in items {
        draw(item, in: context, size: size)
    }
    return context.makeImage()
}

/// 骨格 1 つを描く。選手は、足元に楕円も描く。
private func draw(_ item: PosePreviewItem, in context: CGContext, size: CGSize) {
    func point(_ normalized: CGPoint) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }
    let rgb = item.color.map { PlayerPalette.color(forPlayer: $0) } ?? SIMD3(1, 1, 1)
    let color = CGColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: item.color == nil ? 0.6 : 1)
    context.setStrokeColor(color)
    context.setFillColor(color)
    context.setLineWidth(item.color == nil || item.isHeld ? 1 : 2.5)
    for bone in PoseBone.body {
        guard let start = item.pose.position(of: bone.start), let end = item.pose.position(of: bone.end) else { continue }
        context.move(to: point(start))
        context.addLine(to: point(end))
        context.strokePath()
    }
    let radius: CGFloat = item.color == nil ? 1.5 : 3
    for keypoint in item.pose.joints.values {
        let center = point(keypoint.position)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
    if let foot = item.pose.footPoint, item.color != nil {
        let center = point(foot)
        context.setLineWidth(2)
        context.strokeEllipse(in: CGRect(x: center.x - 8, y: center.y - 4, width: 16, height: 8))
    }
}
