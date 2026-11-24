import SwiftUI
import WyzeStitcherKit

/// User-selectable preview card density in the Hour Preview Grid.
enum HourPreviewSize: String, CaseIterable, Identifiable {
    case compact = "compact"
    case large = "large"
    case cinema = "cinema"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "3-Up"
        case .large: return "Large"
        case .cinema: return "Cinema"
        }
    }

    var systemImage: String {
        switch self {
        case .compact: return "square.grid.3x2"
        case .large: return "square.grid.2x2"
        case .cinema: return "rectangle"
        }
    }

    var gridColumns: [GridItem] {
        switch self {
        case .compact:
            return [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 16)]
        case .large:
            return [GridItem(.adaptive(minimum: 370, maximum: 540), spacing: 20)]
        case .cinema:
            return [GridItem(.flexible(), spacing: 20)]
        }
    }
}

/// Filter options for narrowing hours within a recorded day.
enum HourFilterMode: String, CaseIterable, Identifiable {
    case all
    case complete
    case gaps
    case selected

    var id: String { rawValue }
}

/// Adaptive macOS studio color palette and shared formatting utilities.
enum StudioTheme {
    static let accent = Color(red: 0.055, green: 0.647, blue: 0.914) // Signal Sky (#0EA5E9)
    static let completeGreen = Color(red: 0.063, green: 0.725, blue: 0.506) // Emerald (#10B981)
    static let minorGapAmber = Color(red: 0.961, green: 0.620, blue: 0.043) // Amber (#F59E0B)
    static let severeGapRed = Color(red: 0.937, green: 0.267, blue: 0.267) // Crimson (#EF4444)

    static func canvasBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.039, green: 0.047, blue: 0.067) // #0A0C11
            : Color(nsColor: .windowBackgroundColor)
    }

    static func cardSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.071, green: 0.086, blue: 0.125) // #121620
            : Color(nsColor: .controlBackgroundColor)
    }

    static func elevatedSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.094, green: 0.114, blue: 0.165) // #181D2A
            : Color(nsColor: .underPageBackgroundColor)
    }

    static func hairlineBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.09)
            : Color(nsColor: .separatorColor)
    }

    static func densityColor(for density: FootageDensity) -> Color {
        switch density {
        case .complete: return completeGreen
        case .minorGaps: return minorGapAmber
        case .severeGaps: return severeGapRed
        case .empty: return Color.secondary.opacity(0.2)
        }
    }

    /// Formats `"20260529"` into `"Fri, May 29, 2026"` or `"May 29, 2026"`.
    static func formatDateDisplay(_ rawDay: String, includeWeekday: Bool = true) -> String {
        guard rawDay.count == 8,
              let year = Int(rawDay.prefix(4)),
              let month = Int(rawDay.dropFirst(4).prefix(2)),
              let day = Int(rawDay.dropFirst(6).prefix(2))
        else {
            return rawDay
        }

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.calendar = Calendar(identifier: .gregorian)

        guard let date = comps.date else { return StitcherStore.formatDay(rawDay) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = includeWeekday ? "EEE, MMM d, yyyy" : "MMM d, yyyy"
        return formatter.string(from: date)
    }

    /// Formats `"00"` -> `"12:00 – 12:59 AM"`.
    static func formatHourRange(_ hourStr: String) -> String {
        guard let h = Int(hourStr), (0...23).contains(h) else { return hourStr }
        let ampm = h >= 12 ? "PM" : "AM"
        let displayH = h % 12 == 0 ? 12 : h % 12
        return "\(displayH):00 – \(displayH):59 \(ampm)"
    }

    /// Formats `"00"` + `"05.mp4"` -> `"12:05 AM"`.
    static func formatHourMinute12(_ hourStr: String, minuteFilename: String) -> String {
        guard let h = Int(hourStr), (0...23).contains(h) else { return "\(hourStr):\(minuteFilename)" }
        let ampm = h >= 12 ? "PM" : "AM"
        let displayH = h % 12 == 0 ? 12 : h % 12
        let minuteClean = minuteFilename
            .replacingOccurrences(of: ".mp4", with: "", options: .caseInsensitive)
        let padded = minuteClean.count == 1 ? "0\(minuteClean)" : minuteClean
        return "\(displayH):\(padded) \(ampm)"
    }
}
