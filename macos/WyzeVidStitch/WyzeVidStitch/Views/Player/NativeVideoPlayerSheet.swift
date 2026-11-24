import AVFoundation
import AVKit
import Combine
import SwiftUI
import WyzeStitcherKit

/// Full-size Theater playback sheet hosting Apple's native hardware-accelerated `AVPlayerView`,
/// with playback speed controls and minute-by-minute stepping when reviewing raw hour clips.
struct NativeVideoPlayerSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let target: PlaybackTarget

    @State private var player: AVPlayer
    @State private var currentFilePath: String
    @State private var currentClipFilename: String?
    @State private var currentTitle: String
    @State private var playbackRate: Float = 1.0

    private let speedOptions: [Float] = [0.5, 1.0, 2.0, 4.0]

    init(target: PlaybackTarget) {
        self.target = target
        let fileURL = URL(fileURLWithPath: target.filePath)
        _player = State(initialValue: AVPlayer(url: fileURL))
        _currentFilePath = State(initialValue: target.filePath)
        _currentClipFilename = State(initialValue: target.clipFilename)
        _currentTitle = State(initialValue: target.title)
    }

    private var prevClip: String? {
        guard let hourRecord = target.hourRecord, let current = currentClipFilename else { return nil }
        return adjacentClip(in: hourRecord.clips, current: current, offset: -1)
    }

    private var nextClip: String? {
        guard let hourRecord = target.hourRecord, let current = currentClipFilename else { return nil }
        return adjacentClip(in: hourRecord.clips, current: current, offset: 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Theater Header
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(currentTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(currentFilePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let size = currentFileSize {
                            Text("·")
                            Text(StitcherStore.formatBytes(size))
                        }
                    }
                    .font(.system(.caption, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    FolderPickerService.revealInFinder(path: currentFilePath)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Done") {
                    player.pause()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()
                .overlay(StudioTheme.hairlineBorder(for: colorScheme))

            // Expansive 16:9 Cinema Video Surface
            MacAVPlayerView(player: player)
                .frame(minWidth: 1040, minHeight: 585)
                .background(Color.black)

            Divider()
                .overlay(StudioTheme.hairlineBorder(for: colorScheme))

            // Footer Transport Controls
            HStack(spacing: 12) {
                if let hourRecord = target.hourRecord, let day = target.day {
                    Button {
                        if let prevClip {
                            switchToClip(prevClip, hourRecord: hourRecord, day: day)
                        }
                    } label: {
                        Label("Previous Minute", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(prevClip == nil)
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Button {
                        if let nextClip {
                            switchToClip(nextClip, hourRecord: hourRecord, day: day)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next Minute")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(nextClip == nil)
                    .keyboardShortcut(.rightArrow, modifiers: [])

                    Toggle(isOn: $settings.autoAdvancePreview) {
                        Text("Auto-Advance")
                            .font(.caption.weight(.medium))
                    }
                    .toggleStyle(.checkbox)
                    .padding(.leading, 6)

                    Text("Left / Right arrows step minutes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Press Escape to close theater view")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Label("Speed", systemImage: "forward.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 2) {
                        ForEach(speedOptions, id: \.self) { rate in
                            let active = abs(playbackRate - rate) < 0.01
                            Button {
                                playbackRate = rate
                                if player.timeControlStatus == .playing {
                                    player.rate = rate
                                }
                            } label: {
                                Text(rate == floor(rate) ? "\(Int(rate))x" : String(format: "%.1fx", rate))
                                    .font(.system(.caption, design: .monospaced).weight(active ? .semibold : .regular))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(active ? StudioTheme.accent : Color.clear)
                                    )
                                    .foregroundStyle(active ? Color.black : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(StudioTheme.elevatedSurface(for: colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(StudioTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(StudioTheme.elevatedSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.65 : 0.45))
        }
        .background(StudioTheme.cardSurface(for: colorScheme))
        .onAppear {
            player.play()
            player.rate = playbackRate
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard settings.autoAdvancePreview,
                  let finished = notification.object as? AVPlayerItem,
                  finished === player.currentItem,
                  let hourRecord = target.hourRecord,
                  let day = target.day,
                  let nextClip
            else { return }
            switchToClip(nextClip, hourRecord: hourRecord, day: day)
        }
        .onDisappear {
            player.pause()
        }
    }

    private var currentFileSize: UInt64? {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: currentFilePath),
           let size = attrs[.size] as? UInt64 {
            return size
        }
        return target.sizeBytes
    }

    private func switchToClip(_ clipFilename: String, hourRecord: HourRecord, day: String) {
        let newPath = URL(fileURLWithPath: hourRecord.sourceDirPath)
            .appendingPathComponent(clipFilename)
            .path
        currentClipFilename = clipFilename
        currentFilePath = newPath
        currentTitle = "\(StudioTheme.formatDateDisplay(day)) · \(StudioTheme.formatHourMinute12(hourRecord.hour, minuteFilename: clipFilename))"
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: newPath)))
        player.play()
        player.rate = playbackRate
    }

    private func adjacentClip(in clips: [String], current: String, offset: Int) -> String? {
        guard let idx = clips.firstIndex(of: current) else { return nil }
        let targetIdx = idx + offset
        guard targetIdx >= 0 && targetIdx < clips.count else { return nil }
        return clips[targetIdx]
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
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
