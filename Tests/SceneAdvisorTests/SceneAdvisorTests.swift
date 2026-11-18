import BallTracking
import CourtFit
import Foundation
@testable import SceneAdvisor
import Testing

struct JevClientTests {
    @Test func encodesImageAndQuestions() throws {
        let body = try JevClient.body(
            model: "jev-1.14.0", jpeg: Data([1, 2, 3]),
            questions: ["court": .yesNo("Is a court visible in `photo`?"), "color": .choice("Which color?", options: ["white": "white"])]
        )
        let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(root["model"] as? String == "jev-1.14.0")
        #expect((root["state"] as? [String: String])?["photo"] == JevClient.imageReference)
        let asset = try #require((root["assets"] as? [String: [String: String]])?[JevClient.imageReference])
        #expect(asset["data_base64"] == "AQID")
        #expect(asset["format"] == "jpg")
        let questions = try #require(root["questions"] as? [String: [String: Any]])
        #expect(questions["court"]?["type"] as? String == "noul")
        #expect(questions["color"]?["type"] as? String == "choice")
        #expect((questions["color"]?["criteria"] as? [String: String])?["white"] == "white")
    }

    @Test func decodesYesNoAndChoiceAnswers() throws {
        let json = """
        {"model": "jev-1.14.0", "answers": {
          "court": {"type": "noul", "noul": 0.9},
          "color": {"type": "choice", "choice": "orange", "confidence": 0.8, "probabilities": {"orange": 0.9, "white": 0.1}},
          "box": {"type": "box", "box": {"top": 0, "bottom": 1, "left": 0, "right": 1}, "confidence": 0.3}
        }, "usage": {"input_tokens": 10, "output_tokens": 2}}
        """
        let answers = try JevClient.answers(from: Data(json.utf8))
        #expect(answers["court"] == .yesNo(0.9))
        #expect(answers["color"] == .choice("orange", probabilities: ["orange": 0.9, "white": 0.1]))
        // 使わない型（枠）は読み飛ばす。
        #expect(answers["box"] == nil)
    }

    @Test func rejectsResponseWithoutAnswers() {
        #expect(throws: JevClient.Failure.self) { try JevClient.answers(from: Data("{}".utf8)) }
    }
}

struct SceneAdviceSummaryTests {
    private func advice(ballVisible: Double, ball: [String: Double], line: [String: Double] = ["white": 1], court: Double = 0.9) -> SceneAdvice {
        SceneAdvice(courtVisible: court, ballVisible: ballVisible, ballColors: ball, lineColors: line)
    }

    @Test func weightsBallColorByBallVisibility() {
        // 1min-10 と同じ形: 球が見える 2 枚は白、見えにくい 1 枚は黄緑と答えた。
        let summary = SceneAdviceSummary([
            advice(ballVisible: 0.71, ball: ["white": 0.86, "yellow_green": 0.1, "other": 0.04]),
            advice(ballVisible: 0.78, ball: ["white": 0.64, "yellow_green": 0.3, "other": 0.06]),
            advice(ballVisible: 0.3, ball: ["yellow_green": 0.85, "other": 0.15])
        ])
        #expect(summary.ballColors() == .pale)
    }

    @Test func keepsCurrentColorsWhenBallIsNotSeen() {
        let summary = SceneAdviceSummary([advice(ballVisible: 0.2, ball: ["orange": 0.6, "other": 0.4])])
        #expect(summary.ballColors() == nil)
    }

    @Test func picksLineColorAndIgnoresColorsWithoutRidge() {
        let yellow = SceneAdviceSummary([advice(ballVisible: 0.5, ball: [:], line: ["yellow": 0.77, "white": 0.2])])
        #expect(yellow.lineColor() == .yellow)
        let green = SceneAdviceSummary([advice(ballVisible: 0.5, ball: [:], line: ["green": 0.9])])
        #expect(green.lineColor() == nil)
        // コートが写っていない絵の答えは、ほとんど数えない。
        let noCourt = SceneAdviceSummary([advice(ballVisible: 0.5, ball: [:], line: ["yellow": 0.9], court: 0.07)])
        #expect(noCourt.lineColor() == nil)
    }
}
