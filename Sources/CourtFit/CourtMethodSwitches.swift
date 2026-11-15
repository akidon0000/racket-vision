import Foundation

/// 方式ごとに「使う」かどうかを持つ箱。開発ビルドの画面のスイッチから切り替え、映像の解析（別のキュー）から読むため、ロックで守る。
public final class CourtMethodSwitches: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Set<CourtDetectionMethod>

    /// 既定でオフにする方式。線の探索は誤った線を拾いやすく、重い。線の対応（追従なし）の 2 つは、
    /// 毎フレーム最初から探すので重い（追従ありと同じ探し方なので、比べたいときだけ開発パネルでオンにする）。
    public static let offByDefault: Set<CourtDetectionMethod> = [.lineSearch, .lineModel, .lineModelPolished]

    /// 作ったときは、既定の方式を使う。
    public init(enabled: Set<CourtDetectionMethod> = Set(CourtDetectionMethod.allCases).subtracting(offByDefault)) {
        self.enabled = enabled
    }

    public func isEnabled(_ method: CourtDetectionMethod) -> Bool {
        lock.withLock { enabled.contains(method) }
    }

    public func setEnabled(_ method: CourtDetectionMethod, _ on: Bool) {
        lock.withLock {
            if on {
                enabled.insert(method)
            } else {
                enabled.remove(method)
            }
        }
    }
}
