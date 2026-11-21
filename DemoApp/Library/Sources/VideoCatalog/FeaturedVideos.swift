import Foundation

/// 一覧の一番上に出す、選んだ動画（精度の計測で結果が良かった動画など）。アプリに入れた JSON から読む。
///
/// ```json
/// { "title": "精度が良い動画（上位 5 本）",
///   "videos": [{ "name": "20261119-5012", "caption": "手前 2 人 95%・コート 100%" }] }
/// ```
///
/// `name` は拡張子を除いたファイル名。アプリに入っていない動画は飛ばす。
public struct FeaturedVideos: Decodable, Equatable, Sendable {
    public struct Entry: Decodable, Equatable, Sendable {
        public let name: String
        public let caption: String?

        public init(name: String, caption: String? = nil) {
            self.name = name
            self.caption = caption
        }
    }

    public let title: String
    public let videos: [Entry]

    public init(title: String, videos: [Entry]) {
        self.title = title
        self.videos = videos
    }

    /// JSON のファイルから読む。無いか、読めなければ nil。
    public init?(contentsOf url: URL?) {
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(FeaturedVideos.self, from: data) else { return nil }
        self = decoded
    }

    /// 選んだ順の見出しを作る。入っている動画が 1 本も無ければ nil。
    public func shelf(in videos: [URL]) -> VideoShelf? {
        var captions = [URL: String]()
        let picked: [URL] = self.videos.compactMap { entry in
            guard let url = videos.first(where: { $0.deletingPathExtension().lastPathComponent == entry.name }) else { return nil }
            captions[url] = entry.caption
            return url
        }
        guard !picked.isEmpty else { return nil }
        return VideoShelf(title: title, videos: picked, captions: captions)
    }
}
