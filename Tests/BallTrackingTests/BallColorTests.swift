@testable import BallTracking
import Testing

struct BallColorTests {
    @Test func yellowGreenMatchesBallColor() {
        #expect(BallColor.yellowGreen.matches(red: 210, green: 230, blue: 80))
        // 少し暗く写った球。
        #expect(BallColor.yellowGreen.matches(red: 150, green: 170, blue: 60))
    }

    @Test func yellowGreenRejectsCourtAndPeople() {
        // 青いコート、白線、灰色、肌、暗い黄色。
        #expect(!BallColor.yellowGreen.matches(red: 40, green: 80, blue: 200))
        #expect(!BallColor.yellowGreen.matches(red: 255, green: 255, blue: 255))
        #expect(!BallColor.yellowGreen.matches(red: 120, green: 120, blue: 120))
        #expect(!BallColor.yellowGreen.matches(red: 220, green: 170, blue: 140))
        #expect(!BallColor.yellowGreen.matches(red: 60, green: 70, blue: 20))
    }

    @Test func yellowGreenRejectsYellowClothingAndWoodFloor() {
        // 黄色いパーカーと木の床は、色相が 40 度付近。球は 65〜75 度。
        #expect(!BallColor.yellowGreen.matches(red: 200, green: 170, blue: 90))
        #expect(!BallColor.yellowGreen.matches(red: 200, green: 160, blue: 80))
    }

    @Test func yellowGreenRejectsPaleBlendsAtEdges() {
        // 肌と青いコートの境目にできる、彩度の低い黄緑がかった色。
        #expect(!BallColor.yellowGreen.matches(red: 170, green: 200, blue: 140))
        #expect(!BallColor.yellowGreen.matches(red: 150, green: 175, blue: 130))
    }

    @Test func customHueRangeMatchesOrange() {
        let orange = BallColor(hueRange: 15...40, minimumSaturation: 0.4, minimumBrightness: 0.5)
        #expect(orange.matches(red: 240, green: 130, blue: 30))
        #expect(!orange.matches(red: 210, green: 230, blue: 80))
    }

    @Test func yellowGreenMatchesBrightBallWithLowSaturation() {
        // 明るく写って、白に近づいた球。
        #expect(BallColor.yellowGreen.matches(red: 203, green: 252, blue: 164))
        // 同じ薄さでも、暗い画素（肌と青いコートの境目など）は通さない。
        #expect(!BallColor.yellowGreen.matches(red: 150, green: 186, blue: 121))
    }

    @Test func orangeMatchesBallButNotSkinOrYellowWall() {
        // 1min-09 の球（色相 13〜16 度、鮮やかさ 0.7 前後）。
        #expect(BallColor.orange.matches(red: 204, green: 94, blue: 57))
        // 顔や肌（色相 24 度、鮮やかさ 0.55）と、黄色い壁（色相 44 度）。
        #expect(!BallColor.orange.matches(red: 178, green: 119, blue: 80))
        #expect(!BallColor.orange.matches(red: 191, green: 166, blue: 96))
        // 黄緑の球は通さない。
        #expect(!BallColor.orange.matches(red: 210, green: 230, blue: 80))
    }

    @Test func paleMatchesColorlessBrightPixelsOnly() {
        // 1min-10 の白っぽい球は、灰色や、わずかに青みのある明るい色に写る。
        #expect(BallColor.pale.matches(red: 150, green: 150, blue: 150))
        #expect(BallColor.pale.matches(red: 200, green: 210, blue: 220))
        // 色のある画素と、暗い画素は通さない。
        #expect(!BallColor.pale.matches(red: 204, green: 94, blue: 57))
        #expect(!BallColor.pale.matches(red: 40, green: 80, blue: 200))
        #expect(!BallColor.pale.matches(red: 100, green: 100, blue: 100))
        // 黄緑の球の色は、色の無い画素を通さない（今までどおり）。
        #expect(!BallColor.yellowGreen.matches(red: 255, green: 255, blue: 255))
    }

    @Test func colorSetsAreNamedLikeJevAnswers() {
        #expect(BallColorSet(name: "yellow_green") == .yellowGreen)
        #expect(BallColorSet(name: "orange") == .orange)
        #expect(BallColorSet(name: "white") == .pale)
        #expect(BallColorSet(name: "pink") == nil)
    }

    @Test func yellowGreenPaleMatchesFaintGreenBall() {
        // 小さく写って、背景が混じった球。
        #expect(BallColor.yellowGreenPale.matches(red: 180, green: 225, blue: 176))
        #expect(!BallColor.yellowGreen.matches(red: 180, green: 225, blue: 176))
        // 青いコートと白線は、薄い色でも通さない。
        #expect(!BallColor.yellowGreenPale.matches(red: 130, green: 190, blue: 230))
        #expect(!BallColor.yellowGreenPale.matches(red: 250, green: 250, blue: 250))
    }
}
