import AppKit
import Foundation

/// Displays an aggregate macOS Dock tile progress bar and active count badge during batch compiles.
@MainActor
final class DockProgressService {
    static let shared = DockProgressService()

    private var progressIndicator: NSProgressIndicator?

    private init() {}

    func update(progress: Double, activeCount: Int) {
        let dockTile = NSApplication.shared.dockTile

        guard activeCount > 0 else {
            clear()
            return
        }

        if progressIndicator == nil {
            let size = dockTile.size
            let container = NSView(frame: NSRect(origin: .zero, size: size))

            let iconView = NSImageView(frame: container.bounds)
            iconView.image = NSApplication.shared.applicationIconImage
            iconView.imageScaling = .scaleProportionallyUpOrDown
            container.addSubview(iconView)

            let barHeight: CGFloat = 14
            let barFrame = NSRect(x: 8, y: 10, width: size.width - 16, height: barHeight)
            let indicator = NSProgressIndicator(frame: barFrame)
            indicator.style = .bar
            indicator.isIndeterminate = false
            indicator.minValue = 0.0
            indicator.maxValue = 1.0
            indicator.doubleValue = progress
            container.addSubview(indicator)

            dockTile.contentView = container
            self.progressIndicator = indicator
        } else {
            progressIndicator?.doubleValue = min(max(progress, 0.0), 1.0)
        }

        dockTile.badgeLabel = "\(activeCount)"
        dockTile.display()
    }

    func clear() {
        let dockTile = NSApplication.shared.dockTile
        if progressIndicator != nil || dockTile.badgeLabel != nil {
            progressIndicator = nil
            dockTile.contentView = nil
            dockTile.badgeLabel = nil
            dockTile.display()
        }
    }
}
