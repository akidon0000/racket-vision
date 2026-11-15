@testable import CourtFit
import CoreVideo
import ImageIO
import Testing

/// 検出の中身を使わず、呼ばれたことだけを記録する方式（テスト用）。
private struct StubDetector: CourtRectangleDetector {
    let method: CourtDetectionMethod

    func detect(in _: CVPixelBuffer, orientation _: CGImagePropertyOrientation) -> DetectionOutcome {
        DetectionOutcome(method: method, quads: [], confidence: nil, durationMilliseconds: 0, imageSize: .zero)
    }
}

private func makePixelBuffer() throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_32BGRA, nil, &buffer)
    return try #require(status == kCVReturnSuccess ? buffer : nil)
}

struct CourtAnalyzerTests {
    @Test func defaultMethodsAreOnExceptHeavyOnes() {
        let switches = CourtMethodSwitches()
        for method in CourtDetectionMethod.builtIn {
            #expect(switches.isEnabled(method) == !CourtMethodSwitches.offByDefault.contains(method))
        }
    }

    @Test func switchedOffMethodIsNotRun() throws {
        let switches = CourtMethodSwitches()
        let analyzer = CourtAnalyzer(
            detectors: [StubDetector(method: .vision), StubDetector(method: .lineModelTracking), StubDetector(method: .lineSearch)],
            switches: switches
        )
        switches.setEnabled(.lineModelTracking, false)
        switches.setEnabled(.lineSearch, true)

        let outcomes = try analyzer.analyze(makePixelBuffer(), orientation: .up)

        #expect(outcomes.map(\.method) == [.vision, .lineSearch])
    }

    @Test func switchingBackOnRunsTheMethodAgain() throws {
        let switches = CourtMethodSwitches(enabled: [])
        let analyzer = CourtAnalyzer(detectors: [StubDetector(method: .vision)], switches: switches)
        let buffer = try makePixelBuffer()

        #expect(analyzer.analyze(buffer, orientation: .up).isEmpty)

        switches.setEnabled(.vision, true)

        #expect(analyzer.analyze(buffer, orientation: .up).map(\.method) == [.vision])
    }

    @Test func allMethodsOffGivesNoOutcomes() throws {
        let switches = CourtMethodSwitches(enabled: [])
        let analyzer = CourtAnalyzer(
            detectors: CourtDetectionMethod.builtIn.map { StubDetector(method: $0) },
            switches: switches
        )

        #expect(try analyzer.analyze(makePixelBuffer(), orientation: .up).isEmpty)
    }
}
