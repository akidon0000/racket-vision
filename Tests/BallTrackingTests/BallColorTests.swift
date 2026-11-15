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

    @Test func customHueRangeMatchesOrange() {
        let orange = BallColor(hueRange: 15...40, minimumSaturation: 0.4, minimumBrightness: 0.5)
        #expect(orange.matches(red: 240, green: 130, blue: 30))
        #expect(!orange.matches(red: 210, green: 230, blue: 80))
    }
}
