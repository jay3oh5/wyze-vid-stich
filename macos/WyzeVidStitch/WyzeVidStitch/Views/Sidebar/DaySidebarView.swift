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
                        Label("Compilation Queue", systemImage: "square.stack.3d.up")
                        Spacer()
                        if store.activeJobCount > 0 {
                            Text("\(store.activeJobCount)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                                .foregroundStyle(Color.accentColor)
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
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                if !settings.sourceDir.isEmpty {
                    Text(settings.sourceDir)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if !store.lastScanSummary.isEmpty {
                    Text(store.lastScanSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}

private struct DaySidebarRow: View {
    let dayRecord: DayRecord

    private var gapHourCount: Int {
        dayRecord.hours.filter { !$0.missingMinutes.isEmpty }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(dayRecord.formattedDay)
                    .font(.body.monospacedDigit())
                Text("\(dayRecord.hours.count) hours recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(gapHourCount > 0 ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
                .help(gapHourCount > 0 ? "\(gapHourCount) hour(s) with missing minutes" : "All recorded hours complete")
        }
        .padding(.vertical, 2)
    }
}
