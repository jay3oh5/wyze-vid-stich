import AppKit
import Foundation

/// Native AppKit folder picker (`NSOpenPanel`) and Finder file reveal service.
@MainActor
enum FolderPickerService {
    static func pickFolder(prompt: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = prompt
        panel.prompt = "Select Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        // Default to /Volumes when an external Wyze SD card is mounted.
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        if FileManager.default.fileExists(atPath: volumesURL.path) {
            panel.directoryURL = volumesURL
        }

        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }
}
