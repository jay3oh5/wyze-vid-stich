import Foundation
import Observation
import SwiftUI
import WyzeStitcherKit

/// Sidebar navigation destination inside `NavigationSplitView`.
enum SidebarSelection: Hashable {
    case day(String) // Raw YYYYMMDD folder key
    case queue
}

/// Identifies a specific hour opened inside the Minute-by-Minute Clip Exclusion Inspector sheet.
struct InspectorTarget: Identifiable, Hashable {
    let day: String
    let formattedDay: String
    let hourRecord: HourRecord

    var id: String { "\(day)_\(hourRecord.hour)" }

    static func == (lhs: InspectorTarget, rhs: InspectorTarget) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Identifies a compiled video opened in the native `AVPlayerView` sheet.
struct PlaybackTarget: Identifiable {
    let id = UUID()
    let title: String
    let filePath: String
}

/// Central `@MainActor @Observable` store bridging the Rust `StitcherEngine` to SwiftUI views.
@MainActor
@Observable
final class StitcherStore {
    let settings: AppSettings

    // Navigation & Scan State
    var sidebarSelection: SidebarSelection?
    var days: [DayRecord] = []
    var lastScanSummary: String = ""
    var isScanning: Bool = false
    var scanError: String?

    // Selection State ("YYYYMMDD_HH" keys)
    var selectedHours: Set<String> = []

    // Job Queue State
    var jobs: [StitchJobSnapshot] = []
    var activeJobCount: Int {
        jobs.filter { !$0.status.isTerminal }.count
    }

    // Sheets & Confirmation State
    var inspectingTarget: InspectorTarget?
    var activePlayback: PlaybackTarget?
    var pendingDeleteConfirmationAction: (() -> Void)?
    var showDeleteConfirmation: Bool = false
    var errorBanner: String?

    @ObservationIgnored private var engine: StitcherEngine!
    @ObservationIgnored private var bridgeAdapter: StitcherEventBridge!
    @ObservationIgnored private var knownCompletedJobIds: Set<String> = []

    init(settings: AppSettings) {
        self.settings = settings

        let bridge = StitcherEventBridge()
        let remuxer = AVFoundationRemuxer { [weak bridge] jobId, progress, processed, total, clipName in
            bridge?.onJobProgress(
                event: JobProgressEvent(
                    jobId: jobId,
                    status: .remuxingFallback,
                    progress: progress,
                    processedClips: processed,
                    totalClips: total,
                    currentClipName: clipName
                )
            )
        }

        self.bridgeAdapter = bridge
        self.engine = StitcherEngine(listener: bridge, remuxFallback: remuxer)
        bridge.store = self
    }

    // MARK: - Formatting Helpers

    static func formatHour12(_ hourStr: String) -> String {
        let h = Int(hourStr) ?? 0
        let ampm = h >= 12 ? "PM" : "AM"
        let displayH = h % 12 == 0 ? 12 : h % 12
        return "\(displayH):00 \(ampm)"
    }

    static func formatDay(_ rawDay: String) -> String {
        guard rawDay.count == 8 else { return rawDay }
        let y = rawDay.prefix(4)
        let m = rawDay.dropFirst(4).prefix(2)
        let d = rawDay.dropFirst(6).prefix(2)
        return "\(y)-\(m)-\(d)"
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func hourKey(day: String, hour: String) -> String {
        "\(day)_\(hour)"
    }

    // MARK: - Folder Selection & Scanning

    func browseSourceFolder() {
        if let path = FolderPickerService.pickFolder(prompt: "Select Wyze Camera Record Folder") {
            settings.sourceDir = path
            Task { await scanSourceDirectory() }
        }
    }

    func scanSourceDirectory() async {
        let source = settings.sourceDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            scanError = "Choose a Wyze /record directory first."
            return
        }

        isScanning = true
        scanError = nil
        selectedHours.removeAll()

        do {
            let result = try await engine.scanDirectory(sourceDir: source)
            days = result.days
            lastScanSummary = "\(result.totalDays) days • \(result.totalHours) hours • \(result.totalClips) clips (\(result.scanDurationMs) ms)"

            if let firstDay = result.days.first {
                sidebarSelection = .day(firstDay.day)
            } else {
                sidebarSelection = nil
            }
        } catch {
            days = []
            scanError = error.localizedDescription
        }

        isScanning = false
    }

    // MARK: - Hour Selection Mutations

    func toggleHour(day: String, hour: String) {
        let key = hourKey(day: day, hour: hour)
        if selectedHours.contains(key) {
            selectedHours.remove(key)
        } else {
            selectedHours.insert(key)
        }
    }

    func selectAllHours(in dayRecord: DayRecord) {
        for h in dayRecord.hours {
            selectedHours.insert(hourKey(day: dayRecord.day, hour: h.hour))
        }
    }

    func selectGapHours(in dayRecord: DayRecord) {
        for h in dayRecord.hours {
            let key = hourKey(day: dayRecord.day, hour: h.hour)
            if !h.missingMinutes.isEmpty {
                selectedHours.insert(key)
            } else {
                selectedHours.remove(key)
            }
        }
    }

    func clearSelection(in dayRecord: DayRecord) {
        for h in dayRecord.hours {
            selectedHours.remove(hourKey(day: dayRecord.day, hour: h.hour))
        }
    }

    // MARK: - Job Submission & Queue Control

    func requestStitchSelectedHours() {
        guard !selectedHours.isEmpty else { return }

        let requests: [StitchJobRequest] = selectedHours.sorted().compactMap { key in
            let parts = key.split(separator: "_")
            guard parts.count == 2 else { return nil }
            return StitchJobRequest(
                day: String(parts[0]),
                hour: String(parts[1]),
                selectedClips: nil
            )
        }

        submitWithSafetyCheck(requests: requests, clearSelectionOnSuccess: true)
    }

    func requestStitchCustomSelection(day: String, hour: String, clips: [String]) {
        guard !clips.isEmpty else { return }
        let request = StitchJobRequest(day: day, hour: hour, selectedClips: clips.sorted())
        inspectingTarget = nil
        submitWithSafetyCheck(requests: [request], clearSelectionOnSuccess: false)
    }

    private func submitWithSafetyCheck(requests: [StitchJobRequest], clearSelectionOnSuccess: Bool) {
        let execute = { [weak self] in
            guard let self else { return }
            self.enqueue(requests: requests, clearSelectionOnSuccess: clearSelectionOnSuccess)
        }

        if settings.deleteAfterCompile {
            pendingDeleteConfirmationAction = execute
            showDeleteConfirmation = true
        } else {
            execute()
        }
    }

    private func enqueue(requests: [StitchJobRequest], clearSelectionOnSuccess: Bool) {
        errorBanner = nil
        do {
            let options = settings.toStitchOptions()
            _ = try engine.enqueueJobs(options: options, requests: requests)
            if clearSelectionOnSuccess {
                selectedHours.removeAll()
            }
            sidebarSelection = .queue
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func cancelJob(_ jobId: String) {
        do {
            _ = try engine.cancelJob(jobId: jobId)
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func clearFinishedJobs() {
        jobs = engine.clearFinishedJobs()
    }

    func playCompletedJob(_ job: StitchJobSnapshot) {
        guard let outputPath = job.outputPath else { return }
        let title = "\(Self.formatDay(job.day)) • \(Self.formatHour12(job.hour))"
        activePlayback = PlaybackTarget(title: title, filePath: outputPath)
    }

    func revealJobInFinder(_ job: StitchJobSnapshot) {
        guard let outputPath = job.outputPath else { return }
        FolderPickerService.revealInFinder(path: outputPath)
    }

    // MARK: - Rust Push Callbacks (Dispatched on @MainActor)

    fileprivate func handleJobUpdated(_ snapshot: StitchJobSnapshot) {
        if let idx = jobs.firstIndex(where: { $0.id == snapshot.id }) {
            jobs[idx] = snapshot
        } else {
            jobs.append(snapshot)
        }

        // Fire one-time completion side effects (Finder reveal + macOS Notification Center).
        if snapshot.status == .completed && !knownCompletedJobIds.contains(snapshot.id) {
            knownCompletedJobIds.insert(snapshot.id)
            if settings.sendNotifications {
                NotificationService.sendJobNotification(
                    title: "Stitch Complete",
                    body: "Compiled \(Self.formatDay(snapshot.day)) \(Self.formatHour12(snapshot.hour)) (\(Self.formatBytes(snapshot.fileSizeBytes)))."
                )
            }
            if settings.autoRevealInFinder, let path = snapshot.outputPath {
                FolderPickerService.revealInFinder(path: path)
            }
        } else if snapshot.status == .failed && !knownCompletedJobIds.contains(snapshot.id) {
            knownCompletedJobIds.insert(snapshot.id)
            if settings.sendNotifications {
                NotificationService.sendJobNotification(
                    title: "Stitch Failed",
                    body: "\(Self.formatDay(snapshot.day)) \(Self.formatHour12(snapshot.hour)): \(snapshot.errorMessage ?? "Unknown error")"
                )
            }
        }
    }

    fileprivate func handleJobProgress(_ event: JobProgressEvent) {
        guard let idx = jobs.firstIndex(where: { $0.id == event.jobId }) else { return }
        let current = jobs[idx]
        jobs[idx] = StitchJobSnapshot(
            id: current.id,
            day: current.day,
            hour: current.hour,
            status: event.status,
            totalClips: event.totalClips,
            processedClips: event.processedClips,
            progress: event.progress,
            currentClipName: event.currentClipName,
            outputPath: current.outputPath,
            fileSizeBytes: current.fileSizeBytes,
            durationMs: current.durationMs,
            usedAudioFallback: current.usedAudioFallback || event.status == .remuxingFallback,
            errorMessage: current.errorMessage,
            logs: current.logs
        )
    }

    fileprivate func handleJobLog(jobId: String, line: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        let current = jobs[idx]
        var updatedLogs = current.logs
        updatedLogs.append(line)
        jobs[idx] = StitchJobSnapshot(
            id: current.id,
            day: current.day,
            hour: current.hour,
            status: current.status,
            totalClips: current.totalClips,
            processedClips: current.processedClips,
            progress: current.progress,
            currentClipName: current.currentClipName,
            outputPath: current.outputPath,
            fileSizeBytes: current.fileSizeBytes,
            durationMs: current.durationMs,
            usedAudioFallback: current.usedAudioFallback,
            errorMessage: current.errorMessage,
            logs: updatedLogs
        )
    }
}

/// Thread-safe UniFFI callback adapter forwarding Rust events onto `@MainActor`.
private final class StitcherEventBridge: StitchEventListener, @unchecked Sendable {
    weak var store: StitcherStore?

    func onJobUpdated(snapshot: StitchJobSnapshot) {
        Task { @MainActor [weak self] in
            self?.store?.handleJobUpdated(snapshot)
        }
    }

    func onJobProgress(event: JobProgressEvent) {
        Task { @MainActor [weak self] in
            self?.store?.handleJobProgress(event)
        }
    }

    func onJobLog(jobId: String, line: String, isError: Bool) {
        Task { @MainActor [weak self] in
            self?.store?.handleJobLog(jobId: jobId, line: line)
        }
    }

    func onQueueIdle() {
        // Queue idle hook available for dock badge clearing or auto-rescan.
    }
}

extension JobStatus {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .pending, .running, .remuxingFallback:
            return false
        }
    }
}
