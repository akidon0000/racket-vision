import PlayerPose
import SwiftUI

/// 選手の骨格を、線と点で描く。色は選手の番号で決まり、同じ選手は同じ色のままになる。
/// 頭の上に、選手の番号（1 始まり）を出す。
public struct PlayerSkeletonOverlay: View {
    let players: [CourtPlayer]
    let rect: CGRect

    public init(players: [CourtPlayer], rect: CGRect) {
        self.players = players
        self.rect = rect
    }

    public var body: some View {
        Canvas { context, _ in
            for player in players {
                draw(player, in: &context)
            }
        }
        .allowsHitTesting(false)
    }

    /// 正規化座標（左下が原点）を、画面の座標（左上が原点）にする。
    private func point(_ normalized: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + normalized.x * rect.width, y: rect.minY + (1 - normalized.y) * rect.height)
    }

    private func draw(_ player: CourtPlayer, in context: inout GraphicsContext) {
        let rgb = PlayerPalette.color(forPlayer: player.id)
        // このフレームで骨格が見つからず、少し前の骨格を出しているときは、薄く描く。
        let color = Color(red: rgb.x, green: rgb.y, blue: rgb.z).opacity(player.isDetected ? 1 : 0.45)
        let shading = GraphicsContext.Shading.color(color)
        var bones = Path()
        for bone in PoseBone.body {
            guard let start = player.pose.position(of: bone.start), let end = player.pose.position(of: bone.end) else { continue }
            bones.move(to: point(start))
            bones.addLine(to: point(end))
        }
        context.stroke(bones, with: shading, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        for keypoint in player.pose.joints.values {
            let center = point(keypoint.position)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)), with: shading)
        }
        guard let box = player.pose.boundingBox else { return }
        let top = point(CGPoint(x: box.midX, y: box.maxY))
        context.draw(
            Text("\(player.id + 1)").font(.caption2.bold()).foregroundStyle(color),
            at: CGPoint(x: top.x, y: top.y - 8)
        )
    }
}
