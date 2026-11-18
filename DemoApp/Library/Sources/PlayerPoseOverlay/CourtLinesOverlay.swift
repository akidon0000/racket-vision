import PlayerPose
import SwiftUI

/// 検出したコートの四隅から、コートの線（外周、キッチンの線、センターライン、ネット）を描く。
public struct CourtLinesOverlay: View {
    let corners: [CGPoint]?
    let rect: CGRect
    let color: Color

    /// `corners` は、コートの四隅（正規化座標、左下が原点。奥の左、奥の右、手前の右、手前の左の順）。
    public init(corners: [CGPoint]?, rect: CGRect, color: Color = .gray) {
        self.corners = corners
        self.rect = rect
        self.color = color
    }

    public var body: some View {
        Canvas { context, _ in
            guard let corners, let court = CourtPlane(corners: corners) else { return }
            context.stroke(path(of: CourtPlane.pickleballLines, on: court), with: .color(color), lineWidth: 1.5)
            context.stroke(path(of: [CourtPlane.net], on: court), with: .color(color), style: StrokeStyle(lineWidth: 3, dash: [4, 3]))
        }
        .allowsHitTesting(false)
    }

    /// コートの線を、画面の座標（左上が原点）の線にする。
    private func path(of segments: [CourtSegment], on court: CourtPlane) -> Path {
        var path = Path()
        for segment in segments {
            guard let start = court.imagePoint(for: segment.start), let end = court.imagePoint(for: segment.end) else { continue }
            path.move(to: CGPoint(x: rect.minX + start.x * rect.width, y: rect.minY + (1 - start.y) * rect.height))
            path.addLine(to: CGPoint(x: rect.minX + end.x * rect.width, y: rect.minY + (1 - end.y) * rect.height))
        }
        return path
    }
}
