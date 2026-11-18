import AVKit
import SwiftUI

/// AppKit の動画の部品（`AVPlayerView`）。SwiftUI の `VideoPlayer` は、macOS 26.7 で Xcode 27 の SDK でビルドすると、
/// 起動の直後に落ちた（AVKit の SwiftUI の部分の型の読み込みで止まる）ので、使わない。
struct PlayerNSView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}
