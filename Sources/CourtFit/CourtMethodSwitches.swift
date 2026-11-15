import Foundation

/// 方式ごとに「使う」かどうかを持つ箱。開発ビルドの画面のスイッチから切り替え、映像の解析（別のキュー）から読むため、ロックで守る。
public final class CourtMethodSwitches: @unchecked Sendable {
    private let lock = NSLock()
    /// 切り替えた方式の状態。切り替えていない方式は `initiallyEnabled` で決める。
    private var states = [CourtDetectionMethod: Bool]()
    private let initiallyEnabled: @Sendable (CourtDetectionMethod) -> Bool

    /// 既定でオフにする方式。線の探索は誤った線を拾いやすく、重い。線の対応（追従なし）の 2 つは、
    /// 毎フレーム最初から探すので重い（追従ありと同じ探し方なので、比べたいときだけ開発パネルでオンにする）。
    public static let offByDefault: Set<CourtDetectionMethod> = [.lineSearch, .lineModel, .lineModelPolished]

    /// 作ったときは、`offByDefault` 以外の方式を使う（使う側のアプリが足した方式も使う）。
    public init() {
        initiallyEnabled = { !Self.offByDefault.contains($0) }
    }

    /// 作ったときは、`enabled` の方式だけを使う。
    public init(enabled: Set<CourtDetectionMethod>) {
        initiallyEnabled = { enabled.contains($0) }
    }

    public func isEnabled(_ method: CourtDetectionMethod) -> Bool {
        lock.withLock { states[method] ?? initiallyEnabled(method) }
    }

    public func setEnabled(_ method: CourtDetectionMethod, _ on: Bool) {
        lock.withLock { states[method] = on }
    }
}
