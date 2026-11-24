import AppKit
import SwiftUI
import WyzeStitcherKit

/// Interactive 24-hour footage coverage timeline (`12 AM` – `11 PM`).
/// Click any recorded hour to load it into the Cinema Preview Stage, or Shift-click to toggle stitch selection.
struct Heatmap24hView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(StitcherStore.self) private var store
    let dayRecord: DayRecord

    @State private var hoveredHour: Int?

    private var hoursByIndex: [Int: HourRecord] {
        Dictionary(
            uniqueKeysWithValues: dayRecord.hours.compactMap { record in
                Int(record.hour).map { ($0, record) }
            }
        )
    }

    private var activePreviewHour: String? {
        guard case .rawHour(let day, let hourRecord, _) = store.stagePreview?.mode,
              day == dayRecord.day
        else { return nil }
        return hourRecord.hour
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("24-Hour Coverage Timeline")
                        .font(.subheadline.weight(.semibold))
                    Text("Click any recorded hour to preview above, or Shift-click to toggle stitch selection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 14) {
                    legendSwatch(color: StudioTheme.completeGreen, label: "Complete (60m)")
                    legendSwatch(color: StudioTheme.minorGapAmber, label: "Minor gaps")
                    legendSwatch(color: StudioTheme.severeGapRed, label: "Severe gaps")
                    legendSwatch(color: Color.secondary.opacity(0.2), label: "No footage")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(0..<24, id: \.self) { hourIdx in
                    let hourRecord = hoursByIndex[hourIdx]
                    let hourStr = String(format: "%02d", hourIdx)
                    let isSelected = hourRecord != nil && store.selectedHours.contains(
                        store.hourKey(day: dayRecord.day, hour: hourStr)
                    )
                    let isActivePreview = activePreviewHour == hourStr
                    let isHovered = hoveredHour == hourIdx

                    Button {
                        guard let record = hourRecord else { return }
                        if NSEvent.modifierFlags.contains(.shift) {
                            withAnimation(.snappy(duration: 0.16)) {
                                store.toggleHour(day: dayRecord.day, hour: record.hour)
                            }
                        } else {
                            store.previewHour(record, inDay: dayRecord.day, autoPlay: false)
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(fillColor(for: hourRecord))

                            if hourRecord != nil {
                                Text(hourStr)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(textColor(for: hourRecord))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(
                                    isActivePreview
                                        ? StudioTheme.accent
                                        : (isSelected ? Color.white.opacity(0.85) : Color.clear),
                                    lineWidth: isActivePreview ? 2.5 : 1.5
                                )
                        )
                        .scaleEffect(y: isHovered && hourRecord != nil ? 1.08 : 1.0)
                        .animation(.snappy(duration: 0.14), value: isHovered)
                    }
                    .buttonStyle(.plain)
                    .disabled(hourRecord == nil)
                    .onHover { hovering in
                        hoveredHour = hovering ? hourIdx : (hoveredHour == hourIdx ? nil : hoveredHour)
                    }
                    .help(tooltipText(hourStr: hourStr, record: hourRecord))
                }
            }

            HStack {
                Text("12 AM")
                Spacer()
                Text("6 AM")
                Spacer()
                Text("12 PM")
                Spacer()
                Text("6 PM")
                Spacer()
                Text("11 PM")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(StudioTheme.cardSurface(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(StudioTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private func fillColor(for record: HourRecord?) -> Color {
        guard let record else {
            return Color.secondary.opacity(colorScheme == .dark ? 0.12 : 0.15)
        }
        return StudioTheme.densityColor(for: record.density).opacity(0.86)
    }

    private func textColor(for record: HourRecord?) -> Color {
        guard let record else { return .clear }
        switch record.density {
        case .severeGaps: return .white
        case .complete, .minorGaps: return Color.black.opacity(0.85)
        case .empty: return .secondary
        }
    }

    private func tooltipText(hourStr: String, record: HourRecord?) -> String {
        let label = StitcherStore.formatHour12(hourStr)
        guard let record else {
            return "\(label): No footage"
        }
        if record.missingMinutes.isEmpty {
            return "\(label): 60/60 clips (Complete) — Click to preview, Shift-click to select"
        }
        return "\(label): \(record.clipCount)/60 clips (\(record.missingMinutes.count) missing) — Click to preview, Shift-click to select"
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}
