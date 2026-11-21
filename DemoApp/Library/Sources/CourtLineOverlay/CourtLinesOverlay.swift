import CourtFit
import SwiftUI

/// 検出したコートの四隅から、コートの線（外周、キッチンの線、センターライン、ネット）を描く。
/// 外周だけでなく中の線も描くので、検出がずれているときに、どの線が本物とずれているかが分かる。
public struct CourtLinesOverlay: View {
    let corners: [CGPoint]?
    let rect: CGRect
    let color: Color
    let lineWidth: CGFloat

    /// `corners` は、コートの四隅（正規化座標、左下が原点。奥の左、奥の右、手前の右、手前の左の順）。
    /// `rect` は、映像を描いている範囲（画面の座標）。
    public init(corners: [CGPoint]?, rect: CGRect, color: Color = .gray, lineWidth: CGFloat = 1.5) {
        self.corners = corners
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Canvas { context, _ in
            guard let corners, let court = CourtPlane(corners: corners) else { return }
            context.stroke(path(of: CourtPlane.pickleballLines, on: court), with: .color(color), lineWidth: lineWidth)
            context.stroke(
                path(of: [CourtPlane.net], on: court), with: .color(color), style: StrokeStyle(lineWidth: lineWidth * 2, dash: [4, 3])
            )
        }
        .allowsHitTesting(false)
    }

    /// コートの線を、画面の座標（左上が原点）の線にする。
    ///
    /// 線を細かく分けて写し、カメラの後ろに当たる所だけを描かない。低い位置から近くで撮ると、手前のベースラインの端が
    /// カメラの後ろに当たることがあり、両端だけで写すと線ごと消えてしまうため。
    private func path(of segments: [CourtSegment], on court: CourtPlane) -> Path {
        var path = Path()
        let steps = 24
        for segment in segments {
            var isDrawing = false
            for step in 0...steps {
                let ratio = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(
                    x: segment.start.x + (segment.end.x - segment.start.x) * ratio,
                    y: segment.start.y + (segment.end.y - segment.start.y) * ratio
                )
                guard let image = court.imagePoint(for: point), image.x.isFinite, image.y.isFinite else {
                    isDrawing = false
                    continue
                }
                let screen = CGPoint(x: rect.minX + image.x * rect.width, y: rect.minY + (1 - image.y) * rect.height)
                if isDrawing {
                    path.addLine(to: screen)
                } else {
                    path.move(to: screen)
                    isDrawing = true
                }
            }
        }
        return path
    }
}
