import CoreFoundation
import CoreVideo
import ImageIO
import Vision

/// 検出の方式。複数の方式を同じ画面で比べるために使う。
public enum CourtDetectionMethod: String, CaseIterable, Sendable {
    /// Vision の矩形検出。
    case vision
    /// 直線（ハフ変換）の組から四角形を作り、白線の支持率で選ぶ。
    case lineSearch
    /// 白線の芯から直線を取り、図面の線との対応を総当たりして探す。フレームごとに最初から探す。
    case lineModel
    /// `lineModel` で見つけた後に、元の大きさの画像で合わせ直す。
    case lineModelPolished
    /// `lineModel` と同じ探し方で、見つけた後は前のフレームから合わせ直す。
    case lineModelTracking

    /// 画面やパネルに出す名前。
    public var label: String {
        switch self {
        case .vision: "Vision"
        case .lineSearch: "線の探索"
        case .lineModel: "線の対応"
        case .lineModelPolished: "線の対応+等倍で仕上げ"
        case .lineModelTracking: "線の対応+追従"
        }
    }
}

/// 1 フレームに対する、1 方式の検出の結果。
public struct DetectionOutcome: Equatable, Sendable {
    public var method: CourtDetectionMethod
    /// 見つかった四角形（手前と奥のコートなど、複数あり得る）。見つからなければ空。面積の大きい順。
    public var quads: [DetectedQuad]
    /// 確からしさ（0〜1）。方式が出さなければ nil。
    public var confidence: Float?
    /// 検出にかかった時間（ミリ秒）。
    public var durationMilliseconds: Double
    /// 検出に使った映像の大きさ（表示の向きに回したあと）。
    public var imageSize: CGSize
    /// 検出に使った設定の一覧（開発パネルに出す）。例: 「確からしさの下限 0.6」。
    public var parameters: [String]
    /// 四角形ごとの、白線の支持率（0〜1）。`quads` と同じ並び。白線で確かめていなければ空。
    public var supports: [Double]

    public init(
        method: CourtDetectionMethod,
        quads: [DetectedQuad],
        confidence: Float?,
        durationMilliseconds: Double,
        imageSize: CGSize,
        parameters: [String] = [],
        supports: [Double] = []
    ) {
        self.method = method
        self.quads = quads
        self.confidence = confidence
        self.durationMilliseconds = durationMilliseconds
        self.imageSize = imageSize
        self.parameters = parameters
        self.supports = supports
    }

    /// 四角形が、白線の支持率で「確か」と言えるか（実線で出す）。支持率が分からなければ確かとみなす。
    public func isStrong(at index: Int) -> Bool {
        guard supports.indices.contains(index) else { return true }
        return supports[index] >= CourtLineSupport.strong
    }
}

/// 映像のフレームから、コートの矩形（四角形）を探す。
///
/// 方式ごとに実装を分け、同じ入出力にする。返す座標は、表示の向きに回したあとの映像の正規化座標（左下が原点）。
public protocol CourtRectangleDetector: Sendable {
    /// この実装の方式。
    var method: CourtDetectionMethod { get }
    /// 1 フレームから矩形を探す。`orientation` は、映像を表示の向きに回すための向き。
    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> DetectionOutcome
}

/// 表示の向きに回したあとの、映像の大きさ。
public func uprightImageSize(of pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGSize {
    let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
    let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
    switch orientation {
    case .left, .right, .leftMirrored, .rightMirrored:
        return CGSize(width: height, height: width)
    default:
        return CGSize(width: width, height: height)
    }
}

/// Vision の矩形検出で探す実装。
/// 返された矩形のうち、面積の大きいものから、互いに重ならないものを `maximumQuads` 件まで返す（手前と奥のコートを分けるため）。
public struct VisionCourtRectangleDetector: CourtRectangleDetector {
    public let method = CourtDetectionMethod.vision
    /// 矩形の最小の確からしさ。
    public var minimumConfidence: VNConfidence
    /// 映像の辺に対する、矩形の最小の大きさ（0〜1）。小さい矩形は無視する。
    public var minimumSize: Float
    /// 縦横比の下限。コート（縦横比 約 0.45）を、遠近で潰れた見え方も含めて拾えるようにする。
    public var minimumAspectRatio: VNAspectRatio
    /// 角の直角からのずれの許容（度、0〜45）。遠近で歪んだコートを拾うために大きくする。
    public var quadratureTolerance: Float
    /// Vision に返させる矩形の数の上限。
    public var maximumObservations: Int
    /// 返す矩形の数の上限（手前と奥のコートで 2）。
    public var maximumQuads: Int

    /// 既定値は、デモ動画の検証で選んだ組み合わせ。直角のずれを 45 度まで許し、確からしさは低めにする。
    public init(
        minimumConfidence: VNConfidence = 0.3,
        minimumSize: Float = 0.2,
        minimumAspectRatio: VNAspectRatio = 0.3,
        quadratureTolerance: Float = 45,
        maximumObservations: Int = 10,
        maximumQuads: Int = 2
    ) {
        self.minimumConfidence = minimumConfidence
        self.minimumSize = minimumSize
        self.minimumAspectRatio = minimumAspectRatio
        self.quadratureTolerance = quadratureTolerance
        self.maximumObservations = maximumObservations
        self.maximumQuads = maximumQuads
    }

    public func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> DetectionOutcome {
        let started = CFAbsoluteTimeGetCurrent()
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = maximumObservations
        request.minimumConfidence = minimumConfidence
        request.minimumSize = minimumSize
        request.minimumAspectRatio = minimumAspectRatio
        request.quadratureTolerance = quadratureTolerance

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        var observations = [VNRectangleObservation]()
        do {
            try handler.perform([request])
            observations = request.results ?? []
        } catch {
            observations = []
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000

        let chosen = Self.nonOverlapping(observations, limit: maximumQuads)
        let quads = chosen.map {
            DetectedQuad(topLeft: $0.topLeft, topRight: $0.topRight, bottomRight: $0.bottomRight, bottomLeft: $0.bottomLeft)
        }
        return DetectionOutcome(
            method: method,
            quads: quads,
            confidence: chosen.first?.confidence,
            durationMilliseconds: elapsed,
            imageSize: uprightImageSize(of: pixelBuffer, orientation: orientation),
            parameters: [
                "確からしさの下限 \(String(format: "%.2f", minimumConfidence))",
                "最小の大きさ \(String(format: "%.2f", minimumSize))",
                "縦横比の下限 \(String(format: "%.2f", minimumAspectRatio))",
                "直角のずれ \(String(format: "%.0f", quadratureTolerance))度",
                "候補数 \(maximumObservations)、返す数 \(maximumQuads)"
            ]
        )
    }

    /// 面積の大きい順に、他と重なりが大きくないものを選ぶ。重なりは、外接矩形の重なりの割合（IoU）で見る。
    static func nonOverlapping(_ observations: [VNRectangleObservation], limit: Int) -> [VNRectangleObservation] {
        let sorted = observations.sorted { area($0) > area($1) }
        var chosen = [VNRectangleObservation]()
        for observation in sorted {
            guard chosen.count < limit else { break }
            let overlaps = chosen.contains { intersectionOverUnion($0.boundingBox, observation.boundingBox) > 0.3 }
            if !overlaps {
                chosen.append(observation)
            }
        }
        return chosen
    }

    private static func area(_ observation: VNRectangleObservation) -> CGFloat {
        observation.boundingBox.width * observation.boundingBox.height
    }

    private static func intersectionOverUnion(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = first.width * first.height + second.width * second.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}
