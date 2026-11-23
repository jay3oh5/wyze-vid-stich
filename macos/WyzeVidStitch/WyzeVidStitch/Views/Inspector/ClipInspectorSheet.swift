import AppKit
import AVKit
import SwiftUI
import WyzeStitcherKit

/// Minute-by-minute (00m–59m) clip exclusion inspector modal sheet with:
/// - Inline 1-minute `AVPlayerView` quick preview
/// - Shift-click contiguous range selection/deselection
struct ClipInspectorSheet: View {
    @Environment(StitcherStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: InspectorTarget
    @State private var includedClips: Set<String>
    @State private var lastInteractedMinute: Int?
    @State private var previewingFilename: String?
    @State private var previewPlayer: AVPlayer?

    private let availableClipSet: Set<String>
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 10)

    init(target: InspectorTarget) {
        self.target = target
        self.availableClipSet = Set(target.hourRecord.clips)
        _includedClips = State(initialValue: Set(target.hourRecord.clips))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inspect Footage: \(target.formattedDay) • \(StitcherStore.formatHour12(target.hourRecord.hour))")
                        .font(.title3.weight(.semibold))
                    Text("\(target.hourRecord.clipCount) of 60 minutes present. Click tiles to toggle, Shift-click for ranges, or click the play icon to preview a minute.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    stopPreview()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Inline 1-Minute Quick Preview Strip (shown when a clip is previewed)
            if let filename = previewingFilename, let player = previewPlayer {
                inlinePreviewStrip(filename: filename, player: player)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Selection Controls Bar
            HStack {
                Button("Select All Available") {
                    includedClips = availableClipSet
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear All") {
                    includedClips.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text("\(includedClips.count) / \(target.hourRecord.clipCount) clips selected")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // 60-Minute Grid (00m..59m)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<60, id: \.self) { minute in
                    let minStr = String(format: "%02d", minute)
                    let filename = "\(minStr).mp4"
                    let exists = availableClipSet.contains(filename)
                    let isIncluded = includedClips.contains(filename)
                    let isPreviewing = previewingFilename == filename

                    MinuteTileCard(
                        minuteLabel: "\(minStr)m",
                        exists: exists,
                        isIncluded: isIncluded,
                        isPreviewing: isPreviewing,
                        onToggle: {
                            handleMinuteToggle(minute: minute, filename: filename)
                        },
                        onPreview: {
                            startPreview(filename: filename)
                        }
                    )
                }
            }

            Divider()

            // Footer Actions
            HStack {
                HStack(spacing: 12) {
                    statusLegend(color: .accentColor, text: "Included")
                    statusLegend(color: .secondary, text: "Excluded")
                    statusLegend(color: .red.opacity(0.6), text: "Missing")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    stopPreview()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Stitch Custom Selection (\(includedClips.count) Mins)") {
                    stopPreview()
                    store.requestStitchCustomSelection(
                        target: target,
                        clips: Array(includedClips)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(includedClips.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 740)
        .onDisappear {
            stopPreview()
        }
    }

    private func inlinePreviewStrip(filename: String, player: AVPlayer) -> some View {
        let clipPath = URL(fileURLWithPath: target.hourRecord.sourceDirPath)
            .appendingPathComponent(filename)
            .path
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: clipPath)[.size] as? UInt64) ?? 0
        let isIncluded = includedClips.contains(filename)

        return HStack(spacing: 14) {
            InlineMiniAVPlayerView(player: player)
                .frame(width: 280, height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Previewing \(filename)", systemImage: "play.rectangle.fill")
                        .font(.headline.monospacedDigit())
                    Spacer()
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            stopPreview()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close preview")
                }

                Text("File size: \(StitcherStore.formatBytes(fileSize))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(fileSize == 0 ? .red : .secondary)

                if fileSize == 0 {
                    Label("0-byte clip detected — exclude to prevent stitch failure.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        if isIncluded {
                            includedClips.remove(filename)
                        } else {
                            includedClips.insert(filename)
                        }
                    } label: {
                        Label(
                            isIncluded ? "Exclude This Minute" : "Include This Minute",
                            systemImage: isIncluded ? "minus.circle" : "plus.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Reveal") {
                        FolderPickerService.revealInFinder(path: clipPath)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
    }

    private func handleMinuteToggle(minute: Int, filename: String) {
        guard availableClipSet.contains(filename) else { return }

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

    private func startPreview(filename: String) {
        let clipURL = URL(fileURLWithPath: target.hourRecord.sourceDirPath)
            .appendingPathComponent(filename)
        previewPlayer?.pause()
        let player = AVPlayer(url: clipURL)
        withAnimation(.snappy(duration: 0.2)) {
            previewingFilename = filename
            previewPlayer = player
        }
        player.play()
    }

    private func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        previewingFilename = nil
    }

    private func statusLegend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
        }
    }
}

private struct MinuteTileCard: View {
    let minuteLabel: String
    let exists: Bool
    let isIncluded: Bool
    let isPreviewing: Bool
    let onToggle: () -> Void
    let onPreview: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onToggle) {
                VStack(spacing: 3) {
                    Image(systemName: iconName)
                        .font(.caption2.weight(.bold))
                    Text(minuteLabel)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(backgroundFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isPreviewing ? 2 : 1)
                )
                .foregroundStyle(foregroundColor)
            }
            .buttonStyle(.plain)
            .disabled(!exists)

            if exists && (isHovered || isPreviewing) {
                Button(action: onPreview) {
                    Image(systemName: isPreviewing ? "speaker.wave.2.fill" : "play.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(isPreviewing ? Color.accentColor : Color.primary)
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help("Preview \(minuteLabel) clip")
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var iconName: String {
        if !exists { return "minus" }
        return isIncluded ? "checkmark" : "xmark"
    }

    private var backgroundFill: Color {
        if !exists { return Color.red.opacity(0.08) }
        return isIncluded ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isPreviewing { return Color.accentColor }
        if !exists { return Color.red.opacity(0.25) }
        return isIncluded ? Color.accentColor : Color(nsColor: .separatorColor)
    }

    private var foregroundColor: Color {
        if !exists { return Color.secondary.opacity(0.45) }
        return isIncluded ? Color.primary : Color.secondary
    }
}

private struct InlineMiniAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
