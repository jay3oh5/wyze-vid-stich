import Foundation

enum DiskSpaceStatus {
    case sufficient(availableBytes: UInt64)
    case insufficient(requiredBytes: UInt64, availableBytes: UInt64, destinationPath: String)
}

/// Pre-flight volume free space guard preventing mid-compile disk exhaustion.
enum DiskSpaceService {
    /// Minimum safety headroom (500 MB) required beyond the estimated lossless output size.
    private static let safetyBufferBytes: UInt64 = 500 * 1024 * 1024

    static func checkAvailableSpace(
        forDestinationPath destinationPath: String,
        estimatedOutputBytes: UInt64
    ) -> DiskSpaceStatus {
        guard let existingAncestor = nearestExistingDirectory(for: destinationPath) else {
            return .sufficient(availableBytes: .max)
        }

        do {
            let values = try existingAncestor.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])

            let available: UInt64
            if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
                available = UInt64(important)
            } else if let standard = values.volumeAvailableCapacity, standard > 0 {
                available = UInt64(standard)
            } else {
                return .sufficient(availableBytes: .max)
            }

            let required = estimatedOutputBytes.saturatingAdd(safetyBufferBytes)
            if available < required {
                return .insufficient(
                    requiredBytes: required,
                    availableBytes: available,
                    destinationPath: existingAncestor.path
                )
            }
            return .sufficient(availableBytes: available)
        } catch {
            return .sufficient(availableBytes: .max)
        }
    }

    private static func nearestExistingDirectory(for rawPath: String) -> URL? {
        var url = URL(fileURLWithPath: rawPath)
        let fm = FileManager.default
        while url.path != "/" {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "/")
    }
}

private extension UInt64 {
    func saturatingAdd(_ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = self.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}
