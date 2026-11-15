@testable import BallTracking

/// 1 フレームぶんの書き出し（JSON）。
struct BallFrameExport: Encodable {
    var video: String
    var seconds: Double
    var imageWidth: Int
    var imageHeight: Int
    /// 球の中心 [x, y]（正規化座標、左下が原点）。球が無ければ nil。
    var ball: [Double]?
    /// 球の半径（映像の幅に対する割合）。
    var radius: Double?
    var confidence: Double?
    /// ラリーの番号（0 始まり）。
    var rally: Int
    var sceneChanged: Bool
    var milliseconds: Double

    init(video: String, outcome: BallFrameOutcome, rally: Int) {
        self.video = video
        seconds = outcome.time
        imageWidth = Int(outcome.imageSize.width)
        imageHeight = Int(outcome.imageSize.height)
        ball = outcome.ball.map { [Double($0.center.x), Double($0.center.y)] }
        radius = outcome.ball.map { Double($0.radius) }
        confidence = outcome.ball.map { Double($0.confidence) }
        self.rally = rally
        sceneChanged = outcome.sceneChanged
        milliseconds = outcome.durationMilliseconds
    }
}
