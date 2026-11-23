import SwiftUI
import WyzeStitcherKit

struct HourGridView: View {
    @Environment(StitcherStore.self) private var store
    let dayRecord: DayRecord

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(dayRecord.hours, id: \.hour) { hourRecord in
                HourTileCard(
                    dayRecord: dayRecord,
                    hourRecord: hourRecord,
                    isSelected: store.selectedHours.contains(
                        store.hourKey(day: dayRecord.day, hour: hourRecord.hour)
                    ),
                    onToggle: {
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

private struct HourTileCard: View {
    let dayRecord: DayRecord
    let hourRecord: HourRecord
    let isSelected: Bool
    let onToggle: () -> Void
    let onInspect: () -> Void

    private var gapBadgeColor: Color? {
        switch hourRecord.density {
        case .complete, .empty: return nil
        case .minorGaps: return .orange
        case .severeGaps: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(StitcherStore.formatHour12(hourRecord.hour))
                        .font(.headline.monospacedDigit())
                    Text("\(hourRecord.clipCount)/60 clips")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let badgeColor = gapBadgeColor {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 8, height: 8)
                        .help("Missing \(hourRecord.missingMinutes.count) minute(s)")
                }
            }

            if hourRecord.hasNonAacAudio {
                Label("AAC Fallback", systemImage: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.indigo)
                    .help("Legacy non-AAC Wyze audio detected; will remux audio via AVFoundation.")
            }

            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Spacer()

                Button("Inspect") {
                    onInspect()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.12)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onToggle)
    }
}
