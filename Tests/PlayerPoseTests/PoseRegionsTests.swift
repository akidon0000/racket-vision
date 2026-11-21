import CoreGraphics
import PlayerPose
import Testing

struct PoseRegionsTests {
    @Test func tilesCoverPlayersOnBothSides() throws {
        let court = try #require(CourtPlane(corners: [
            CGPoint(x: 0.4, y: 0.7), CGPoint(x: 0.6, y: 0.7), CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.2, y: 0.2)
        ]))
        let tiles = PoseRegions().tiles(for: court, aspect: 16.0 / 9)
        #expect(tiles.count >= 2)
        // 奥のベースラインに立つ選手の頭のあたりと、手前のベースラインに立つ選手の足元が、どれかの範囲に入る。
        #expect(tiles.contains { $0.contains(CGPoint(x: 0.5, y: 0.78)) })
        #expect(tiles.contains { $0.contains(CGPoint(x: 0.5, y: 0.21)) })
        // 範囲は画面の中に収まる。
        #expect(tiles.allSatisfy { $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= 1.0001 && $0.maxY <= 1.0001 })
    }

    /// ベースラインの 3 m 後ろ、高さ 1.5 m から撮ると、ベースラインの後ろ 3.4 m（範囲を広げる先）はカメラの後ろになる。
    /// そのときも、手前の半面に立つ選手（キッチンの線の近く、サイドラインの外）の足元が、範囲に入る。
    @Test func tilesCoverNearPlayersWhenCameraIsBehindTheBackMargin() throws {
        let court = try #require(CourtPlane(corners: [
            CGPoint(x: 0.4218, y: 0.5271), CGPoint(x: 0.5953, y: 0.5259), CGPoint(x: 0.9263, y: 0.1894), CGPoint(x: 0.0273, y: 0.2207)
        ]))
        let tiles = PoseRegions().tiles(for: court, aspect: 16.0 / 9)
        #expect(tiles.contains { $0.contains(CGPoint(x: 0.3986, y: 0.4328)) })
        #expect(tiles.contains { $0.contains(CGPoint(x: 0.0631, y: 0.3533)) })
        // 手前のベースラインの中央の足元（画面の下のほう）も入る。
        #expect(tiles.contains { $0.contains(CGPoint(x: 0.48, y: 0.21)) })
    }

    @Test func gridSplitsLongSideIntoMoreTiles() {
        let landscape = PoseRegions().grid(aspect: 16.0 / 9)
        let portrait = PoseRegions().grid(aspect: 9.0 / 16)
        // 最初の 1 つは画面の全体。
        #expect(landscape.first == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(landscape.count > 3)
        #expect(portrait.count == landscape.count)
        // 横長の映像は横に、縦長の映像は縦に、多く分ける。
        #expect(Set(landscape.dropFirst().map(\.minX)).count > Set(landscape.dropFirst().map(\.minY)).count)
        #expect(Set(portrait.dropFirst().map(\.minY)).count > Set(portrait.dropFirst().map(\.minX)).count)
    }
}
