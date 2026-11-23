import AppKit
import Foundation

struct DetectedSDCard: Identifiable, Equatable {
    let id: String
    let volumeName: String
    let recordPath: String
}

/// Watches macOS `/Volumes` mounts for Wyze SD cards containing a `record/` directory.
@MainActor
final class SDCardMonitor {
    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?
    private let onDetected: (DetectedSDCard?) -> Void

    init(onDetected: @escaping (DetectedSDCard?) -> Void) {
        self.onDetected = onDetected
        startObserving()
        scanMountedVolumes()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        if let mountObserver { center.removeObserver(mountObserver) }
        if let unmountObserver { center.removeObserver(unmountObserver) }
    }

    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        mountObserver = center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
                return
            }
            Task { @MainActor [weak self] in
                if let card = Self.inspectVolume(url) {
                    self?.onDetected(card)
                }
            }
        }

        unmountObserver = center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanMountedVolumes()
            }
        }
    }

    func scanMountedVolumes() {
        guard let volumeURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsInternalKey, .volumeNameKey],
            options: [.skipHiddenVolumes]
        ) else {
            onDetected(nil)
            return
        }

        for url in volumeURLs {
            if let card = Self.inspectVolume(url) {
                onDetected(card)
                return
            }
        }
        onDetected(nil)
    }

    private static func inspectVolume(_ volumeURL: URL) -> DetectedSDCard? {
        // Ignore the root boot drive.
        if volumeURL.path == "/" { return nil }

        let values = try? volumeURL.resourceValues(forKeys: [
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeNameKey
        ])
        let isRemovable = values?.volumeIsRemovable ?? false
        let isExternal = (values?.volumeIsInternal == false)
        guard isRemovable || isExternal else { return nil }

        let recordURL = volumeURL.appendingPathComponent("record", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: recordURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }

        let name = values?.volumeName ?? volumeURL.lastPathComponent
        return DetectedSDCard(
            id: volumeURL.path,
            volumeName: name,
            recordPath: recordURL.path
        )
    }
}
