import CourtFit
import SwiftUI

/// 動画の表示の範囲（縦横比を保って、枠の中に収める）。
public func fitRect(container: CGSize, video: CGSize) -> CGRect {
    guard video.width > 0, video.height > 0 else { return CGRect(origin: .zero, size: container) }
    let scale = min(container.width / video.width, container.height / video.height)
    let width = video.width * scale
    let height = video.height * scale
    return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2, width: width, height: height)
}

/// 映像を画面いっぱいに、縦横比を保って広げる（はみ出した分は切る）。
public func fillRect(container: CGSize, video: CGSize) -> CGRect {
    guard video.width > 0, video.height > 0 else { return CGRect(origin: .zero, size: container) }
    let scale = max(container.width / video.width, container.height / video.height)
    let width = video.width * scale
    let height = video.height * scale
    return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2, width: width, height: height)
}

/// 検出した四角形を、表示の範囲に合わせて描く。
public struct QuadsOverlay: View {
    let quads: [DetectedQuad]
    let rect: CGRect

    public init(quads: [DetectedQuad], rect: CGRect) {
        self.quads = quads
        self.rect = rect
    }

    public var body: some View {
        Canvas { context, _ in
            for quad in quads {
                // DetectedQuad は左下が原点の正規化座標。画面は左上が原点。
                let points = quad.corners.map {
                    CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + (1 - $0.y) * rect.height)
                }
                var path = Path()
                path.move(to: points[0])
                points.dropFirst().forEach { path.addLine(to: $0) }
                path.closeSubpath()
                context.stroke(path, with: .color(.pink), lineWidth: 4)
            }
        }
        .allowsHitTesting(false)
    }
}

