import CoreGraphics

/// 動画の表示の範囲（縦横比を保って、枠の中に収める）。
public func fitRect(container: CGSize, video: CGSize) -> CGRect {
    guard video.width > 0, video.height > 0 else { return CGRect(origin: .zero, size: container) }
    let scale = min(container.width / video.width, container.height / video.height)
    let width = video.width * scale
    let height = video.height * scale
    return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2, width: width, height: height)
}

/// 映像を画面いっぱいに、縦横比を保って広げる（はみ出した分は切る）。
public func fillRect(container: CGSize, video: CGSize) -> CGRect {
    guard video.width > 0, video.height > 0 else { return CGRect(origin: .zero, size: container) }
    let scale = max(container.width / video.width, container.height / video.height)
    let width = video.width * scale
    let height = video.height * scale
    return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2, width: width, height: height)
}
