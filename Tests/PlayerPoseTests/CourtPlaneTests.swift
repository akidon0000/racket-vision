import CoreGraphics
import PlayerPose
import Testing

struct CourtPlaneTests {
    /// 奥が狭く写った台形のコート（奥の左、奥の右、手前の右、手前の左）。
    private let trapezoid = [
        CGPoint(x: 0.4, y: 0.8), CGPoint(x: 0.6, y: 0.8), CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.2, y: 0.2)
    ]

    private func isClose(_ a: CGPoint?, _ b: CGPoint, tolerance: CGFloat = 1e-9) -> Bool {
        guard let a else { return false }
        return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    @Test func mapsCourtCornersToImageCorners() throws {
        let court = try #require(CourtPlane(corners: trapezoid))
        #expect(isClose(court.imagePoint(for: CGPoint(x: 0, y: 1)), trapezoid[0]))
        #expect(isClose(court.imagePoint(for: CGPoint(x: 1, y: 1)), trapezoid[1]))
        #expect(isClose(court.imagePoint(for: CGPoint(x: 1, y: 0)), trapezoid[2]))
        #expect(isClose(court.imagePoint(for: CGPoint(x: 0, y: 0)), trapezoid[3]))
    }

    @Test func mapsImagePointBackToCourt() throws {
        let court = try #require(CourtPlane(corners: trapezoid))
        let position = CGPoint(x: 0.3, y: 0.7)
        let image = try #require(court.imagePoint(for: position))
        #expect(isClose(court.courtPoint(for: image), position))
        // 奥ほど小さく写るので、コートの真ん中（ネット）は、映像では上寄りになる。
        let net = try #require(court.imagePoint(for: CGPoint(x: 0.5, y: 0.5)))
        #expect(net.y > 0.5)
    }

    @Test func rejectsDegenerateCorners() {
        #expect(CourtPlane(corners: []) == nil)
        #expect(CourtPlane(corners: Array(trapezoid.prefix(3))) == nil)
        #expect(CourtPlane(corners: [CGPoint](repeating: CGPoint(x: 0.5, y: 0.5), count: 4)) == nil)
    }

    @Test func pickleballLinesStayInsideCourtAndIncludeKitchen() {
        let lines = CourtPlane.pickleballLines
        #expect(lines.count == 8)
        let points = lines.flatMap { [$0.start, $0.end] }
        #expect(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        // キッチンの線は、ネットから 2.13 m（コートの長さ 13.41 m）。
        let kitchenYs = Set(lines.filter { $0.start.y == $0.end.y && $0.start.y != 0 && $0.start.y != 1 }.map(\.start.y))
        #expect(kitchenYs.count == 2)
        #expect(kitchenYs.allSatisfy { abs(abs($0 - 0.5) - 2.1336 / 13.4112) < 1e-9 })
        #expect(CourtPlane.net.start.y == 0.5)
    }
}
