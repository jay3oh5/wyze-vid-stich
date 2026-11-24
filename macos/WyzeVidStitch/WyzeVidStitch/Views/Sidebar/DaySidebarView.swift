import SwiftUI
import WyzeStitcherKit

struct DaySidebarView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(StitcherStore.self) private var store

    var body: some View {
        @Bindable var bindableStore = store

        List(selection: $bindableStore.sidebarSelection) {
            Section("Workspace") {
                NavigationLink(value: SidebarSelection.queue) {
                    HStack {
                        Label("Render Queue", systemImage: "square.stack.3d.up")
                        Spacer()
                        if store.activeJobCount > 0 {
                            Text("\(store.activeJobCount) active")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(StudioTheme.accent)
                        } else if !store.jobs.isEmpty {
                            Text("\(store.jobs.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Recorded Days (\(store.days.count))") {
                if store.days.isEmpty {
                    Text("No days scanned yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.days, id: \.day) { dayRecord in
                        NavigationLink(value: SidebarSelection.day(dayRecord.day)) {
                            DaySidebarRow(dayRecord: dayRecord)
                        }
                    }
                }
            }

            if !store.compiledVideos.isEmpty {
                Section("Compiled Videos (\(store.compiledVideos.count))") {
                    ForEach(store.compiledVideos) { item in
                        CompiledVideoSidebarRow(
                            item: item,
                            isPlaying: store.stagePreview?.videoPath == item.filePath,
                            onPlay: {
                                store.previewCompiledVideo(item, autoPlay: true)
                            },
                            onReveal: {
                                FolderPickerService.revealInFinder(path: item.filePath)
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Divider()

                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(StudioTheme.accent)

                    Text(settings.sourceDir.isEmpty ? "No folder selected" : settings.sourceDir)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer(minLength: 4)

                    Button("Change") {
                        store.browseSourceFolder()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(StudioTheme.accent)
                }

                if !store.lastScanSummary.isEmpty {
                    Text(store.lastScanSummary)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

private struct DaySidebarRow: View {
    let dayRecord: DayRecord

    private var totalClips: UInt32 {
        dayRecord.hours.reduce(0) { $0 + $1.clipCount }
    }

    private var totalSizeBytes: UInt64 {
        dayRecord.hours.reduce(0) { $0 + $1.totalSizeBytes }
    }

    private var continuityRatio: Double {
        let possible = dayRecord.hours.count * 60
        guard possible > 0 else { return 0 }
        return min(max(Double(totalClips) / Double(possible), 0), 1)
    }

    private var barColor: Color {
        if continuityRatio >= 0.999 { return StudioTheme.completeGreen }
        if continuityRatio >= 0.6 { return StudioTheme.accent }
        return StudioTheme.minorGapAmber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(StudioTheme.formatDateDisplay(dayRecord.day, includeWeekday: false))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text("\(dayRecord.hours.count)h")
                    .font(.system(.caption, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("\(totalClips) clips · \(StitcherStore.formatBytes(totalSizeBytes))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * continuityRatio))
                }
            }
            .frame(height: 3.5)
        }
        .padding(.vertical, 4)
    }
}

private struct CompiledVideoSidebarRow: View {
    let item: CompiledVideoItem
    let isPlaying: Bool
    let onPlay: () -> Void
    let onReveal: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "play.circle.fill" : "play.circle")
                    .font(.subheadline)
                    .foregroundStyle(isPlaying ? StudioTheme.completeGreen : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(item.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(StitcherStore.formatBytes(item.sizeBytes))
                    }
                    .font(.system(.caption2, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play in Preview Stage", action: onPlay)
            Button("Reveal in Finder", action: onReveal)
        }
    }
}
