import SwiftUI
import WyzeStitcherKit

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(StitcherStore.self) private var store

    var body: some View {
        @Bindable var bindableStore = store

        NavigationSplitView {
            DaySidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            "Stitcher Error",
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
                            ? "Select your Wyze camera's /record folder to scan footage density and missing minute gaps."
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
