#if os(iOS)
import CourtFit
import QuartzCore
import UIKit

public extension CourtDetectionMethod {
    /// 方式の線の色。Vision は緑、線の探索は水色、線の対応は橙・白・桃。映像の上で見やすいよう、鮮やかな色にしている。
    var overlayColor: UIColor {
        // 色の値は意図して指定している（システムの色は暗いため）。そのため object_literal の規則は、この行だけ外す。
        switch self {
        // swiftlint:disable:next object_literal
        case .vision: UIColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 1)
        // swiftlint:disable:next object_literal
        case .lineSearch: UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1)
        // swiftlint:disable:next object_literal
        case .lineModel: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1)
        // swiftlint:disable:next object_literal
        case .lineModelPolished: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        // swiftlint:disable:next object_literal
        case .lineModelTracking: UIColor(red: 1.0, green: 0.2, blue: 0.9, alpha: 1)
        }
    }
}

/// 検出した四角形を、方式ごとの色の線で描く。線はレイヤーの座標で描くので、置く場所（画面か映像の中か）は呼ぶ側が決める。
public final class CourtOverlayLayer: CALayer {
    private var shapes = [CourtDetectionMethod: CAShapeLayer]()
    /// 支持率が基準に届かない、候補の四角形の線（点線で薄く描く）。
    private var tentativeShapes = [CourtDetectionMethod: CAShapeLayer]()

    override public init() {
        super.init()
    }

    override public init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) は使わない")
    }

    /// 検出の結果を描き直す。`toPoint` は、正規化座標（左下が原点）を、このレイヤーの座標に変換する。
    /// 結果に入らなかった方式の線（見つからなかったもの、オフにしたもの）は消す。
    public func update(_ outcomes: [DetectionOutcome], toPoint: (CGPoint) -> CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapes.values.forEach { $0.path = nil }
        tentativeShapes.values.forEach { $0.path = nil }
        for outcome in outcomes {
            // 一つの方式の四角形は、同じ線の層に全部描く（手前と奥のコートを同じ色で）。
            let strongPath = UIBezierPath()
            let tentativePath = UIBezierPath()
            for (index, quad) in outcome.quads.enumerated() {
                let points = quad.corners.map(toPoint)
                let path = outcome.isStrong(at: index) ? strongPath : tentativePath
                path.move(to: points[0])
                points.dropFirst().forEach { path.addLine(to: $0) }
                path.close()
            }
            shapeLayer(for: outcome.method).path = strongPath.isEmpty ? nil : strongPath.cgPath
            tentativeLayer(for: outcome.method).path = tentativePath.isEmpty ? nil : tentativePath.cgPath
        }
        CATransaction.commit()
    }

    private func shapeLayer(for method: CourtDetectionMethod) -> CAShapeLayer {
        if let existing = shapes[method] {
            return existing
        }
        let shape = makeLayer(color: method.overlayColor)
        addSublayer(shape)
        shapes[method] = shape
        return shape
    }

    private func tentativeLayer(for method: CourtDetectionMethod) -> CAShapeLayer {
        if let existing = tentativeShapes[method] {
            return existing
        }
        let shape = makeLayer(color: method.overlayColor.withAlphaComponent(0.6))
        // 点線（候補であることが、色と線の形で分かるように）。
        shape.lineDashPattern = [14, 8]
        addSublayer(shape)
        tentativeShapes[method] = shape
        return shape
    }

    private func makeLayer(color: UIColor) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        // 映像の上で目立つよう、太く描く。暗い背景でも見えるよう、線の周りに影を付ける。
        shape.lineWidth = 6
        shape.lineJoin = .round
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.7
        shape.shadowRadius = 2
        shape.shadowOffset = .zero
        return shape
    }
}
#endif
