import SwiftUI
import WyzeStitcherKit

/// Minute-by-minute (00m–59m) clip exclusion inspector modal sheet.
struct ClipInspectorSheet: View {
    @Environment(StitcherStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: InspectorTarget
    @State private var includedClips: Set<String>

    private let availableClipSet: Set<String>
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 10)

    init(target: InspectorTarget) {
        self.target = target
        self.availableClipSet = Set(target.hourRecord.clips)
        _includedClips = State(initialValue: Set(target.hourRecord.clips))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inspect Footage: \(target.formattedDay) • \(StitcherStore.formatHour12(target.hourRecord.hour))")
                        .font(.title3.weight(.semibold))
                    Text("\(target.hourRecord.clipCount) of 60 minutes present. Click minute tiles to exclude clips from compilation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Selection Controls Bar
            HStack {
                Button("Select All Available") {
                    includedClips = availableClipSet
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear All") {
                    includedClips.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text("\(includedClips.count) / \(target.hourRecord.clipCount) clips selected")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // 60-Minute Grid (00m..59m)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<60, id: \.self) { minute in
                    let minStr = String(format: "%02d", minute)
                    let filename = "\(minStr).mp4"
                    let exists = availableClipSet.contains(filename)
                    let isIncluded = includedClips.contains(filename)

                    MinuteTileButton(
                        minuteLabel: "\(minStr)m",
                        exists: exists,
                        isIncluded: isIncluded
                    ) {
                        guard exists else { return }
                        if isIncluded {
                            includedClips.remove(filename)
                        } else {
                            includedClips.insert(filename)
                        }
                    }
                }
            }

            Divider()

            // Footer Actions
            HStack {
                HStack(spacing: 12) {
                    statusLegend(color: .accentColor, text: "Included")
                    statusLegend(color: .secondary, text: "Excluded")
                    statusLegend(color: .red.opacity(0.6), text: "Missing")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Stitch Custom Selection (\(includedClips.count) Mins)") {
                    store.requestStitchCustomSelection(
                        day: target.day,
                        hour: target.hourRecord.hour,
                        clips: Array(includedClips)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(includedClips.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 680)
    }

    private func statusLegend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
        }
    }
}

private struct MinuteTileButton: View {
    let minuteLabel: String
    let exists: Bool
    let isIncluded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: iconName)
                    .font(.caption2.weight(.bold))
                Text(minuteLabel)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .foregroundStyle(foregroundColor)
        }
        .buttonStyle(.plain)
        .disabled(!exists)
    }

    private var iconName: String {
        if !exists { return "minus" }
        return isIncluded ? "checkmark" : "xmark"
    }

    private var backgroundFill: Color {
        if !exists { return Color.red.opacity(0.08) }
        return isIncluded ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if !exists { return Color.red.opacity(0.25) }
        return isIncluded ? Color.accentColor : Color(nsColor: .separatorColor)
    }

    private var foregroundColor: Color {
        if !exists { return Color.secondary.opacity(0.45) }
        return isIncluded ? Color.primary : Color.secondary
    }
}
