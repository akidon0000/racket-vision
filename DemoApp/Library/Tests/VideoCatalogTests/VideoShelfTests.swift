import Foundation
import Testing
import VideoCatalog

struct VideoShelfTests {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/videos/\(name)") }

    @Test func groupsOwnVideosByDateAndSamplesLast() {
        let shelves = VideoShelf.shelves(for: [
            url("pickleball-play-demo-1min-02.mp4"),
            url("20261119-4992-2.mp4"),
            url("pickleball-play-demo-1min-01.mp4"),
            url("20261119-4992-1.mp4"),
            url("20261201-5100-1.mp4")
        ])
        #expect(shelves.map(\.title) == ["2026-12-01 撮影", "2026-11-19 撮影", "サンプル動画（ネット）"])
        #expect(shelves[1].videos.map(\.lastPathComponent) == ["20261119-4992-1.mp4", "20261119-4992-2.mp4"])
        #expect(shelves[2].videos.map(\.lastPathComponent) == ["pickleball-play-demo-1min-01.mp4", "pickleball-play-demo-1min-02.mp4"])
    }

    @Test func treatsNamesWithoutDatePrefixAsSamples() {
        // 数字で始まっても、8 桁の後に `-` が無ければ日付とみなさない。
        let shelves = VideoShelf.shelves(for: [url("123456789.mp4"), url("2026111-x.mp4")])
        #expect(shelves.map(\.title) == ["サンプル動画（ネット）"])
    }

    @Test func returnsNoShelvesForNoVideos() {
        #expect(VideoShelf.shelves(for: []).isEmpty)
    }

    @Test func putsFeaturedShelfFirstInGivenOrder() {
        let featured = FeaturedVideos(title: "精度が良い動画", videos: [
            .init(name: "20261119-4992", caption: "手前 2 人 90%"),
            .init(name: "20261119-9999"),
            .init(name: "20261119-4990")
        ])
        let shelves = VideoShelf.shelves(
            for: [url("20261119-4990.mp4"), url("20261119-4992.mp4"), url("pickleball-play-demo-1min-01.mp4")],
            featured: featured
        )
        #expect(shelves.map(\.title) == ["精度が良い動画", "2026-11-19 撮影", "サンプル動画（ネット）"])
        // 選んだ順に並べ、アプリに入っていない動画は飛ばす。撮った日の見出しにも残す。
        #expect(shelves[0].videos.map(\.lastPathComponent) == ["20261119-4992.mp4", "20261119-4990.mp4"])
        #expect(shelves[0].captions[url("20261119-4992.mp4")] == "手前 2 人 90%")
        #expect(shelves[0].captions[url("20261119-4990.mp4")] == nil)
        #expect(shelves[1].videos.count == 2)
    }

    @Test func skipsFeaturedShelfWhenNoneOfItsVideosAreBundled() {
        let featured = FeaturedVideos(title: "精度が良い動画", videos: [.init(name: "20261119-9999")])
        #expect(VideoShelf.shelves(for: [url("20261119-4990.mp4")], featured: featured).map(\.title) == ["2026-11-19 撮影"])
    }

    @Test func decodesFeaturedVideosFromJSON() throws {
        let json = #"{"title":"上位","videos":[{"name":"20261119-5012","caption":"手前 2 人 95%"},{"name":"20261119-4990"}]}"#
        let decoded = try JSONDecoder().decode(FeaturedVideos.self, from: Data(json.utf8))
        #expect(decoded == FeaturedVideos(title: "上位", videos: [
            .init(name: "20261119-5012", caption: "手前 2 人 95%"), .init(name: "20261119-4990")
        ]))
        #expect(FeaturedVideos(contentsOf: nil) == nil)
    }
}
