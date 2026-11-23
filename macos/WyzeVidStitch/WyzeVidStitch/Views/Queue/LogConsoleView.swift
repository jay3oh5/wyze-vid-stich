import SwiftUI

struct LogConsoleView: View {
    let logs: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(logs.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(lineColor(for: line))
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(maxHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .onChange(of: logs.count) { _, newCount in
                if newCount > 0 {
                    proxy.scrollTo(newCount - 1, anchor: .bottom)
                }
            }
        }
    }

    private func lineColor(for line: String) -> Color {
        if line.contains("ERROR:") {
            return .red
        }
        if line.contains("fallback") || line.contains("skipped") {
            return .orange
        }
        return .secondary
    }
}
