import AVFoundation
import AVKit
import Combine
import SwiftUI
import WyzeStitcherKit

/// Large embedded widescreen cinema preview stage with minute-by-minute scrubbing,
/// playback speed controls, auto-advance across consecutive 1-minute clips, and full Theater expansion.
struct CinemaPreviewStageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @Environment(StitcherStore.self) private var store

    @State private var player: AVPlayer = AVPlayer()
    @State private var loadedVideoPath: String?
    @State private var playbackRate: Float = 1.0

    private let speedOptions: [Float] = [0.5, 1.0, 2.0, 4.0]

    var body: some View {
        VStack(spacing: 0) {
            if let stage = store.stagePreview {
                stageHeader(for: stage)

                Divider()
                    .overlay(StudioTheme.hairlineBorder(for: colorScheme))

                // Spacious 16:9 Cinema Video Viewport
                ZStack {
                    Color.black
                    StageAVPlayerRepresentable(player: player)
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(minHeight: 360, maxHeight: 500)
                .frame(maxWidth: .infinity)
                .background(Color.black)

                Divider()
                    .overlay(StudioTheme.hairlineBorder(for: colorScheme))

                stageTransportAndScrubber(for: stage)
            } else {
                emptyStagePlaceholder
            }
        }
        .background(StudioTheme.cardSurface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(StudioTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
        )
        .onAppear {
            syncPlayerWithStage(store.stagePreview)
        }
        .onChange(of: store.stagePreview) { _, newStage in
            syncPlayerWithStage(newStage)
        }
        .onChange(of: playbackRate) { _, newRate in
            if player.timeControlStatus == .playing {
                player.rate = newRate
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let finishedItem = notification.object as? AVPlayerItem,
                  finishedItem === player.currentItem,
                  settings.autoAdvancePreview,
                  let stage = store.stagePreview,
                  case .rawHour(let day, let hourRecord, let clipFilename) = stage.mode,
                  let nextClip = adjacentClip(in: hourRecord.clips, current: clipFilename, offset: 1)
            else {
                return
            }
            store.previewHour(hourRecord, inDay: day, clipFilename: nextClip, autoPlay: true)
        }
        .onDisappear {
            player.pause()
        }
    }

    // MARK: - Stage Header

    @ViewBuilder
    private func stageHeader(for stage: StagePreviewState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle(for: stage))
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Text(headerSubtitle(for: stage))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if case .rawHour(let day, let hourRecord, _) = stage.mode {
                    let isSelected = store.selectedHours.contains(store.hourKey(day: day, hour: hourRecord.hour))
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            store.toggleHour(day: day, hour: hourRecord.hour)
                        }
                    } label: {
                        Label(
                            isSelected ? "Selected" : "Select Hour",
                            systemImage: isSelected ? "checkmark.square.fill" : "square"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? StudioTheme.accent : nil)
                    .controlSize(.small)

                    Button {
                        store.inspectingTarget = InspectorTarget(
                            day: day,
                            formattedDay: StitcherStore.formatDay(day),
                            hourRecord: hourRecord
                        )
                    } label: {
                        Label("Inspect Clips", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if case .compiled(let item) = stage.mode {
                    Button {
                        FolderPickerService.revealInFinder(path: item.filePath)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    player.pause()
                    store.openTheaterForCurrentStage()
                } label: {
                    Label("Expand Theater", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Transport Controls & 60-Minute Scrubber

    @ViewBuilder
    private func stageTransportAndScrubber(for stage: StagePreviewState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if case .rawHour(let day, let hourRecord, let clipFilename) = stage.mode {
                    let prevClip = adjacentClip(in: hourRecord.clips, current: clipFilename, offset: -1)
                    let nextClip = adjacentClip(in: hourRecord.clips, current: clipFilename, offset: 1)

                    HStack(spacing: 6) {
                        Button {
                            if let prevClip {
                                store.previewHour(hourRecord, inDay: day, clipFilename: prevClip, autoPlay: true)
                            }
                        } label: {
                            Label("Prev Minute", systemImage: "chevron.left")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(prevClip == nil)

                        Button {
                            if let nextClip {
                                store.previewHour(hourRecord, inDay: day, clipFilename: nextClip, autoPlay: true)
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

                        Toggle(isOn: $settings.autoAdvancePreview) {
                            Text("Auto-Advance")
                                .font(.caption.weight(.medium))
                        }
                        .toggleStyle(.checkbox)
                        .padding(.leading, 6)
                        .help("Automatically play the next 1-minute clip when the current clip ends")
                    }
                } else {
                    Text(stage.videoPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Playback Speed Selector
                HStack(spacing: 6) {
                    Label("Speed", systemImage: "forward.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 2) {
                        ForEach(speedOptions, id: \.self) { rate in
                            let isCurrent = abs(playbackRate - rate) < 0.01
                            Button {
                                playbackRate = rate
                                if player.timeControlStatus == .playing {
                                    player.rate = rate
                                }
                            } label: {
                                Text(speedLabel(rate))
                                    .font(.system(.caption, design: .monospaced).weight(isCurrent ? .semibold : .regular))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(isCurrent ? StudioTheme.accent : Color.clear)
                                    )
                                    .foregroundStyle(isCurrent ? Color.black : Color.secondary)
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

            // 60-Minute Interactive Scrubber Strip (Raw Hour Mode)
            if case .rawHour(let day, let hourRecord, let clipFilename) = stage.mode {
                let presentSet = Set(hourRecord.clips)
                let currentMin = clipFilename.replacingOccurrences(of: ".mp4", with: "", options: .caseInsensitive)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Minute-by-Minute Scrubber (\(StitcherStore.formatHour12(hourRecord.hour)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Playing :\(currentMin) · \(hourRecord.clipCount)/60 present")
                            .font(.system(.caption, design: .monospaced).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 2) {
                        ForEach(0..<60, id: \.self) { minute in
                            let minStr = String(format: "%02d", minute)
                            let filename = "\(minStr).mp4"
                            let isPresent = presentSet.contains(filename)
                            let isCurrent = filename == clipFilename

                            Button {
                                if isPresent {
                                    store.previewHour(hourRecord, inDay: day, clipFilename: filename, autoPlay: true)
                                }
                            } label: {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(scrubberColor(isPresent: isPresent, isCurrent: isCurrent))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: isCurrent ? 26 : 22)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .strokeBorder(isCurrent ? Color.white : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!isPresent)
                            .help(
                                isPresent
                                    ? "Preview \(StudioTheme.formatHourMinute12(hourRecord.hour, minuteFilename: filename))"
                                    : "\(StudioTheme.formatHourMinute12(hourRecord.hour, minuteFilename: filename)) — Missing"
                            )
                        }
                    }
                    .frame(height: 26)

                    HStack {
                        Text(":00")
                        Spacer()
                        Text(":15")
                        Spacer()
                        Text(":30")
                        Spacer()
                        Text(":45")
                        Spacer()
                        Text(":59")
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(StudioTheme.elevatedSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.6 : 0.45))
    }

    private var emptyStagePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("Select an Hour or Compiled Video to Preview")
                .font(.headline)
            Text("Click any large preview card below or any compiled video in the sidebar to inspect footage in widescreen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .padding(24)
    }

    // MARK: - Helpers

    private func syncPlayerWithStage(_ stage: StagePreviewState?) {
        guard let stage else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            loadedVideoPath = nil
            return
        }

        if loadedVideoPath != stage.videoPath {
            loadedVideoPath = stage.videoPath
            let url = URL(fileURLWithPath: stage.videoPath)
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
        }

        if stage.autoPlay {
            player.seek(to: .zero)
            player.play()
            player.rate = playbackRate
        }
    }

    private func adjacentClip(in clips: [String], current: String, offset: Int) -> String? {
        guard let idx = clips.firstIndex(of: current) else { return nil }
        let target = idx + offset
        guard target >= 0 && target < clips.count else { return nil }
        return clips[target]
    }

    private func headerTitle(for stage: StagePreviewState) -> String {
        switch stage.mode {
        case .rawHour(let day, let hourRecord, let clipFilename):
            return "\(StudioTheme.formatDateDisplay(day)) · \(StudioTheme.formatHourMinute12(hourRecord.hour, minuteFilename: clipFilename))"
        case .compiled(let item):
            return item.displayTitle
        }
    }

    private func headerSubtitle(for stage: StagePreviewState) -> String {
        switch stage.mode {
        case .rawHour(_, let hourRecord, _):
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: stage.videoPath)[.size] as? UInt64) ?? 0
            var parts = [
                "Hour \(StitcherStore.formatHour12(hourRecord.hour))",
                "\(hourRecord.clipCount) of 60 min recorded"
            ]
            if !hourRecord.missingMinutes.isEmpty {
                parts.append("\(hourRecord.missingMinutes.count) gaps")
            }
            if fileSize > 0 {
                parts.append(StitcherStore.formatBytes(fileSize))
            }
            return parts.joined(separator: " · ")
        case .compiled(let item):
            return "Compiled MP4 · \(item.fileName) · \(StitcherStore.formatBytes(item.sizeBytes))"
        }
    }

    private func speedLabel(_ rate: Float) -> String {
        rate == floor(rate) ? "\(Int(rate))x" : String(format: "%.1fx", rate)
    }

    private func scrubberColor(isPresent: Bool, isCurrent: Bool) -> Color {
        if isCurrent { return StudioTheme.accent }
        if isPresent { return StudioTheme.completeGreen.opacity(0.62) }
        return StudioTheme.severeGapRed.opacity(0.28)
    }
}

/// Embedded `AVPlayerView` wrapper tailored for the Cinema Preview Stage.
private struct StageAVPlayerRepresentable: NSViewRepresentable {
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
