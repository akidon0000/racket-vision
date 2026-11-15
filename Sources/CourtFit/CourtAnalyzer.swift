import CoreVideo
import ImageIO

/// 1 フレームを、登録された方式のうち「使う」になっているものにかける。3 方式を同じ画面で比べるために使う。
/// どの方式を登録するかは、組み立ての場所（アプリの殻）が決める。「使う」かどうかは `switches` で切り替える（開発ビルドの画面から）。
public struct CourtAnalyzer: Sendable {
    public let detectors: [any CourtRectangleDetector]
    public let switches: CourtMethodSwitches

    public init(detectors: [any CourtRectangleDetector], switches: CourtMethodSwitches = CourtMethodSwitches()) {
        self.detectors = detectors
        self.switches = switches
    }

    /// 1 フレームを、「使う」になっている方式で検出する。結果は方式の登録の順。オフの方式は、検出もしない。
    /// コートとしてありえない四角形（スコアボードなど）は、結果から外す（`keepingPlausibleQuads`）。
    /// 白線の支持率で外すのは、向きが `.up`（画素のまま使う）のときだけ。
    public func analyze(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [DetectionOutcome] {
        let enabled = detectors.filter { switches.isEnabled($0.method) }
        let edges = orientation == .up ? EdgeMap(bgraPixelBuffer: pixelBuffer) : nil
        return enabled.map {
            $0.detect(in: pixelBuffer, orientation: orientation).keepingPlausibleQuads(edges: edges)
        }
    }
}
