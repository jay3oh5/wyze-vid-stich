import AppKit
import AVFoundation
import SwiftUI

/// Asynchronously extracts and caches crisp 16:9 video preview thumbnails from local `.mp4` files
/// using native `AVAssetImageGenerator` (hardware-accelerated on Apple Silicon & Intel Macs).
final class VideoThumbnailService: @unchecked Sendable {
    static let shared = VideoThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 96 * 1024 * 1024 // ~96 MB image cache budget
    }

    func cachedImage(for path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    /// Loads a scaled preview frame for `path`, deduplicating concurrent requests for the same clip.
    func thumbnail(for path: String, maxSize: CGSize = CGSize(width: 720, height: 405)) async -> NSImage? {
        if let hit = cache.object(forKey: path as NSString) {
            return hit
        }

        let existingTask: Task<NSImage?, Never>? = lock.withLock {
            inFlight[path]
        }
        if let existingTask {
            return await existingTask.value
        }

        let task = Task.detached(priority: .userInitiated) { [weak self] () -> NSImage? in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = maxSize
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity

            let sampleTimes: [CMTime] = [
                CMTime(seconds: 0.25, preferredTimescale: 600),
                .zero
            ]

            for time in sampleTimes {
                if Task.isCancelled { return nil }
                do {
                    let (cgImage, _) = try await generator.image(at: time)
                    let nsImage = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                    let approxBytes = cgImage.bytesPerRow * cgImage.height
                    self?.cache.setObject(nsImage, forKey: path as NSString, cost: approxBytes)
                    return nsImage
                } catch {
                    continue
                }
            }
            return nil
        }

        lock.withLock {
            inFlight[path] = task
        }

        let result = await task.value

        lock.withLock {
            inFlight[path] = nil
        }

        return result
    }
}

/// Reusable SwiftUI thumbnail surface that asynchronously renders a real video frame with a clean fallback.
struct VideoThumbnailView: View {
    let filePath: String?
    var placeholderIcon: String = "film"

    @State private var image: NSImage?
    @State private var didAttemptLoad: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.95),
                    Color.black.opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
            } else {
                VStack(spacing: 6) {
                    if !didAttemptLoad && filePath != nil {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: placeholderIcon)
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }
        }
        .clipped()
        .task(id: filePath) {
            guard let filePath, !filePath.isEmpty else {
                image = nil
                didAttemptLoad = true
                return
            }

            if let cached = VideoThumbnailService.shared.cachedImage(for: filePath) {
                image = cached
                didAttemptLoad = true
                return
            }

            didAttemptLoad = false
            let loaded = await VideoThumbnailService.shared.thumbnail(for: filePath)
            if !Task.isCancelled {
                image = loaded
                didAttemptLoad = true
            }
        }
    }
}
