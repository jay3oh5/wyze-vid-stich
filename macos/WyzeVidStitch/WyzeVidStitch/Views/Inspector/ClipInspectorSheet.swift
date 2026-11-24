import AppKit
import AVFoundation
import AVKit
import SwiftUI
import WyzeStitcherKit

/// Split-pane Minute-by-Minute (00m–59m) Clip Inspector sheet featuring:
/// - Large always-visible 16:9 `AVPlayerView` live clip preview on the left
/// - Playback speed controls & Previous/Next minute stepping
/// - Clean 60-minute selector grid on the right with Shift-click range selection
struct ClipInspectorSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(StitcherStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: InspectorTarget

    @State private var includedClips: Set<String>
    @State private var lastInteractedMinute: Int?
    @State private var previewingFilename: String?
    @State private var player: AVPlayer = AVPlayer()
    @State private var playbackRate: Float = 1.0

    private let availableClipSet: Set<String>
    private let sortedClips: [String]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 10)
    private let speedOptions: [Float] = [0.5, 1.0, 2.0, 4.0]

    init(target: InspectorTarget) {
        self.target = target
        self.sortedClips = target.hourRecord.clips.sorted()
        self.availableClipSet = Set(target.hourRecord.clips)
        _includedClips = State(initialValue: Set(target.hourRecord.clips))
        _previewingFilename = State(initialValue: target.hourRecord.clips.sorted().first)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        "Clip Inspector · \(StudioTheme.formatDateDisplay(target.day, includeWeekday: false)) · \(StitcherStore.formatHour12(target.hourRecord.hour))"
                    )
                    .font(.title3.weight(.semibold))

                    Text(
                        "\(target.hourRecord.clipCount) of 60 minutes recorded · \(includedClips.count) selected for export · Shift-click tiles for ranges"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    player.pause()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            Divider()
                .overlay(StudioTheme.hairlineBorder(for: colorScheme))

            // Split Workspace: Large Preview Left + 60-Minute Selector Right
            HStack(spacing: 0) {
                leftPreviewPane
                    .frame(width: 500)
                    .background(StudioTheme.elevatedSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.4))

                Divider()
                    .overlay(StudioTheme.hairlineBorder(for: colorScheme))

                rightGridPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
                .overlay(StudioTheme.hairlineBorder(for: colorScheme))

            // Footer Actions
            HStack {
                HStack(spacing: 14) {
                    statusLegend(color: StudioTheme.accent, text: "Included")
                    statusLegend(color: Color.secondary.opacity(0.45), text: "Excluded")
                    statusLegend(color: StudioTheme.severeGapRed.opacity(0.5), text: "Missing")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    player.pause()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    player.pause()
                    store.requestStitchCustomSelection(
                        target: target,
                        clips: Array(includedClips)
                    )
                    dismiss()
                } label: {
                    Label("Stitch Selected (\(includedClips.count) min)", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .disabled(includedClips.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 1060, height: 640)
        .background(StudioTheme.cardSurface(for: colorScheme))
        .onAppear {
            if let initial = previewingFilename {
                loadPreviewClip(initial, autoPlay: false)
            }
        }
        .onChange(of: playbackRate) { _, newRate in
            if player.timeControlStatus == .playing {
                player.rate = newRate
            }
        }
        .onDisappear {
            player.pause()
        }
    }

    // MARK: - Left Pane: Large 16:9 Live Clip Preview

    private var leftPreviewPane: some View {
        let filename = previewingFilename
        let clipPath = filename.map {
            URL(fileURLWithPath: target.hourRecord.sourceDirPath).appendingPathComponent($0).path
        }
        let fileSize: UInt64 = clipPath.flatMap {
            (try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? UInt64)
        } ?? 0
        let isIncluded = filename.map { includedClips.contains($0) } ?? false
        let prevClip = filename.flatMap { adjacentClip(from: $0, offset: -1) }
        let nextClip = filename.flatMap { adjacentClip(from: $0, offset: 1) }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(
                    filename.map {
                        "Previewing \(StudioTheme.formatHourMinute12(target.hourRecord.hour, minuteFilename: $0))"
                    } ?? "No Clip Selected"
                )
                .font(.subheadline.weight(.semibold))

                Spacer()

                if let filename {
                    Text("\(filename) · \(StitcherStore.formatBytes(fileSize))")
                        .font(.system(.caption, design: .monospaced).monospacedDigit())
                        .foregroundStyle(fileSize == 0 ? StudioTheme.severeGapRed : .secondary)
                }
            }

            // Large 16:9 Video Player
            ZStack {
                Color.black
                if filename != nil {
                    InspectorAVPlayerRepresentable(player: player)
                } else {
                    Text("No recorded clips available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(StudioTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
            )

            // Prev / Next Minute + Speed Selector
            HStack(spacing: 8) {
                Button {
                    if let prevClip { loadPreviewClip(prevClip, autoPlay: true) }
                } label: {
                    Label("Prev", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(prevClip == nil)

                Button {
                    if let nextClip { loadPreviewClip(nextClip, autoPlay: true) }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(nextClip == nil)

                Spacer()

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
                                .font(.system(.caption2, design: .monospaced).weight(active ? .semibold : .regular))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(active ? StudioTheme.accent : Color.clear)
                                )
                                .foregroundStyle(active ? Color.black : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(StudioTheme.cardSurface(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(StudioTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
                        )
                )
            }

            if filename != nil && fileSize == 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("0-byte corrupted clip detected — exclude this minute to prevent stitch errors.")
                }
                .font(.caption)
                .foregroundStyle(StudioTheme.severeGapRed)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(StudioTheme.severeGapRed.opacity(0.12))
                )
            }

            Spacer()

            if let filename, let clipPath {
                HStack(spacing: 10) {
                    Button {
                        if isIncluded {
                            includedClips.remove(filename)
                        } else {
                            includedClips.insert(filename)
                        }
                    } label: {
                        Label(
                            isIncluded ? "Included in Stitch" : "Excluded from Stitch",
                            systemImage: isIncluded ? "checkmark.circle.fill" : "minus.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(isIncluded ? StudioTheme.accent : .secondary)

                    Button {
                        FolderPickerService.revealInFinder(path: clipPath)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Right Pane: Clean 60-Minute Selector Grid

    private var rightGridPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button("Select All") {
                    includedClips = availableClipSet
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Invert") {
                    includedClips = availableClipSet.subtracting(includedClips)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear") {
                    includedClips.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text("\(includedClips.count) / \(target.hourRecord.clipCount) clips")
                    .font(.system(.caption, design: .monospaced).weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(0..<60, id: \.self) { minute in
                    let minStr = String(format: "%02d", minute)
                    let filename = "\(minStr).mp4"
                    let exists = availableClipSet.contains(filename)
                    let isIncluded = includedClips.contains(filename)
                    let isPreviewing = previewingFilename == filename

                    InspectorMinuteTile(
                        minuteText: minStr,
                        exists: exists,
                        isIncluded: isIncluded,
                        isPreviewing: isPreviewing,
                        onTap: {
                            handleMinuteTap(minute: minute, filename: filename)
                        }
                    )
                }
            }

            Text("Click any minute to preview it on the left and toggle inclusion. Hold Shift to toggle a contiguous range.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func handleMinuteTap(minute: Int, filename: String) {
        guard availableClipSet.contains(filename) else { return }

        loadPreviewClip(filename, autoPlay: false)

        let targetState = !includedClips.contains(filename)
        let isShiftHeld = NSEvent.modifierFlags.contains(.shift)

        if isShiftHeld, let anchor = lastInteractedMinute {
            let lower = min(anchor, minute)
            let upper = max(anchor, minute)
            for m in lower...upper {
                let candidate = String(format: "%02d.mp4", m)
                guard availableClipSet.contains(candidate) else { continue }
                if targetState {
                    includedClips.insert(candidate)
                } else {
                    includedClips.remove(candidate)
                }
            }
        } else {
            if targetState {
                includedClips.insert(filename)
            } else {
                includedClips.remove(filename)
            }
        }

        lastInteractedMinute = minute
    }

    private func loadPreviewClip(_ filename: String, autoPlay: Bool) {
        let clipURL = URL(fileURLWithPath: target.hourRecord.sourceDirPath)
            .appendingPathComponent(filename)
        previewingFilename = filename
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: clipURL))
        if autoPlay {
            player.play()
            player.rate = playbackRate
        }
    }

    private func adjacentClip(from current: String, offset: Int) -> String? {
        guard let idx = sortedClips.firstIndex(of: current) else { return nil }
        let nextIdx = idx + offset
        guard nextIdx >= 0 && nextIdx < sortedClips.count else { return nil }
        return sortedClips[nextIdx]
    }

    private func statusLegend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(text)
        }
    }
}

private struct InspectorMinuteTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let minuteText: String
    let exists: Bool
    let isIncluded: Bool
    let isPreviewing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text(minuteText)
                    .font(.system(.caption, design: .monospaced).weight(.semibold).monospacedDigit())
                Text(!exists ? "—" : (isIncluded ? "✓" : "off"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isPreviewing ? 2 : 1)
            )
            .foregroundStyle(numberColor)
        }
        .buttonStyle(.plain)
        .disabled(!exists)
        .help(exists ? "Minute :\(minuteText) (\(isIncluded ? "Included" : "Excluded"))" : "Minute :\(minuteText) (Missing)")
    }

    private var backgroundFill: Color {
        if !exists { return StudioTheme.severeGapRed.opacity(0.08) }
        if isIncluded { return StudioTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.15) }
        return StudioTheme.elevatedSurface(for: colorScheme)
    }

    private var borderColor: Color {
        if isPreviewing { return Color.primary }
        if !exists { return StudioTheme.severeGapRed.opacity(0.22) }
        if isIncluded { return StudioTheme.accent.opacity(0.65) }
        return StudioTheme.hairlineBorder(for: colorScheme)
    }

    private var numberColor: Color {
        if !exists { return Color.secondary.opacity(0.45) }
        return isIncluded ? Color.primary : Color.secondary
    }

    private var statusTextColor: Color {
        if !exists { return Color.secondary.opacity(0.35) }
        return isIncluded ? StudioTheme.accent : Color.secondary.opacity(0.75)
    }
}

private struct InspectorAVPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.showsFrameSteppingButtons = true
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
