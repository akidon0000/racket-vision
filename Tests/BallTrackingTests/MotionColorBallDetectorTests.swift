@testable import BallTracking
import CoreGraphics
import CoreVideo
import Testing

struct MotionColorBallDetectorTests {
    private let frameDuration = 1.0 / 60

    /// 止まった黄色の四角と、1 フレームに (12, 4) 画素ずつ動く球。
    private func ballFrame(_ index: Int, background: SyntheticColor = .court) -> SyntheticFrame {
        var image = SyntheticFrame(background: background)
        image.fillRect(x: 500, y: 40, width: 30, height: 30, color: .ball)
        image.fillCircle(centerX: 100 + 12 * Double(index), centerY: 100 + 4 * Double(index), radius: 4, color: .ball)
        return image
    }

    private func detect(_ detector: MotionColorBallDetector, _ image: SyntheticFrame, index: Int) throws -> BallFrameOutcome {
        try detector.detect(in: image.pixelBuffer(), at: Double(index) * frameDuration)
    }

    @Test func tracksMovingBallInNormalizedCoordinates() throws {
        let detector = MotionColorBallDetector()
        let outcomes = try (0..<12).map { try detect(detector, ballFrame($0), index: $0) }
        // 最初の 2 枚は比べる相手が無い。3 枚目から候補が出て、0.08 秒たつ 8 枚目（番号 7）から球を出す。
        #expect(outcomes[0..<7].allSatisfy { $0.ball == nil })
        for index in 7..<12 {
            let ball = try #require(outcomes[index].ball)
            // 正規化座標は左下が原点。画素（左上が原点）に戻して比べる。
            #expect(abs(ball.center.x * 640 - (100 + 12 * Double(index))) <= 1.5)
            #expect(abs((1 - ball.center.y) * 360 - (100 + 4 * Double(index))) <= 1.5)
            #expect(abs(ball.radius * 640 - 4) <= 1)
            #expect(outcomes[index].imageSize == CGSize(width: 640, height: 360))
        }
    }

    @Test func findsOrangeBallOnlyAfterSwitchingColors() throws {
        func orangeFrame(_ index: Int) -> SyntheticFrame {
            var image = SyntheticFrame()
            image.fillCircle(centerX: 100 + 12 * Double(index), centerY: 100 + 4 * Double(index), radius: 4, color: .orangeBall)
            return image
        }
        let detector = MotionColorBallDetector()
        let before = try (0..<12).map { try detect(detector, orangeFrame($0), index: $0) }
        #expect(before.allSatisfy { $0.ball == nil })

        detector.setColors(.orange)
        #expect(detector.colors == .orange)
        let after = try (12..<24).map { try detect(detector, orangeFrame($0), index: $0) }
        let ball = try #require(after.last?.ball)
        #expect(abs(ball.center.x * 640 - (100 + 12 * 23)) <= 1.5)
    }

    @Test func dropsTrackOnSceneChange() throws {
        let detector = MotionColorBallDetector()
        for index in 0..<10 {
            _ = try detect(detector, ballFrame(index), index: index)
        }
        let cut = try detect(detector, ballFrame(10, background: .gray), index: 10)
        #expect(cut.sceneChanged)
        #expect(cut.ball == nil)
        let next = try detect(detector, ballFrame(11, background: .gray), index: 11)
        #expect(!next.sceneChanged)
        #expect(next.ball == nil)
    }

    @Test func treatsWholeFrameOfBallColorAsSceneChange() throws {
        let detector = MotionColorBallDetector()
        _ = try detect(detector, SyntheticFrame(), index: 0)
        _ = try detect(detector, SyntheticFrame(), index: 1)
        let outcome = try detect(detector, SyntheticFrame(background: .ball), index: 2)
        #expect(outcome.sceneChanged)
        #expect(outcome.ball == nil)
        #expect(outcome.candidates.isEmpty)
    }

    @Test func returnsNoBallForOtherPixelFormats() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &buffer)
        let outcome = try MotionColorBallDetector().detect(in: #require(buffer), at: 0)
        #expect(outcome.ball == nil)
        #expect(outcome.imageSize == CGSize(width: 64, height: 64))
    }

    @Test func survivesChangeOfFrameSize() throws {
        let detector = MotionColorBallDetector()
        for index in 0..<3 {
            _ = try detect(detector, ballFrame(index), index: index)
        }
        // 途中で大きさが変わる。覚えているフレームとは比べずに、やり直す。
        let small = try detect(detector, SyntheticFrame(width: 320, height: 180), index: 3)
        #expect(small.ball == nil)
        #expect(small.candidates.isEmpty)
        _ = try detect(detector, SyntheticFrame(width: 320, height: 180), index: 4)
        _ = try detect(detector, ballFrame(5), index: 5)
    }

    @Test func returnsNoBallForTinyFrames() throws {
        let outcome = try MotionColorBallDetector().detect(in: SyntheticFrame(width: 2, height: 2).pixelBuffer(), at: 0)
        #expect(outcome.ball == nil)
    }

    @Test func resetForgetsFrames() throws {
        let detector = MotionColorBallDetector()
        for index in 0..<10 {
            _ = try detect(detector, ballFrame(index), index: index)
        }
        detector.reset()
        // やり直した直後は、比べる相手が無いので候補も出ない。
        let outcome = try detect(detector, ballFrame(10), index: 10)
        #expect(outcome.ball == nil)
        #expect(outcome.candidates.isEmpty)
    }

    @Test func dropsBallsOutsideCourtRegion() throws {
        let detector = MotionColorBallDetector()
        // 範囲は画面の右半分（正規化座標で x が 0.5 から 1）。球は左側にあるので、出ない。
        detector.setCourtRegion([CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 1)], margin: 0)
        let outcomes = try (0..<12).map { try detect(detector, ballFrame($0), index: $0) }
        #expect(outcomes.allSatisfy { $0.ball == nil })
        #expect(outcomes.allSatisfy { $0.candidates.isEmpty })
    }

    @Test func keepsBallsInsideCourtRegion() throws {
        let detector = MotionColorBallDetector()
        detector.setCourtRegion([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)], margin: 0)
        let outcomes = try (0..<12).map { try detect(detector, ballFrame($0), index: $0) }
        #expect(outcomes[11].ball != nil)
    }

    @Test func keepsBallsInTheAirAboveCourtRegion() throws {
        // コートは画面の下半分（正規化座標の y が 0〜0.4）。球は y が 0.6〜0.75 のあたりを飛ぶ。
        let court = [CGPoint(x: 0, y: 0.4), CGPoint(x: 1, y: 0.4), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]
        let flat = MotionColorBallDetector()
        flat.setCourtRegion(court, margin: 0, airHeight: 0)
        let raised = MotionColorBallDetector()
        raised.setCourtRegion(court, margin: 0, airHeight: 0.6)
        var flatFound = false
        var raisedFound = false
        for index in 0..<12 {
            flatFound = try detect(flat, ballFrame(index), index: index).ball != nil || flatFound
            raisedFound = try detect(raised, ballFrame(index), index: index).ball != nil || raisedFound
        }
        #expect(!flatFound)
        #expect(raisedFound)
    }

    @Test func findsPaleBallOnlyWhenCourtRegionIsSet() throws {
        // 小さく明るく写って、薄い緑になった球。観客や服も拾いやすい色なので、コートの範囲で絞れるときだけ球にする。
        let pale = SyntheticColor(red: 180, green: 225, blue: 176)
        func frame(_ index: Int) -> SyntheticFrame {
            var image = SyntheticFrame()
            image.fillCircle(centerX: 100 + 12 * Double(index), centerY: 100 + 4 * Double(index), radius: 4, color: pale)
            return image
        }
        let free = MotionColorBallDetector()
        let gated = MotionColorBallDetector()
        gated.setCourtRegion([CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)])
        let freeOutcomes = try (0..<12).map { try detect(free, frame($0), index: $0) }
        let gatedOutcomes = try (0..<12).map { try detect(gated, frame($0), index: $0) }
        #expect(freeOutcomes.allSatisfy { $0.ball == nil })
        #expect(gatedOutcomes[11].ball != nil)
    }

    @Test func dropsEverythingWhenRegionIsEmpty() throws {
        let detector = MotionColorBallDetector()
        detector.setCourtRegion([], margin: 0)
        let outcomes = try (0..<12).map { try detect(detector, ballFrame($0), index: $0) }
        #expect(outcomes.allSatisfy { $0.ball == nil })
    }
}
