import BallTracking
import SwiftUI

/// 球の軌跡を、点で描く。色はラリーの番号で決まり、ラリーが変わると変わる。
public struct BallDotsOverlay: View {
    let samples: [BallSample]
    let rallyIndex: Int
    let rect: CGRect
    let outline: Color?

    /// `outline` を渡すと、点の縁をその色で描く（白い背景の上で、白いラリーの色も見えるように）。
    public init(samples: [BallSample], rallyIndex: Int, rect: CGRect, outline: Color? = nil) {
        self.samples = samples
        self.rallyIndex = rallyIndex
        self.rect = rect
        self.outline = outline
    }

    public var body: some View {
        Canvas { context, _ in
            let color = BallRallyPalette.color(forRally: rallyIndex)
            let shading = GraphicsContext.Shading.color(Color(red: color.x, green: color.y, blue: color.z))
            for sample in samples {
                // BallSample は左下が原点の正規化座標。画面は左上が原点。
                let center = CGPoint(x: rect.minX + sample.center.x * rect.width, y: rect.minY + (1 - sample.center.y) * rect.height)
                let dot = Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
                context.fill(dot, with: shading)
                if let outline {
                    context.stroke(dot, with: .color(outline), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
