import SwiftUI
import UniformTypeIdentifiers
import WyzeStitcherKit

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @Environment(StitcherStore.self) private var store

    @State private var isDropTargeted: Bool = false

    var body: some View {
        @Bindable var bindableStore = store

        NavigationSplitView {
            DaySidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            VStack(spacing: 0) {
                if let card = store.detectedSDCard {
                    sdCardBanner(card)
                    Divider()
                        .overlay(StudioTheme.hairlineBorder(for: colorScheme))
                }
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            if isDropTargeted {
                dropTargetOverlay
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleFileDrop(providers)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    store.browseSourceFolder()
                } label: {
                    Label("Source Folder", systemImage: "folder")
                }
                .help(settings.sourceDir.isEmpty ? "Select Wyze /record directory" : settings.sourceDir)

                Button {
                    Task { await store.scanSourceDirectory() }
                } label: {
                    if store.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(settings.sourceDir.isEmpty || store.isScanning)
                .help("Rescan source directory (Cmd+R)")
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 10) {
                    if !store.selectedHours.isEmpty {
                        let estBytes = store.estimatedSelectedBytes()
                        if estBytes > 0 {
                            Text("~\(StitcherStore.formatBytes(estBytes))")
                                .font(.system(.caption, design: .monospaced).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        store.requestStitchSelectedHours()
                    } label: {
                        Label(
                            "Stitch Selected (\(store.selectedHours.count))",
                            systemImage: "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .disabled(store.selectedHours.isEmpty)
                }
            }
        }
        .sheet(item: $bindableStore.inspectingTarget) { target in
            ClipInspectorSheet(target: target)
                .environmentObject(settings)
                .environment(store)
        }
        .sheet(item: $bindableStore.activePlayback) { playback in
            NativeVideoPlayerSheet(target: playback)
                .environmentObject(settings)
                .environment(store)
        }
        .confirmationDialog(
            "Delete Source Clips After Compile?",
            isPresented: $bindableStore.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Compile & Permanently Delete Sources", role: .destructive) {
                let action = store.pendingDeleteConfirmationAction
                store.pendingDeleteConfirmationAction = nil
                action?()
            }
            Button("Cancel", role: .cancel) {
                store.pendingDeleteConfirmationAction = nil
            }
        } message: {
            Text(
                "'Delete source clips after successful compile' is enabled in Settings. " +
                "Original 1-minute MP4 files will be permanently deleted once the compiled file is verified."
            )
        }
        .alert(
            "Stitcher Notice",
            isPresented: Binding(
                get: { store.errorBanner != nil },
                set: { if !$0 { store.errorBanner = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                store.errorBanner = nil
            }
        } message: {
            Text(store.errorBanner ?? "")
        }
        .onAppear {
            if settings.sendNotifications {
                NotificationService.requestAuthorization()
            }
            if !settings.sourceDir.isEmpty && store.days.isEmpty && !store.isScanning {
                Task { await store.scanSourceDirectory() }
            }
        }
    }

    private func sdCardBanner(_ card: DetectedSDCard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sdcard.fill")
                .foregroundStyle(StudioTheme.accent)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wyze SD Card Detected: \(card.volumeName)")
                    .font(.subheadline.weight(.semibold))
                Text(card.recordPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Scan SD Card") {
                store.scanDetectedSDCard()
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.accent)
            .controlSize(.small)

            Button {
                store.dismissSDCardBanner()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(StudioTheme.accent.opacity(0.12))
    }

    private var dropTargetOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(StudioTheme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                .padding(24)
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(StudioTheme.accent)
                Text("Drop Wyze Record Folder or SD Card")
                    .font(.title3.weight(.semibold))
                Text("Release to scan footage density, preview thumbnails, and missing minute gaps automatically")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let resolvedURL: URL?
            if let data = item as? Data {
                resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                resolvedURL = url
            } else {
                resolvedURL = nil
            }
            if let url = resolvedURL {
                Task { @MainActor in
                    store.handleDroppedFolderURL(url)
                }
            }
        }
        return true
    }

    @ViewBuilder
    private var detailContent: some View {
        switch store.sidebarSelection {
        case .queue:
            JobQueueView()
        case .day(let dayId):
            if let dayRecord = store.days.first(where: { $0.day == dayId }) {
                DayDetailView(dayRecord: dayRecord)
            } else {
                emptyWorkspace
            }
        case .none:
            emptyWorkspace
        }
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 18) {
            if let scanError = store.scanError {
                ContentUnavailableView {
                    Label("Scan Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(scanError)
                } actions: {
                    Button("Select Another Folder...") {
                        store.browseSourceFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                }
            } else {
                ContentUnavailableView {
                    Label("Wyze Video Stitcher", systemImage: "film.stack")
                } description: {
                    Text(
                        settings.sourceDir.isEmpty
                            ? "Select or drag-and-drop your Wyze microSD card's /record folder onto this window to preview footage, inspect gaps, and stitch lossless hourly videos."
                            : "Ready to scan \(settings.sourceDir)."
                    )
                } actions: {
                    HStack(spacing: 12) {
                        Button("Select Source Folder...") {
                            store.browseSourceFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioTheme.accent)

                        if !settings.sourceDir.isEmpty {
                            Button("Scan Now") {
                                Task { await store.scanSourceDirectory() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StudioTheme.canvasBackground(for: colorScheme))
    }
}
