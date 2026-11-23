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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header & Batch Selection Controls
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayRecord.formattedDay)
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Text("\(dayRecord.hours.count) hours available • \(selectedCountInDay) selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
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
