import AVKit
import SwiftUI

/// Modal playback sheet hosting Apple's native macOS `AVPlayerView` for hardware-accelerated
/// local `.mp4` playback without any HTTP range-streaming server.
struct NativeVideoPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: PlaybackTarget
    @State private var player: AVPlayer

    init(target: PlaybackTarget) {
        self.target = target
        let fileURL = URL(fileURLWithPath: target.filePath)
        _player = State(initialValue: AVPlayer(url: fileURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Player Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title)
                        .font(.headline)
                    Text(target.filePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Reveal in Finder") {
                    FolderPickerService.revealInFinder(path: target.filePath)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Close") {
                    player.pause()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            MacAVPlayerView(player: player)
                .frame(minWidth: 820, minHeight: 480)
        }
        .onAppear {
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }
}

/// AppKit `NSViewRepresentable` wrapper around native `AVKit.AVPlayerView`.
private struct MacAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.showsFrameSteppingButtons = true
        view.showsTimecodes = true
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
