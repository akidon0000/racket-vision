import BallTracking
import SwiftUI

/// 球の軌跡を、点で描く。色はラリーの番号で決まり、ラリーが変わると変わる。
public struct BallDotsOverlay: View {
    let samples: [BallSample]
    let rallyIndex: Int
    let rect: CGRect

    public init(samples: [BallSample], rallyIndex: Int, rect: CGRect) {
        self.samples = samples
        self.rallyIndex = rallyIndex
        self.rect = rect
    }

    public var body: some View {
        Canvas { context, _ in
            let color = BallRallyPalette.color(forRally: rallyIndex)
            let shading = GraphicsContext.Shading.color(Color(red: color.x, green: color.y, blue: color.z))
            for sample in samples {
                // BallSample は左下が原点の正規化座標。画面は左上が原点。
                let center = CGPoint(x: rect.minX + sample.center.x * rect.width, y: rect.minY + (1 - sample.center.y) * rect.height)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: shading)
            }
        }
        .allowsHitTesting(false)
    }
}
