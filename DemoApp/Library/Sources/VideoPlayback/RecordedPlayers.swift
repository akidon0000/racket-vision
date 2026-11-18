import CoreGraphics
import Foundation
import PlayerPose

/// macOS で前もって求めた、選手の検出の記録。動画と同じフォルダの `<動画の名前>.players.json` から読む。
///
/// iOS のシミュレーターでは、Vision の骨格検出が動かない。そこで、その場の検出が動かないときは、この記録を
/// 再生の時刻に合わせて出す。記録は、`reportsPlayersOnDemoVideos`（`Tests/PlayerPoseTests`）が書き出す JSON を、
/// 名前を変えて置いたもの。手順は `docs/accuracy/pose.md`。
struct RecordedPlayers {
    /// 記録の 1 フレーム（書き出しの JSON の、読むところだけ）。
    private struct Frame: Decodable {
        var seconds: Double
        var players: [Player]
    }

    private struct Player: Decodable {
        var id: Int
        var firstSeen: Double
        var isDetected: Bool
        var side: String?
        /// コートの上の位置 [横, 縦]。
        var court: [Double]?
        /// 関節の名前から [x, y, 確からしさ]。
        var joints: [String: [Double]]
    }

    private let frames: [Frame]
    /// 記録のフレームの間隔より長く離れた時刻には、出さない（秒）。
    private let tolerance: Double = 0.3

    /// `video` と同じ場所にある記録を読む。無いとき、読めないときは nil。
    init?(video: URL) {
        let url = video.deletingPathExtension().appendingPathExtension("players.json")
        guard let data = try? Data(contentsOf: url),
              let frames = try? JSONDecoder().decode([Frame].self, from: data), !frames.isEmpty else { return nil }
        self.frames = frames.sorted { $0.seconds < $1.seconds }
    }

    /// `time`（秒）の時点の選手。その時刻より前で、いちばん近い記録のフレームを使う。
    func players(at time: Double) -> [CourtPlayer] {
        // 時刻の順に並んでいるので、二分探索で、time 以下の最後のフレームを探す。
        var low = 0
        var high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].seconds <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0, time - frames[low - 1].seconds <= tolerance else { return [] }
        return frames[low - 1].players.map(courtPlayer)
    }

    private func courtPlayer(_ player: Player) -> CourtPlayer {
        var joints = [PoseJoint: PoseKeypoint]()
        for (name, values) in player.joints {
            guard let joint = PoseJoint(rawValue: name), values.count >= 3 else { continue }
            joints[joint] = PoseKeypoint(position: CGPoint(x: values[0], y: values[1]), confidence: Float(values[2]))
        }
        return CourtPlayer(
            id: player.id,
            pose: BodyPose(joints: joints),
            side: player.side.flatMap(CourtSide.init(rawValue:)),
            courtPosition: player.court.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil },
            firstSeen: player.firstSeen,
            isDetected: player.isDetected
        )
    }
}
