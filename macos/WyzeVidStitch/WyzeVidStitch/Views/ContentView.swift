import SwiftUI
import UniformTypeIdentifiers
import WyzeStitcherKit

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(StitcherStore.self) private var store

    @State private var isDropTargeted: Bool = false

    var body: some View {
        @Bindable var bindableStore = store

        NavigationSplitView {
            DaySidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if let card = store.detectedSDCard {
                    sdCardBanner(card)
                    Divider()
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
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(settings.sourceDir.isEmpty || store.isScanning)
                .help("Scan source directory (Cmd+R)")
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if !store.selectedHours.isEmpty {
                        let estBytes = store.estimatedSelectedBytes()
                        if estBytes > 0 {
                            Text("~\(StitcherStore.formatBytes(estBytes))")
                                .font(.caption.monospacedDigit())
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
                    .disabled(store.selectedHours.isEmpty)
                }
            }
        }
        .sheet(item: $bindableStore.inspectingTarget) { target in
            ClipInspectorSheet(target: target)
        }
        .sheet(item: $bindableStore.activePlayback) { playback in
            NativeVideoPlayerSheet(target: playback)
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
        }
    }

    private func sdCardBanner(_ card: DetectedSDCard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sdcard.fill")
                .foregroundStyle(Color.accentColor)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.1))
    }

    private var dropTargetOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                .padding(20)
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.accentColor)
                Text("Drop Wyze Record Folder or SD Card")
                    .font(.title3.weight(.semibold))
                Text("Release to scan footage density and gaps automatically")
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
        VStack(spacing: 16) {
            if let scanError = store.scanError {
                ContentUnavailableView(
                    "Scan Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(scanError)
                )
            } else {
                ContentUnavailableView {
                    Label("Wyze SD Card Video Stitcher", systemImage: "film.stack")
                } description: {
                    Text(
                        settings.sourceDir.isEmpty
                            ? "Select or drop your Wyze camera's /record folder onto this window to scan footage density and missing minute gaps."
                            : "Ready to scan \(settings.sourceDir)."
                    )
                } actions: {
                    HStack(spacing: 12) {
                        Button("Select Source Folder...") {
                            store.browseSourceFolder()
                        }
                        .buttonStyle(.borderedProminent)

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
        .padding()
    }
}
