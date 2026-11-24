import SwiftUI
import WyzeStitcherKit

struct JobQueueView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(StitcherStore.self) private var store
    @State private var expandedLogJobIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Queue Header Bar + Aggregate Batch Progress
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Render Queue")
                            .font(.system(size: 26, weight: .bold))
                            .tracking(-0.3)
                        Text(queueSubtitle)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if store.activeJobCount > 0 {
                            Button("Cancel All", role: .destructive) {
                                store.cancelAllJobs()
                            }
                            .buttonStyle(.bordered)
                        }

                        if store.failedOrCancelledCount > 0 {
                            Button {
                                store.retryAllFailedJobs()
                            } label: {
                                Label("Retry Failed (\(store.failedOrCancelledCount))", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Clear Finished") {
                            store.clearFinishedJobs()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.jobs.contains(where: { $0.status.isTerminal }))
                    }
                }

                if store.activeJobCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Overall Batch Progress")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((store.aggregateProgress * 100).rounded()))%")
                                .font(.system(.caption, design: .monospaced).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: store.aggregateProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(StudioTheme.accent)
                    }
                }
            }
            .padding(24)

            Divider()
                .overlay(StudioTheme.hairlineBorder(for: colorScheme))

            if store.jobs.isEmpty {
                ContentUnavailableView(
                    "Your Render Queue Is Empty",
                    systemImage: "square.stack.3d.up",
                    description: Text("Select one or more recorded hours from any day and click Stitch Selected or Stitch Full Day to compile lossless hourly videos.")
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
                                onRetry: { store.retryJob(job.id) },
                                onPlay: { store.playCompletedJob(job) },
                                onReveal: { store.revealJobInFinder(job) }
                            )
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 1360, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .background(StudioTheme.canvasBackground(for: colorScheme))
    }

    private var queueSubtitle: String {
        "\(store.activeJobCount) active · \(store.completedJobCount) completed · \(store.jobs.count) total"
    }
}

private struct JobRowCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let job: StitchJobSnapshot
    let isShowingLogs: Bool
    let onToggleLogs: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onPlay: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                // Visual Video Thumbnail when Completed
                if job.status == .completed, let outputPath = job.outputPath {
                    Button(action: onPlay) {
                        ZStack {
                            VideoThumbnailView(filePath: outputPath)
                            Circle()
                                .fill(Color.black.opacity(0.62))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white)
                                        .offset(x: 1)
                                )
                        }
                        .frame(width: 104, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(StudioTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Play compiled video in Theater View")
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        statusIndicator

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(
                            "\(StudioTheme.formatDateDisplay(job.day, includeWeekday: false)) · \(job.mode == .fullDay ? "Full Day" : StitcherStore.formatHour12(job.hour))"
                        )
                        .font(.headline.weight(.semibold))

                        if job.usedAudioFallback {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("AVFoundation AAC")
                                .font(.caption)
                                .foregroundStyle(.indigo)
                        }
                    }

                    HStack(spacing: 8) {
                        if job.status == .completed {
                            Text("\(job.totalClips) clips")
                            Text("·")
                            Text(StitcherStore.formatBytes(job.fileSizeBytes))
                            Text("·")
                            Text(String(format: "%.1fs", Double(job.durationMs) / 1000.0))
                        } else {
                            Text("\(job.processedClips) / \(job.totalClips) clips")
                        }

                        if let outputPath = job.outputPath {
                            Text("·")
                            Text((outputPath as NSString).lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.system(.caption, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Spacer()

                actionsView
            }

            if job.status == .running || job.status == .remuxingFallback {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(job.currentClipName ?? "Processing clips...")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((job.progress * 100).rounded()))%")
                            .font(.system(.caption, design: .monospaced).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(job.progress), total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(StudioTheme.accent)
                }
            }

            if let errorMessage = job.errorMessage, job.status == .failed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                        .textSelection(.enabled)
                }
                .font(.caption)
                .foregroundStyle(StudioTheme.severeGapRed)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(StudioTheme.severeGapRed.opacity(0.1))
                )
            }

            if isShowingLogs {
                LogConsoleView(logs: job.logs)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(StudioTheme.cardSurface(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    job.status == .running || job.status == .remuxingFallback
                        ? StudioTheme.accent.opacity(0.65)
                        : StudioTheme.hairlineBorder(for: colorScheme),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch job.status {
        case .pending:
            Label("Queued", systemImage: "clock")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .running:
            Label("Compiling", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(StudioTheme.accent)
        case .remuxingFallback:
            Label("Remuxing Audio", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
        case .completed:
            Label("Completed", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(StudioTheme.completeGreen)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(StudioTheme.severeGapRed)
        case .cancelled:
            Label("Cancelled", systemImage: "slash.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(StudioTheme.minorGapAmber)
        }
    }

    private var actionsView: some View {
        HStack(spacing: 8) {
            if !job.status.isTerminal {
                Button(job.status == .pending ? "Remove" : "Cancel", role: .destructive) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if job.status == .failed || job.status == .cancelled {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
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
                .tint(StudioTheme.accent)
                .controlSize(.small)

                Button {
                    onReveal()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                onToggleLogs()
            } label: {
                Label("Logs", systemImage: isShowingLogs ? "terminal.fill" : "terminal")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Toggle job activity log")
        }
    }
}
