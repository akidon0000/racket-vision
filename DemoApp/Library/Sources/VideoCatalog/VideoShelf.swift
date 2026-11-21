import Foundation

/// 動画の一覧の、見出しごとのまとまり。動画は、ファイル名で分ける。
///
/// - 選んだ動画（`FeaturedVideos`）: 渡したときだけ、一番上にまとめる。
/// - `20261119-…`（8 桁の日付で始まる）: 自分たちで撮った動画。日付ごとにまとめ、新しい日付を上にする。
/// - それ以外（`pickleball-play-demo-…` など）: ネットから集めたサンプル動画。最後にまとめる。
public struct VideoShelf: Identifiable, Equatable, Sendable {
    public let title: String
    public let videos: [URL]
    /// 動画の名前の下に出す説明（無い動画は出さない）。
    public let captions: [URL: String]
    public var id: String { title }

    public init(title: String, videos: [URL], captions: [URL: String] = [:]) {
        self.title = title
        self.videos = videos
        self.captions = captions
    }

    /// 動画を見出しごとに分ける。見出しの中は、ファイル名の順に並べる。
    /// `featured` を渡すと、その見出しを一番上に足す（選んだ動画は、撮った日の見出しにも残す）。
    public static func shelves(for videos: [URL], featured: FeaturedVideos? = nil) -> [VideoShelf] {
        var byDate: [String: [URL]] = [:]
        var samples: [URL] = []
        for video in videos {
            if let date = shootingDate(of: video) {
                byDate[date, default: []].append(video)
            } else {
                samples.append(video)
            }
        }
        let sortedByName: ([URL]) -> [URL] = { $0.sorted { $0.lastPathComponent < $1.lastPathComponent } }
        var shelves = featured?.shelf(in: videos).map { [$0] } ?? []
        shelves += byDate.keys.sorted(by: >).map { date in
            VideoShelf(title: "\(date) 撮影", videos: sortedByName(byDate[date] ?? []))
        }
        if !samples.isEmpty {
            shelves.append(VideoShelf(title: "サンプル動画（ネット）", videos: sortedByName(samples)))
        }
        return shelves
    }

    /// ファイル名が 8 桁の日付と `-` で始まれば、`2026-11-19` の形で返す。
    static func shootingDate(of video: URL) -> String? {
        let name = video.lastPathComponent
        let digits = name.prefix(8)
        guard digits.count == 8, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              name.dropFirst(8).first == "-" else { return nil }
        let year = digits.prefix(4)
        let month = digits.dropFirst(4).prefix(2)
        let day = digits.suffix(2)
        return "\(year)-\(month)-\(day)"
    }
}
