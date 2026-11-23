import SwiftUI

@main
struct WyzeVidStitchApp: App {
    @StateObject private var settings = AppSettings()
    @State private var store: StitcherStore

    init() {
        let appSettings = AppSettings()
        _settings = StateObject(wrappedValue: appSettings)
        _store = State(initialValue: StitcherStore(settings: appSettings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environment(store)
                .preferredColorScheme(settings.appearanceMode.colorScheme)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Select Source Folder...") {
                    store.browseSourceFolder()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Rescan Source Folder") {
                    Task { await store.scanSourceDirectory() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(settings.sourceDir.isEmpty || store.isScanning)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.appearanceMode.colorScheme)
        }
    }
}
