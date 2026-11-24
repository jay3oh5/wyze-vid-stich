import SwiftUI
import WyzeStitcherKit

struct DayDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(StitcherStore.self) private var store
    let dayRecord: DayRecord

    private var selectedCountInDay: Int {
        dayRecord.hours.filter {
            store.selectedHours.contains(store.hourKey(day: dayRecord.day, hour: $0.hour))
        }.count
    }

    private var dayTotalClips: UInt32 {
        dayRecord.hours.reduce(0) { $0 + $1.clipCount }
    }

    private var continuityPercent: Int {
        let possible = dayRecord.hours.count * 60
        guard possible > 0 else { return 0 }
        return Int((Double(dayTotalClips) / Double(possible) * 100.0).rounded())
    }

    private var dayTotalSizeBytes: UInt64 {
        dayRecord.hours.reduce(0) { $0 + $1.totalSizeBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Editorial Day Header & Full-Day Merge Controls
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(StudioTheme.formatDateDisplay(dayRecord.day, includeWeekday: true))
                            .font(.system(size: 26, weight: .bold))
                            .tracking(-0.3)

                        Text(
                            "\(dayRecord.hours.count) recorded hours · \(dayTotalClips) clips · \(continuityPercent)% continuity · \(StitcherStore.formatBytes(dayTotalSizeBytes))"
                        )
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Menu {
                            Button {
                                store.requestStitchFullDay(for: dayRecord, onlySelectedHours: false)
                            } label: {
                                Label(
                                    "Merge Entire Day (\(dayRecord.hours.count) Hours)",
                                    systemImage: "film.stack"
                                )
                            }

                            Button {
                                store.requestStitchFullDay(for: dayRecord, onlySelectedHours: true)
                            } label: {
                                Label(
                                    "Merge Selected Hours into One File (\(selectedCountInDay) Hours)",
                                    systemImage: "rectangle.stack.badge.play"
                                )
                            }
                            .disabled(selectedCountInDay < 2)
                        } label: {
                            Label("Stitch Full Day", systemImage: "film.stack")
                        } primaryAction: {
                            store.requestStitchFullDay(for: dayRecord, onlySelectedHours: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(dayRecord.hours.isEmpty)
                        .help("Compile all hours in \(dayRecord.formattedDay) into a single continuous MP4")
                    }
                }

                // Hero Focal Anchor: Large Embedded Cinema Preview Stage
                CinemaPreviewStageView()

                // Interactive 24-Hour Footage Coverage Timeline
                Heatmap24hView(dayRecord: dayRecord)

                // Large Visual Hour Preview Grid with Size Switcher & Filters
                HourGridView(dayRecord: dayRecord)
            }
            .padding(24)
            .frame(maxWidth: 1480, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(StudioTheme.canvasBackground(for: colorScheme))
        .onAppear {
            store.syncStagePreviewForDay(dayRecord)
        }
        .onChange(of: dayRecord.day) { _, _ in
            store.syncStagePreviewForDay(dayRecord)
        }
    }
}
