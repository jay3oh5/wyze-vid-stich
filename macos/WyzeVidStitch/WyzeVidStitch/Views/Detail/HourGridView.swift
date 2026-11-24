import SwiftUI
import WyzeStitcherKit

/// Large visual 16:9 Hour Preview Grid with real AVFoundation thumbnails,
/// preview card size switcher (3-Up / Large / Cinema), status filters, and 60-minute coverage strips.
struct HourGridView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @Environment(StitcherStore.self) private var store

    let dayRecord: DayRecord

    @State private var filterMode: HourFilterMode = .all

    private var selectedCountInDay: Int {
        dayRecord.hours.filter {
            store.selectedHours.contains(store.hourKey(day: dayRecord.day, hour: $0.hour))
        }.count
    }

    private var completeCount: Int {
        dayRecord.hours.filter { $0.missingMinutes.isEmpty && $0.clipCount == 60 }.count
    }

    private var gapCount: Int {
        dayRecord.hours.filter { !$0.missingMinutes.isEmpty }.count
    }

    private var filteredHours: [HourRecord] {
        switch filterMode {
        case .all:
            return dayRecord.hours
        case .complete:
            return dayRecord.hours.filter { $0.missingMinutes.isEmpty && $0.clipCount == 60 }
        case .gaps:
            return dayRecord.hours.filter { !$0.missingMinutes.isEmpty }
        case .selected:
            return dayRecord.hours.filter {
                store.selectedHours.contains(store.hourKey(day: dayRecord.day, hour: $0.hour))
            }
        }
    }

    private var activePreviewHour: String? {
        guard case .rawHour(let day, let hourRecord, _) = store.stagePreview?.mode,
              day == dayRecord.day
        else { return nil }
        return hourRecord.hour
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toolbar: Filter Segmented Controls + Preview Size Switcher + Batch Selection
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    filterSegmentedControl
                    previewSizeControl
                    Spacer()
                    batchSelectionControls
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        filterSegmentedControl
                        previewSizeControl
                    }
                    batchSelectionControls
                }
            }

            if filteredHours.isEmpty {
                VStack(spacing: 10) {
                    Text("No hours match this filter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Show All Hours") {
                        filterMode = .all
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(StudioTheme.cardSurface(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(StudioTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
                        )
                )
            } else {
                LazyVGrid(columns: settings.previewSize.gridColumns, spacing: 18) {
                    ForEach(filteredHours, id: \.sourceDirPath) { hourRecord in
                        HourPreviewCard(
                            hourRecord: hourRecord,
                            thumbnailPath: store.representativeClipPath(for: hourRecord),
                            isSelected: store.selectedHours.contains(
                                store.hourKey(day: dayRecord.day, hour: hourRecord.hour)
                            ),
                            isActivePreview: activePreviewHour == hourRecord.hour,
                            onPreview: {
                                store.previewHour(hourRecord, inDay: dayRecord.day, autoPlay: true)
                            },
                            onOpenTheater: {
                                store.openTheaterForHour(hourRecord, inDay: dayRecord.day)
                            },
                            onToggleSelect: {
                                withAnimation(.snappy(duration: 0.18)) {
                                    store.toggleHour(day: dayRecord.day, hour: hourRecord.hour)
                                }
                            },
                            onInspect: {
                                store.inspectingTarget = InspectorTarget(
                                    day: dayRecord.day,
                                    formattedDay: dayRecord.formattedDay,
                                    hourRecord: hourRecord
                                )
                            }
                        )
                    }
                }
            }
        }
        .onChange(of: dayRecord.day) { _, _ in
            filterMode = .all
        }
    }

    private var filterSegmentedControl: some View {
        HStack(spacing: 2) {
            filterButton(.all, label: "All (\(dayRecord.hours.count))")
            filterButton(.complete, label: "Complete (\(completeCount))")
            filterButton(.gaps, label: "With Gaps (\(gapCount))")
            filterButton(.selected, label: "Selected (\(selectedCountInDay))")
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(StudioTheme.cardSurface(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(StudioTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private func filterButton(_ mode: HourFilterMode, label: String) -> some View {
        let isActive = filterMode == mode
        return Button {
            withAnimation(.snappy(duration: 0.16)) {
                filterMode = mode
            }
        } label: {
            Text(label)
                .font(.caption.weight(isActive ? .semibold : .medium).monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10) : Color.clear)
                )
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var previewSizeControl: some View {
        HStack(spacing: 2) {
            ForEach(HourPreviewSize.allCases) { size in
                let isActive = settings.previewSize == size
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        settings.previewSize = size
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: size.systemImage)
                            .font(.caption2)
                        Text(size.label)
                            .font(.caption.weight(isActive ? .semibold : .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isActive ? StudioTheme.accent : Color.clear)
                    )
                    .foregroundStyle(isActive ? Color.black : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(StudioTheme.cardSurface(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(StudioTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private var batchSelectionControls: some View {
        HStack(spacing: 8) {
            Button("Select All") {
                withAnimation(.snappy(duration: 0.18)) {
                    store.selectAllHours(in: dayRecord)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Select Gaps") {
                withAnimation(.snappy(duration: 0.18)) {
                    store.selectGapHours(in: dayRecord)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Clear") {
                withAnimation(.snappy(duration: 0.18)) {
                    store.clearSelection(in: dayRecord)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedCountInDay == 0)
        }
    }
}

private struct HourPreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let hourRecord: HourRecord
    let thumbnailPath: String?
    let isSelected: Bool
    let isActivePreview: Bool
    let onPreview: () -> Void
    let onOpenTheater: () -> Void
    let onToggleSelect: () -> Void
    let onInspect: () -> Void

    @State private var isHovered: Bool = false

    private var presentMinuteSet: Set<String> {
        Set(hourRecord.clips)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Large 16:9 Real Video Thumbnail with Contrast Scrim & Coverage Micro-Bar
            ZStack {
                VideoThumbnailView(filePath: thumbnailPath)
                    .scaleEffect(isHovered ? 1.03 : 1.0)
                    .animation(.easeOut(duration: 0.22), value: isHovered)

                // Measured Bottom Scrim for guaranteed legibility on bright video frames
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.58),
                            Color.black.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 112)
                }
                .allowsHitTesting(false)

                // Center Play Button Overlay
                Button(action: onPreview) {
                    ZStack {
                        Color.black.opacity(isHovered ? 0.24 : 0.0)
                        Circle()
                            .fill(Color.black.opacity(0.68))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .offset(x: 2)
                            )
                            .scaleEffect(isHovered ? 1.06 : 0.96)
                            .opacity(isHovered ? 1.0 : 0.85)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Load \(StitcherStore.formatHour12(hourRecord.hour)) in Cinema Preview Stage")

                // Top Row Controls: Select Toggle (Left) + Expand Theater (Right)
                VStack {
                    HStack {
                        Button(action: onToggleSelect) {
                            HStack(spacing: 5) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .font(.caption.weight(.bold))
                                Text(isSelected ? "Selected" : "Select")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? StudioTheme.accent : Color.black.opacity(0.68))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? StudioTheme.accent : Color.white.opacity(0.22),
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(isSelected ? Color.black : Color.white)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: onOpenTheater) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.black.opacity(0.68))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Open \(StitcherStore.formatHour12(hourRecord.hour)) in Theater View")
                    }
                    .padding(11)

                    Spacer()

                    // Bottom Overlay Text + 60-Minute Coverage Micro-Bar
                    VStack(spacing: 8) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(StitcherStore.formatHour12(hourRecord.hour))
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                Text(StudioTheme.formatHourRange(hourRecord.hour))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.78))
                            }

                            Spacer()

                            Text("\(hourRecord.clipCount)/60 min")
                                .font(.system(.caption, design: .monospaced).weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.white.opacity(0.92))
                        }
                        .padding(.horizontal, 12)

                        // 60-Minute Micro-Coverage Strip
                        HStack(spacing: 1) {
                            ForEach(0..<60, id: \.self) { m in
                                let fname = String(format: "%02d.mp4", m)
                                Rectangle()
                                    .fill(
                                        presentMinuteSet.contains(fname)
                                            ? StudioTheme.completeGreen.opacity(0.92)
                                            : StudioTheme.severeGapRed.opacity(0.78)
                                    )
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.black)

            // Clean Footer: Unboxed Semantic Metadata + Inspect Clips Action
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    statusLabel

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(StitcherStore.formatBytes(hourRecord.totalSizeBytes))
                        .font(.system(.caption, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.secondary)

                    if hourRecord.hasNonAacAudio {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Label("AAC", systemImage: "waveform")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                            .help("Legacy non-AAC Wyze audio detected; will remux audio via AVFoundation.")
                    }
                }
                .lineLimit(1)

                Spacer()

                Button {
                    onInspect()
                } label: {
                    Label("Inspect Clips", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(StudioTheme.cardSurface(for: colorScheme))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected || isActivePreview ? 1.75 : 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var borderColor: Color {
        if isSelected { return StudioTheme.accent }
        if isActivePreview { return Color.primary.opacity(0.35) }
        return StudioTheme.hairlineBorder(for: colorScheme)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch hourRecord.density {
        case .complete:
            Label("Complete", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(StudioTheme.completeGreen)
        case .minorGaps:
            Label("\(hourRecord.missingMinutes.count) missing", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(StudioTheme.minorGapAmber)
        case .severeGaps:
            Label("\(hourRecord.missingMinutes.count) missing", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(StudioTheme.severeGapRed)
        case .empty:
            Text("Empty")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
