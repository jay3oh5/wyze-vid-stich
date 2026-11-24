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

    var id: String { "\(day)_\(hourRecord.hour)_\(hourRecord.sourceDirPath)" }

    static func == (lhs: InspectorTarget, rhs: InspectorTarget) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Represents a compiled `.mp4` output discovered in the output directory or day folders.
struct CompiledVideoItem: Identifiable, Hashable {
    let filePath: String
    let fileName: String
    let displayTitle: String
    let sizeBytes: UInt64
    let modifiedDate: Date

    var id: String { filePath }
}

/// Active footage loaded in the embedded Cinema Preview Stage.
struct StagePreviewState: Equatable {
    enum Mode: Equatable {
        case rawHour(day: String, hourRecord: HourRecord, clipFilename: String)
        case compiled(CompiledVideoItem)
    }

    let mode: Mode
    let videoPath: String
    let autoPlay: Bool

    static func == (lhs: StagePreviewState, rhs: StagePreviewState) -> Bool {
        lhs.videoPath == rhs.videoPath && lhs.autoPlay == rhs.autoPlay && lhs.mode == rhs.mode
    }
}

/// Identifies a video opened in the full-size Theater `AVPlayerView` sheet.
struct PlaybackTarget: Identifiable {
    let id = UUID()
    let title: String
    let filePath: String
    let sizeBytes: UInt64?
    let day: String?
    let hourRecord: HourRecord?
    let clipFilename: String?

    init(
        title: String,
        filePath: String,
        sizeBytes: UInt64? = nil,
        day: String? = nil,
        hourRecord: HourRecord? = nil,
        clipFilename: String? = nil
    ) {
        self.title = title
        self.filePath = filePath
        self.sizeBytes = sizeBytes
        self.day = day
        self.hourRecord = hourRecord
        self.clipFilename = clipFilename
    }
}

/// Central `@MainActor @Observable` store bridging the Rust `StitcherEngine` to SwiftUI views.
@MainActor
@Observable
final class StitcherStore {
    let settings: AppSettings

    // Navigation & Scan State
    var sidebarSelection: SidebarSelection?
    var days: [DayRecord] = []
    var compiledVideos: [CompiledVideoItem] = []
    var lastScanSummary: String = ""
    var isScanning: Bool = false
    var scanError: String?

    // Selection State ("YYYYMMDD_HH" keys)
    var selectedHours: Set<String> = []

    // Embedded Cinema Preview Stage State
    var stagePreview: StagePreviewState?

    // Job Queue State
    var jobs: [StitchJobSnapshot] = []
    var activeJobCount: Int {
        jobs.filter { !$0.status.isTerminal }.count
    }
    var failedOrCancelledCount: Int {
        jobs.filter { $0.status == .failed || $0.status == .cancelled }.count
    }
    var completedJobCount: Int {
        jobs.filter { $0.status == .completed }.count
    }
    var aggregateProgress: Double {
        guard !jobs.isEmpty else { return 0.0 }
        let total = jobs.reduce(0.0) { acc, job in
            switch job.status {
            case .completed, .failed, .cancelled:
                return acc + 1.0
            case .running, .remuxingFallback:
                return acc + Double(job.progress)
            case .pending:
                return acc
            }
        }
        return min(max(total / Double(jobs.count), 0.0), 1.0)
    }

    // SD Card Auto-Detection Banner
    var detectedSDCard: DetectedSDCard?
    var dismissedSDCardId: String?

    // Sheets, Disk Guard & Confirmation State
    var inspectingTarget: InspectorTarget?
    var activePlayback: PlaybackTarget?
    var pendingDeleteConfirmationAction: (() -> Void)?
    var showDeleteConfirmation: Bool = false
    var errorBanner: String?

    @ObservationIgnored private var engine: StitcherEngine!
    @ObservationIgnored private var bridgeAdapter: StitcherEventBridge!
    @ObservationIgnored private var sdMonitor: SDCardMonitor?
    @ObservationIgnored private var knownCompletedJobIds: Set<String> = []
    @ObservationIgnored private var needsRescanOnIdle: Bool = false

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

        self.sdMonitor = SDCardMonitor { [weak self] card in
            guard let self else { return }
            if let card, card.id != self.dismissedSDCardId {
                self.detectedSDCard = card
            } else if card == nil {
                self.detectedSDCard = nil
                self.dismissedSDCardId = nil
            }
        }
    }

    // MARK: - Formatting Helpers

    static func formatHour12(_ hourStr: String) -> String {
        if hourStr == "ALL" { return "Full Day" }
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

    func representativeClipPath(for hourRecord: HourRecord) -> String? {
        guard !hourRecord.clips.isEmpty else { return nil }
        let midIndex = hourRecord.clips.count / 2
        let clipName = hourRecord.clips[midIndex]
        return URL(fileURLWithPath: hourRecord.sourceDirPath)
            .appendingPathComponent(clipName)
            .path
    }

    // MARK: - Cinema Preview Stage Controls

    func previewHour(_ hourRecord: HourRecord, inDay day: String, clipFilename: String? = nil, autoPlay: Bool = false) {
        guard let clip = clipFilename ?? hourRecord.clips.first else { return }
        let path = URL(fileURLWithPath: hourRecord.sourceDirPath)
            .appendingPathComponent(clip)
            .path
        stagePreview = StagePreviewState(
            mode: .rawHour(day: day, hourRecord: hourRecord, clipFilename: clip),
            videoPath: path,
            autoPlay: autoPlay
        )
    }

    func previewCompiledVideo(_ item: CompiledVideoItem, autoPlay: Bool = true) {
        stagePreview = StagePreviewState(
            mode: .compiled(item),
            videoPath: item.filePath,
            autoPlay: autoPlay
        )
        if case .day = sidebarSelection {
            // Stay on current day detail so Cinema Preview Stage shows it immediately
        } else if let firstDay = days.first {
            sidebarSelection = .day(firstDay.day)
        } else {
            // If no day scanned yet, open Theater Sheet directly
            activePlayback = PlaybackTarget(
                title: item.displayTitle,
                filePath: item.filePath,
                sizeBytes: item.sizeBytes
            )
        }
    }

    func openTheaterForCurrentStage() {
        guard let stage = stagePreview else { return }
        switch stage.mode {
        case .rawHour(let day, let hourRecord, let clipFilename):
            let title = "\(StudioTheme.formatDateDisplay(day)) · \(StudioTheme.formatHourMinute12(hourRecord.hour, minuteFilename: clipFilename))"
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: stage.videoPath)[.size] as? UInt64)
            activePlayback = PlaybackTarget(
                title: title,
                filePath: stage.videoPath,
                sizeBytes: fileSize,
                day: day,
                hourRecord: hourRecord,
                clipFilename: clipFilename
            )
        case .compiled(let item):
            activePlayback = PlaybackTarget(
                title: item.displayTitle,
                filePath: item.filePath,
                sizeBytes: item.sizeBytes
            )
        }
    }

    func openTheaterForHour(_ hourRecord: HourRecord, inDay day: String) {
        guard let clip = hourRecord.clips.first else { return }
        let path = URL(fileURLWithPath: hourRecord.sourceDirPath)
            .appendingPathComponent(clip)
            .path
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64)
        let title = "\(StudioTheme.formatDateDisplay(day)) · \(StudioTheme.formatHourMinute12(hourRecord.hour, minuteFilename: clip))"
        stagePreview = StagePreviewState(
            mode: .rawHour(day: day, hourRecord: hourRecord, clipFilename: clip),
            videoPath: path,
            autoPlay: false
        )
        activePlayback = PlaybackTarget(
            title: title,
            filePath: path,
            sizeBytes: fileSize,
            day: day,
            hourRecord: hourRecord,
            clipFilename: clip
        )
    }

    func syncStagePreviewForDay(_ dayRecord: DayRecord) {
        if let current = stagePreview {
            if case .rawHour(let currentDay, _, _) = current.mode, currentDay == dayRecord.day {
                return
            }
            if case .compiled = current.mode {
                return
            }
        }
        if let firstHour = dayRecord.hours.first(where: { !$0.clips.isEmpty }) {
            previewHour(firstHour, inDay: dayRecord.day, autoPlay: false)
        }
    }

    // MARK: - Folder Ingestion (Browse, Drag-and-Drop, SD Auto-Detect)

    func browseSourceFolder() {
        if let path = FolderPickerService.pickFolder(prompt: "Select Wyze Camera Record Folder") {
            settings.sourceDir = path
            Task { await scanSourceDirectory() }
        }
    }

    func handleDroppedFolderURL(_ url: URL) {
        var isDir: ObjCBool = false
        let targetURL: URL
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            targetURL = url
        } else {
            targetURL = url.deletingLastPathComponent()
        }
        settings.sourceDir = targetURL.path
        Task { await scanSourceDirectory() }
    }

    func scanDetectedSDCard() {
        guard let card = detectedSDCard else { return }
        settings.sourceDir = card.recordPath
        dismissedSDCardId = card.id
        detectedSDCard = nil
        Task { await scanSourceDirectory() }
    }

    func dismissSDCardBanner() {
        dismissedSDCardId = detectedSDCard?.id
        detectedSDCard = nil
    }

    func scanSourceDirectory() async {
        let source = settings.sourceDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            scanError = "Choose a Wyze /record directory first."
            return
        }

        let previouslySelectedDay: String?
        if case .day(let dayId) = sidebarSelection {
            previouslySelectedDay = dayId
        } else {
            previouslySelectedDay = nil
        }

        isScanning = true
        scanError = nil
        selectedHours.removeAll()

        do {
            let result = try await engine.scanDirectory(sourceDir: source)
            days = result.days
            lastScanSummary = "\(result.totalDays) days • \(result.totalHours) hours • \(result.totalClips) clips (\(result.scanDurationMs) ms)"

            refreshCompiledVideos()

            if let prev = previouslySelectedDay, let matched = result.days.first(where: { $0.day == prev }) {
                sidebarSelection = .day(prev)
                if let firstHour = matched.hours.first(where: { !$0.clips.isEmpty }) {
                    previewHour(firstHour, inDay: matched.day, autoPlay: false)
                }
            } else if sidebarSelection == .queue {
                // Keep Queue open if auto-rescan triggered while viewing Queue.
            } else if let firstDay = result.days.first {
                sidebarSelection = .day(firstDay.day)
                if let firstHour = firstDay.hours.first(where: { !$0.clips.isEmpty }) {
                    previewHour(firstHour, inDay: firstDay.day, autoPlay: false)
                }
            } else {
                sidebarSelection = nil
                stagePreview = nil
                scanError = "No supported Wyze footage found in the selected folder. Ensure the folder contains hour directories with .mp4 clips or a Wyze record structure."
            }
        } catch {
            days = []
            stagePreview = nil
            scanError = error.localizedDescription
        }

        isScanning = false
    }

    func refreshCompiledVideos() {
        let fm = FileManager.default
        var discovered: [CompiledVideoItem] = []
        var seenPaths: Set<String> = []

        func scanFolder(_ dirPath: String) {
            guard !dirPath.isEmpty else { return }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { return }
            guard let items = try? fm.contentsOfDirectory(atPath: dirPath) else { return }
            for name in items where name.lowercased().hasSuffix(".mp4") {
                let fullPath = URL(fileURLWithPath: dirPath).appendingPathComponent(name).path
                guard !seenPaths.contains(fullPath) else { continue }
                guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                      let fileType = attrs[.type] as? FileAttributeType,
                      fileType == .typeRegular
                else { continue }

                seenPaths.insert(fullPath)
                let size = (attrs[.size] as? UInt64) ?? 0
                let modDate = (attrs[.modificationDate] as? Date) ?? .distantPast
                discovered.append(
                    CompiledVideoItem(
                        filePath: fullPath,
                        fileName: name,
                        displayTitle: Self.prettyCompiledTitle(from: name),
                        sizeBytes: size,
                        modifiedDate: modDate
                    )
                )
            }
        }

        if !settings.customOutputDir.isEmpty {
            scanFolder(settings.customOutputDir)
        }

        let source = settings.sourceDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !source.isEmpty {
            scanFolder(source)
            for day in days {
                let dayPath = URL(fileURLWithPath: source).appendingPathComponent(day.day).path
                scanFolder(dayPath)
            }
        }

        for job in jobs where job.status == .completed {
            if let path = job.outputPath, !seenPaths.contains(path), fm.fileExists(atPath: path) {
                let name = (path as NSString).lastPathComponent
                let attrs = try? fm.attributesOfItem(atPath: path)
                let size = (attrs?[.size] as? UInt64) ?? job.fileSizeBytes
                let modDate = (attrs?[.modificationDate] as? Date) ?? Date()
                seenPaths.insert(path)
                discovered.append(
                    CompiledVideoItem(
                        filePath: path,
                        fileName: name,
                        displayTitle: Self.prettyCompiledTitle(from: name),
                        sizeBytes: size,
                        modifiedDate: modDate
                    )
                )
            }
        }

        compiledVideos = discovered.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    private static func prettyCompiledTitle(from filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        let parts = base.split(separator: "_")
        if parts.count == 2 {
            let datePart = String(parts[0]).replacingOccurrences(of: "-", with: "")
            let timePart = String(parts[1]).replacingOccurrences(of: "!", with: "")
            if datePart.count == 8 {
                let dateLabel = StudioTheme.formatDateDisplay(datePart, includeWeekday: false)
                if timePart.uppercased() == "FULLDAY" || timePart.uppercased() == "ALL" {
                    return "\(dateLabel) · Full Day"
                }
                if timePart.count == 4, timePart.hasSuffix("00") {
                    let hourPrefix = String(timePart.prefix(2))
                    return "\(dateLabel) · \(formatHour12(hourPrefix))"
                }
                if timePart.count == 2, Int(timePart) != nil {
                    return "\(dateLabel) · \(formatHour12(timePart))"
                }
                return "\(dateLabel) · \(timePart)"
            }
        }
        return base
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

    func estimatedSelectedBytes() -> UInt64 {
        var total: UInt64 = 0
        for day in days {
            for hour in day.hours {
                if selectedHours.contains(hourKey(day: day.day, hour: hour.hour)) {
                    total += hour.totalSizeBytes
                }
            }
        }
        return total
    }

    // MARK: - Job Submission (Per-Hour & Full-Day) + Disk Space Guard

    func requestStitchSelectedHours() {
        guard !selectedHours.isEmpty else { return }

        var requests: [StitchJobRequest] = []
        var estimatedBytes: UInt64 = 0

        for day in days {
            for hour in day.hours {
                if selectedHours.contains(hourKey(day: day.day, hour: hour.hour)) {
                    requests.append(
                        StitchJobRequest(
                            day: day.day,
                            hour: hour.hour,
                            mode: .singleHour,
                            hourDirPaths: [hour.sourceDirPath],
                            selectedClips: nil
                        )
                    )
                    estimatedBytes += hour.totalSizeBytes
                }
            }
        }

        guard !requests.isEmpty else { return }
        submitWithGuards(
            requests: requests,
            estimatedOutputBytes: estimatedBytes,
            clearSelectionOnSuccess: true
        )
    }

    /// Merges all recorded hours (or only the currently selected hours) of a day into one continuous MP4.
    func requestStitchFullDay(for dayRecord: DayRecord, onlySelectedHours: Bool = false) {
        let targetHours: [HourRecord]
        if onlySelectedHours {
            targetHours = dayRecord.hours.filter {
                selectedHours.contains(hourKey(day: dayRecord.day, hour: $0.hour))
            }
        } else {
            targetHours = dayRecord.hours
        }

        guard !targetHours.isEmpty else { return }

        let hourPaths = targetHours.map(\.sourceDirPath)
        let estimatedBytes = targetHours.reduce(UInt64(0)) { $0 + $1.totalSizeBytes }
        let label = onlySelectedHours ? "\(targetHours.count)h Merge" : "ALL"

        let request = StitchJobRequest(
            day: dayRecord.day,
            hour: label,
            mode: .fullDay,
            hourDirPaths: hourPaths,
            selectedClips: nil
        )

        submitWithGuards(
            requests: [request],
            estimatedOutputBytes: estimatedBytes,
            clearSelectionOnSuccess: onlySelectedHours
        )
    }

    func requestStitchCustomSelection(target: InspectorTarget, clips: [String]) {
        guard !clips.isEmpty else { return }

        let fraction = Double(clips.count) / Double(max(target.hourRecord.clipCount, 1))
        let estimatedBytes = UInt64(Double(target.hourRecord.totalSizeBytes) * fraction)

        let request = StitchJobRequest(
            day: target.day,
            hour: target.hourRecord.hour,
            mode: .singleHour,
            hourDirPaths: [target.hourRecord.sourceDirPath],
            selectedClips: clips.sorted()
        )
        inspectingTarget = nil

        submitWithGuards(
            requests: [request],
            estimatedOutputBytes: estimatedBytes,
            clearSelectionOnSuccess: false
        )
    }

    private func submitWithGuards(
        requests: [StitchJobRequest],
        estimatedOutputBytes: UInt64,
        clearSelectionOnSuccess: Bool
    ) {
        let destinationDir = settings.useSameFolder
            ? settings.sourceDir
            : settings.customOutputDir.trimmingCharacters(in: .whitespacesAndNewlines)

        if !destinationDir.isEmpty {
            let diskStatus = DiskSpaceService.checkAvailableSpace(
                forDestinationPath: destinationDir,
                estimatedOutputBytes: estimatedOutputBytes
            )
            if case .insufficient(let required, let available, let dest) = diskStatus {
                errorBanner = "Insufficient disk space on destination volume (\(dest)). Estimated required (with 500 MB buffer): \(Self.formatBytes(required)), available: \(Self.formatBytes(available))."
                return
            }
        }

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
            updateDockProgress()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    // MARK: - Queue Controls (Cancel, Cancel All, Retry, Clear)

    func cancelJob(_ jobId: String) {
        do {
            _ = try engine.cancelJob(jobId: jobId)
            updateDockProgress()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func cancelAllJobs() {
        jobs = engine.cancelAllJobs()
        updateDockProgress()
    }

    func retryJob(_ jobId: String) {
        errorBanner = nil
        do {
            _ = try engine.retryJob(jobId: jobId)
            updateDockProgress()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func retryAllFailedJobs() {
        let failedIds = jobs
            .filter { $0.status == .failed || $0.status == .cancelled }
            .map(\.id)
        for id in failedIds {
            retryJob(id)
        }
    }

    func clearFinishedJobs() {
        jobs = engine.clearFinishedJobs()
        updateDockProgress()
    }

    func playCompletedJob(_ job: StitchJobSnapshot) {
        guard let outputPath = job.outputPath else { return }
        let suffix = job.mode == .fullDay ? "Full Day" : Self.formatHour12(job.hour)
        let title = "\(StudioTheme.formatDateDisplay(job.day)) · \(suffix)"
        activePlayback = PlaybackTarget(
            title: title,
            filePath: outputPath,
            sizeBytes: job.fileSizeBytes
        )
    }

    func revealJobInFinder(_ job: StitchJobSnapshot) {
        guard let outputPath = job.outputPath else { return }
        FolderPickerService.revealInFinder(path: outputPath)
    }

    private func updateDockProgress() {
        DockProgressService.shared.update(
            progress: aggregateProgress,
            activeCount: activeJobCount
        )
    }

    // MARK: - Rust Push Callbacks (Dispatched on @MainActor)

    fileprivate func handleJobUpdated(_ snapshot: StitchJobSnapshot) {
        if let idx = jobs.firstIndex(where: { $0.id == snapshot.id }) {
            jobs[idx] = snapshot
        } else {
            jobs.append(snapshot)
        }

        if snapshot.status == .completed && !knownCompletedJobIds.contains(snapshot.id) {
            knownCompletedJobIds.insert(snapshot.id)
            refreshCompiledVideos()
            if snapshot.deletedSources {
                needsRescanOnIdle = true
            }
            if settings.sendNotifications {
                let label = snapshot.mode == .fullDay ? "Full Day" : Self.formatHour12(snapshot.hour)
                NotificationService.sendJobNotification(
                    title: "Stitch Complete",
                    body: "Compiled \(Self.formatDay(snapshot.day)) \(label) (\(Self.formatBytes(snapshot.fileSizeBytes)))."
                )
            }
            if settings.autoRevealInFinder, let path = snapshot.outputPath {
                FolderPickerService.revealInFinder(path: path)
            }
        } else if snapshot.status == .failed && !knownCompletedJobIds.contains(snapshot.id) {
            knownCompletedJobIds.insert(snapshot.id)
            if settings.sendNotifications {
                let label = snapshot.mode == .fullDay ? "Full Day" : Self.formatHour12(snapshot.hour)
                NotificationService.sendJobNotification(
                    title: "Stitch Failed",
                    body: "\(Self.formatDay(snapshot.day)) \(label): \(snapshot.errorMessage ?? "Unknown error")"
                )
            }
        }

        updateDockProgress()
    }

    fileprivate func handleJobProgress(_ event: JobProgressEvent) {
        guard let idx = jobs.firstIndex(where: { $0.id == event.jobId }) else { return }
        let current = jobs[idx]
        jobs[idx] = StitchJobSnapshot(
            id: current.id,
            day: current.day,
            hour: current.hour,
            mode: current.mode,
            status: event.status,
            totalClips: event.totalClips,
            processedClips: event.processedClips,
            progress: event.progress,
            currentClipName: event.currentClipName,
            outputPath: current.outputPath,
            fileSizeBytes: current.fileSizeBytes,
            durationMs: current.durationMs,
            usedAudioFallback: current.usedAudioFallback || event.status == .remuxingFallback,
            deletedSources: current.deletedSources,
            errorMessage: current.errorMessage,
            logs: current.logs
        )
        updateDockProgress()
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
            mode: current.mode,
            status: current.status,
            totalClips: current.totalClips,
            processedClips: current.processedClips,
            progress: current.progress,
            currentClipName: current.currentClipName,
            outputPath: current.outputPath,
            fileSizeBytes: current.fileSizeBytes,
            durationMs: current.durationMs,
            usedAudioFallback: current.usedAudioFallback,
            deletedSources: current.deletedSources,
            errorMessage: current.errorMessage,
            logs: updatedLogs
        )
    }

    fileprivate func handleQueueIdle() {
        DockProgressService.shared.clear()
        if needsRescanOnIdle {
            needsRescanOnIdle = false
            Task { await scanSourceDirectory() }
        }
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
        Task { @MainActor [weak self] in
            self?.store?.handleQueueIdle()
        }
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
