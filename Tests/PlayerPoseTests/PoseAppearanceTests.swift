import CoreGraphics
import CoreVideo
import PlayerPose
import Testing

struct PoseAppearanceTests {
    /// 塗る四角形（画素、左上が原点）と、その色（赤・緑・青、0〜255）。
    private struct Patch {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
        var color: SIMD3<UInt8>
    }

    /// 1 色で塗った 200×200 の 32BGRA の画素バッファに、四角形を塗り足す。
    private func buffer(background: SIMD3<UInt8>, patches: [Patch]) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 200, 200, kCVPixelFormatType_32BGRA, nil, &created)
        let buffer = try #require(created)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for patch in [Patch(x: 0, y: 0, width: 200, height: 200, color: background)] + patches {
            for row in patch.y..<(patch.y + patch.height) {
                for column in patch.x..<(patch.x + patch.width) {
                    let offset = row * stride + column * 4
                    base[offset] = patch.color.z
                    base[offset + 1] = patch.color.y
                    base[offset + 2] = patch.color.x
                    base[offset + 3] = 255
                }
            }
        }
        return buffer
    }

    @Test func samplesTorsoAndLegColors() throws {
        // 足元が (0.5, 0.2)、身長が 0.5。画素（左上が原点）では、肩が y = 80、腰が 110、膝が 135。
        let pose = standingPose(foot: CGPoint(x: 0.5, y: 0.2), height: 0.5)
        let image = try buffer(background: SIMD3(0, 0, 255), patches: [
            Patch(x: 80, y: 75, width: 40, height: 35, color: SIMD3(255, 0, 0)),
            Patch(x: 80, y: 110, width: 40, height: 30, color: SIMD3(0, 255, 0))
        ])
        let appearance = try #require(PoseAppearance(pose: pose, in: image))
        let torso = try #require(appearance.torso)
        let legs = try #require(appearance.legs)
        #expect(torso.x > 0.9 && torso.y < 0.1 && torso.z < 0.1)
        #expect(legs.y > 0.9 && legs.x < 0.1 && legs.z < 0.1)
    }

    @Test func distanceIsSmallForSameClothesAndLargeForDifferentClothes() {
        let red = PoseAppearance(torso: SIMD3(0.9, 0.1, 0.1), legs: SIMD3(0.1, 0.1, 0.1))
        let nearlyRed = PoseAppearance(torso: SIMD3(0.85, 0.15, 0.1), legs: SIMD3(0.12, 0.1, 0.1))
        let blue = PoseAppearance(torso: SIMD3(0.1, 0.1, 0.9), legs: SIMD3(0.1, 0.1, 0.1))
        let small = red.distance(to: nearlyRed) ?? 1
        let large = red.distance(to: blue) ?? 0
        #expect(small < 0.05)
        #expect(large > 0.3)
        // 比べられる部分が無ければ、決めない。
        #expect(PoseAppearance(torso: SIMD3(1, 0, 0), legs: nil).distance(to: PoseAppearance(torso: nil, legs: SIMD3(1, 0, 0))) == nil)
    }

    @Test func returnsNilWithoutTorsoOrLegJoints() throws {
        let image = try buffer(background: SIMD3(0, 0, 255), patches: [])
        let pose = BodyPose(joints: [.nose: PoseKeypoint(position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)])
        #expect(PoseAppearance(pose: pose, in: image) == nil)
    }

    @Test func detectorFindsNobodyInPlainImage() throws {
        let image = try buffer(background: SIMD3(40, 80, 200), patches: [])
        let outcome = CourtPlayerDetector().detect(in: image, at: 0)
        #expect(outcome.players.isEmpty)
        #expect(outcome.imageSize == CGSize(width: 200, height: 200))
    }
}
