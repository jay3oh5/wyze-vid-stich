import SwiftUI
import WyzeStitcherKit

/// Native macOS Settings window (`Cmd+,`) for Output & Naming, Appearance, and Automation.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    private var previewFilename: String {
        previewOutputFilename(
            day: "20260529",
            hour: "00",
            format: settings.namingPreference.ffiFormat
        )
    }

    private var previewAfternoonFilename: String {
        previewOutputFilename(
            day: "20260529",
            hour: "14",
            format: settings.namingPreference.ffiFormat
        )
    }

    var body: some View {
        TabView {
            outputAndNamingTab
                .tabItem {
                    Label("Output & Naming", systemImage: "folder.badge.gearshape")
                }

            appearanceTab
                .tabItem {
                    Label("Appearance & Previews", systemImage: "circle.lefthalf.filled")
                }

            automationTab
                .tabItem {
                    Label("Automation & Safety", systemImage: "bell.badge")
                }
        }
        .frame(width: 560, height: 390)
        .padding(16)
    }

    private var outputAndNamingTab: some View {
        Form {
            Section("Destination Folder") {
                Toggle("Save compiled videos inside original day folders (record/YYYYMMDD/)", isOn: $settings.useSameFolder)

                if !settings.useSameFolder {
                    HStack {
                        TextField("Custom destination directory", text: $settings.customOutputDir)
                            .font(.system(.body, design: .monospaced))
                        Button("Browse...") {
                            if let folder = FolderPickerService.pickFolder(prompt: "Select Custom Output Folder") {
                                settings.customOutputDir = folder
                            }
                        }
                    }
                }

                Toggle("Overwrite existing compiled files", isOn: $settings.overwrite)
            }

            Section("Output Filename Format") {
                Picker("Naming Convention", selection: $settings.namingPreference) {
                    ForEach(NamingPreference.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)

                HStack {
                    Text("Hourly preview:")
                        .foregroundStyle(.secondary)
                    Text("\(previewFilename), \(previewAfternoonFilename)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                HStack {
                    Text("Full-Day preview:")
                        .foregroundStyle(.secondary)
                    Text(previewFullDayFilename(day: "20260529"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Section("Window Theme") {
                Picker("Appearance", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Defaults to Auto to adapt seamlessly with macOS Light and Dark Mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Video Previews") {
                Picker("Default Hour Card Size", selection: $settings.previewSize) {
                    ForEach(HourPreviewSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Auto-advance between 1-minute clips during preview", isOn: $settings.autoAdvancePreview)

                Text("Choose larger preview cards for visual scanning, or Cinema for full-width widescreen frames.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var automationTab: some View {
        Form {
            Section("Post-Compile Actions") {
                Toggle("Reveal output file in Finder when job completes", isOn: $settings.autoRevealInFinder)

                Toggle("Send macOS notification when job finishes", isOn: $settings.sendNotifications)
                    .onChange(of: settings.sendNotifications) { _, enabled in
                        if enabled {
                            NotificationService.requestAuthorization()
                        }
                    }
            }

            Section("Destructive Cleanup") {
                Toggle(isOn: $settings.deleteAfterCompile) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete source 1-minute clips after verified compile")
                            .foregroundStyle(.red)
                        Text("Also removes empty hour folders. Confirmation is required before stitching starts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
