import SwiftUI
import WyzeStitcherKit

struct DayDetailView: View {
    @Environment(StitcherStore.self) private var store
    let dayRecord: DayRecord

    private var selectedCountInDay: Int {
        dayRecord.hours.filter {
            store.selectedHours.contains(store.hourKey(day: dayRecord.day, hour: $0.hour))
        }.count
    }

    private var dayTotalSizeBytes: UInt64 {
        dayRecord.hours.reduce(0) { $0 + $1.totalSizeBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header & Batch Selection / Full-Day Merge Controls
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayRecord.formattedDay)
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Text(
                            "\(dayRecord.hours.count) hours available • \(StitcherStore.formatBytes(dayTotalSizeBytes)) • \(selectedCountInDay) selected"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
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
                        .controlSize(.small)
                        .disabled(dayRecord.hours.isEmpty)
                        .help("Compile all hours in \(dayRecord.formattedDay) into a single continuous MP4")

                        Divider()
                            .frame(height: 16)

                        Button("Select All") {
                            withAnimation(.snappy(duration: 0.2)) {
                                store.selectAllHours(in: dayRecord)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Select Gaps") {
                            withAnimation(.snappy(duration: 0.2)) {
                                store.selectGapHours(in: dayRecord)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Clear") {
                            withAnimation(.snappy(duration: 0.2)) {
                                store.clearSelection(in: dayRecord)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // 24-Hour Footage Density Heatmap
                Heatmap24hView(dayRecord: dayRecord)

                // Hour Selection Grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recorded Hours")
                        .font(.headline)

                    HourGridView(dayRecord: dayRecord)
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
