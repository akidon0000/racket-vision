import AVFoundation
import DeviceSimulation
import Foundation

/// 選んだ動画と機種、流した結果、再生の時刻を持つ。
@MainActor
final class LabModel: ObservableObject {
    /// アプリに入っている動画。
    let videos: [URL] = (Bundle.main.urls(forResourcesWithExtension: "mp4", subdirectory: nil) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    /// アプリに入っている機種の一覧。
    let profiles = DeviceProfile.bundled()

    @Published var video: URL? {
        didSet { loadVideo() }
    }
    @Published var left: DeviceProfile?
    @Published var right: DeviceProfile?
    /// 機種ごとの、流した結果。
    @Published private(set) var results: [String: DeviceRunResult] = [:]
    /// 機種ごとの、流している途中の割合（0〜1）。
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var player = AVPlayer()

    private var timeObserver: Any?
    private var runTask: Task<Void, Never>?

    init() {
        left = profiles.first
        right = profiles.count > 1 ? profiles[profiles.count - 1] : profiles.first
        video = videos.first
        loadVideo()
    }

    /// これから流す機種（流す順を待っている）か。
    func isWaiting(_ id: String) -> Bool {
        waiting.contains(id)
    }

    /// 流す順を待っている機種。
    @Published private(set) var waiting = Set<String>()

    /// 選んだ機種の結果。まだ流していなければ nil。
    func result(for profile: DeviceProfile?) -> DeviceRunResult? {
        profile.flatMap { results[$0.id] }
    }

    /// 選んだ 2 つの機種で、動画を流す。結果は、機種ごとに順に出る。
    func run() {
        guard let video else { return }
        let selected = [left, right].compactMap { $0 }.reduce(into: [DeviceProfile]()) { list, profile in
            if !list.contains(profile) {
                list.append(profile)
            }
        }
        runTask?.cancel()
        results = [:]
        progress = [:]
        waiting = Set(selected.map(\.id))
        runTask = Task { [weak self] in
            for profile in selected {
                let id = profile.id
                self?.waiting.remove(id)
                self?.progress[id] = 0
                // 検出は重いので、画面とは別のところで動かす。
                let result = await Task.detached(priority: .userInitiated) {
                    try? await DeviceSimulator(profile: profile).run(video: video) { value in
                        Task { @MainActor [weak self] in self?.progress[id] = value }
                    }
                }.value
                guard !Task.isCancelled else { return }
                self?.progress[id] = nil
                if let result {
                    self?.results[id] = result
                }
            }
        }
    }

    private func loadVideo() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        runTask?.cancel()
        results = [:]
        progress = [:]
        waiting = []
        currentTime = 0
        guard let video else { return }
        player = AVPlayer(url: video)
        player.isMuted = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.currentTime = time.seconds }
        }
    }
}
