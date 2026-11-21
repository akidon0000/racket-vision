import PlayerPose

/// 1 フレームぶんの書き出し（JSON）。
struct PlayerFrameExport: Encodable {
    /// 選手 1 人。
    struct Player: Encodable {
        var id: Int
        /// この番号で追い始めた時刻（秒）。
        var firstSeen: Double
        /// このフレームで骨格が見つかったか（false は、少し前の骨格をそのまま出している）。
        var isDetected: Bool
        var side: String?
        /// コートの上の位置 [横, 縦]（0〜1）。
        var court: [Double]?
        /// 足元 [x, y]（正規化座標、左下が原点）。
        var foot: [Double]?
        /// 胴の色と腿の色 [赤, 緑, 青]（0〜1）。
        var torso: [Double]?
        var legs: [Double]?
        /// 関節の名前から [x, y, 確からしさ]。
        var joints: [String: [Double]]
    }

    var video: String
    var seconds: Double
    var imageWidth: Int
    var imageHeight: Int
    var players: [Player]
    /// 見つかった人の数（選手に選ばなかった人も入る）。
    var poseCount: Int
    var courtFound: Bool
    var milliseconds: Double

    init(video: String, outcome: CourtPlayersOutcome, courtFound: Bool) {
        self.video = video
        seconds = outcome.time
        imageWidth = Int(outcome.imageSize.width)
        imageHeight = Int(outcome.imageSize.height)
        players = outcome.players.map { player in
            Player(
                id: player.id,
                firstSeen: player.firstSeen,
                isDetected: player.isDetected,
                side: player.side?.rawValue,
                court: player.courtPosition.map { [Double($0.x), Double($0.y)] },
                foot: player.pose.footPoint.map { [Double($0.x), Double($0.y)] },
                torso: player.appearance?.torso.map { [$0.x, $0.y, $0.z] },
                legs: player.appearance?.legs.map { [$0.x, $0.y, $0.z] },
                joints: Dictionary(uniqueKeysWithValues: player.pose.joints.map { joint, keypoint in
                    (joint.rawValue, [Double(keypoint.position.x), Double(keypoint.position.y), Double(keypoint.confidence)])
                })
            )
        }
        poseCount = outcome.poses.count
        self.courtFound = courtFound
        milliseconds = outcome.durationMilliseconds
    }
}
