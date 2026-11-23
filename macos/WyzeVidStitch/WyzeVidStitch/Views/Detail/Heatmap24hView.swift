import SwiftUI
import WyzeStitcherKit

/// Interactive 24-hour footage density heatmap (`12 AM` – `11 PM`).
/// Clicking any recorded hour segment toggles its stitch selection.
struct Heatmap24hView: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("24-Hour Footage Density (12 AM – 11 PM)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    legendDot(color: .green, label: "Complete (60)")
                    legendDot(color: .orange, label: "Minor Gaps")
                    legendDot(color: .red, label: "Severe Gaps")
                    legendDot(color: Color.secondary.opacity(0.25), label: "Empty")
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
                    let isHovered = hoveredHour == hourIdx

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(fillColor(for: hourRecord))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .frame(height: 28)
                        .scaleEffect(y: isHovered && hourRecord != nil ? 1.12 : 1.0)
                        .animation(.snappy(duration: 0.15), value: isHovered)
                        .onHover { hovering in
                            hoveredHour = hovering ? hourIdx : (hoveredHour == hourIdx ? nil : hoveredHour)
                        }
                        .onTapGesture {
                            if let record = hourRecord {
                                withAnimation(.snappy(duration: 0.18)) {
                                    store.toggleHour(day: dayRecord.day, hour: record.hour)
                                }
                            }
                        }
                        .help(tooltipText(hourStr: hourStr, record: hourRecord))
                }
            }

            // Hour Axis Markers
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
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
    }

    private func fillColor(for record: HourRecord?) -> Color {
        guard let record else {
            return Color.secondary.opacity(0.15)
        }
        switch record.density {
        case .complete:
            return Color.green.opacity(0.85)
        case .minorGaps:
            return Color.orange.opacity(0.85)
        case .severeGaps:
            return Color.red.opacity(0.85)
        case .empty:
            return Color.secondary.opacity(0.15)
        }
    }

    private func tooltipText(hourStr: String, record: HourRecord?) -> String {
        let label = StitcherStore.formatHour12(hourStr)
        guard let record else {
            return "\(label): No footage"
        }
        if record.missingMinutes.isEmpty {
            return "\(label): 60/60 clips (Complete)"
        }
        return "\(label): \(record.clipCount)/60 clips (\(record.missingMinutes.count) missing)"
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
        }
    }
}
