@testable import CourtFit
import simd
import Testing

struct CourtModelTests {
    @Test func hasTwelveKeypointsAndEightLines() {
        #expect(CourtKeypoint.allCases.count == 12)
        #expect(CourtModel.lines.count == 8)
    }

    @Test func keypointsMatchCourtSize() {
        let model = CourtModel.pickleball
        #expect(model.position(of: .nearLeftCorner) == SIMD2(-3.048, -6.7056))
        #expect(model.position(of: .nearRightCorner) == SIMD2(3.048, -6.7056))
        #expect(model.position(of: .farRightCorner) == SIMD2(3.048, 6.7056))
        #expect(model.position(of: .farLeftCorner) == SIMD2(-3.048, 6.7056))
        #expect(model.position(of: .nearKitchenCenter) == SIMD2(0, -2.1336))
        #expect(model.position(of: .farKitchenRight) == SIMD2(3.048, 2.1336))
        #expect(model.position(of: .farBaselineCenter) == SIMD2(0, 6.7056))
    }
}
