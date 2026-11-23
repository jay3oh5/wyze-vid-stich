import SwiftUI
import WyzeStitcherKit

struct JobQueueView: View {
    @Environment(StitcherStore.self) private var store
    @State private var expandedLogJobIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Queue Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compilation Queue & History")
                        .font(.title2.weight(.semibold))
                    Text(queueSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear History") {
                    store.clearFinishedJobs()
                }
                .buttonStyle(.bordered)
                .disabled(!store.jobs.contains(where: { $0.status.isTerminal }))
            }
            .padding(24)

            Divider()

            if store.jobs.isEmpty {
                ContentUnavailableView(
                    "No Compilation Jobs",
                    systemImage: "tray",
                    description: Text("Select one or more hours from any recorded day and click Stitch Selected to start compiling.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.jobs, id: \.id) { job in
                            JobRowCard(
                                job: job,
                                isShowingLogs: expandedLogJobIds.contains(job.id),
                                onToggleLogs: {
                                    if expandedLogJobIds.contains(job.id) {
                                        expandedLogJobIds.remove(job.id)
                                    } else {
                                        expandedLogJobIds.insert(job.id)
                                    }
                                },
                                onCancel: { store.cancelJob(job.id) },
                                onPlay: { store.playCompletedJob(job) },
                                onReveal: { store.revealJobInFinder(job) }
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var queueSubtitle: String {
        let active = store.activeJobCount
        let completed = store.jobs.filter { $0.status == .completed }.count
        return "\(active) active • \(completed) completed • \(store.jobs.count) total"
    }
}

private struct JobRowCard: View {
    let job: StitchJobSnapshot
    let isShowingLogs: Bool
    let onToggleLogs: () -> Void
    let onCancel: () -> Void
    let onPlay: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                statusBadge

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(StitcherStore.formatDay(job.day))
                            .font(.headline.monospacedDigit())
                        Text(StitcherStore.formatHour12(job.hour))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if job.usedAudioFallback {
                            Text("AVFoundation AAC")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.16), in: Capsule())
                                .foregroundStyle(.indigo)
                        }
                    }

                    if let outputPath = job.outputPath {
                        Text((outputPath as NSString).lastPathComponent)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                metricsView

                actionsView
            }

            if job.status == .running || job.status == .remuxingFallback {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(job.currentClipName ?? "Processing clips...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((job.progress * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(job.progress), total: 1.0)
                        .progressViewStyle(.linear)
                }
            }

            if let errorMessage = job.errorMessage, job.status == .failed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            if isShowingLogs {
                LogConsoleView(logs: job.logs)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    job.status == .running || job.status == .remuxingFallback
                        ? Color.accentColor.opacity(0.6)
                        : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
        )
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = switch job.status {
        case .pending: ("PENDING", .secondary)
        case .running: ("MERGING", .accentColor)
        case .remuxingFallback: ("REMUXING", .indigo)
        case .completed: ("COMPLETED", .green)
        case .failed: ("FAILED", .red)
        case .cancelled: ("CANCELLED", .orange)
        }

        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var metricsView: some View {
        HStack(spacing: 12) {
            if job.status == .completed {
                Text(StitcherStore.formatBytes(job.fileSizeBytes))
                Text(String(format: "%.1fs", Double(job.durationMs) / 1000.0))
            } else if !job.status.isTerminal {
                Text("\(job.processedClips) / \(job.totalClips) clips")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var actionsView: some View {
        HStack(spacing: 6) {
            Button {
                onToggleLogs()
            } label: {
                Image(systemName: isShowingLogs ? "terminal.fill" : "terminal")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Toggle job activity log")

            if !job.status.isTerminal {
                Button(job.status == .pending ? "Remove" : "Cancel", role: .destructive) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if job.status == .completed && job.outputPath != nil {
                Button {
                    onPlay()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Reveal") {
                    onReveal()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
