import SwiftUI
import WyzeStitcherKit

/// User-selectable macOS appearance mode, defaulting to adaptive system appearance (Auto).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto (System)"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// User-selectable compiled filename format, defaulting to 24-hour sortable (`YYYY-MM-DD_HH00.mp4`).
enum NamingPreference: String, CaseIterable, Identifiable {
    case twentyFourHour = "24h"
    case twelveHourLegacy = "12h_legacy"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twentyFourHour: return "24-Hour Sortable (YYYY-MM-DD_HH00.mp4)"
        case .twelveHourLegacy: return "12-Hour Legacy (YYYY-MM-DD_!12AM.mp4)"
        }
    }

    var ffiFormat: OutputNamingFormat {
        switch self {
        case .twentyFourHour: return .twentyFourHour
        case .twelveHourLegacy: return .twelveHourLegacy
        }
    }
}

/// Persistent application settings stored in macOS `UserDefaults` via `@AppStorage`.
@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("wyze_sourceDir") var sourceDir: String = ""
    @AppStorage("wyze_useSameFolder") var useSameFolder: Bool = true
    @AppStorage("wyze_customOutputDir") var customOutputDir: String = ""
    @AppStorage("wyze_overwrite") var overwrite: Bool = false
    @AppStorage("wyze_deleteAfterCompile") var deleteAfterCompile: Bool = false
    @AppStorage("wyze_autoRevealInFinder") var autoRevealInFinder: Bool = false
    @AppStorage("wyze_sendNotifications") var sendNotifications: Bool = true
    @AppStorage("wyze_namingFormat") var namingFormatRaw: String = NamingPreference.twentyFourHour.rawValue
    @AppStorage("wyze_appearanceMode") var appearanceModeRaw: String = AppearanceMode.auto.rawValue
    @AppStorage("wyze_previewSize") var previewSizeRaw: String = HourPreviewSize.large.rawValue
    @AppStorage("wyze_autoAdvancePreview") var autoAdvancePreview: Bool = true

    var namingPreference: NamingPreference {
        get { NamingPreference(rawValue: namingFormatRaw) ?? .twentyFourHour }
        set { namingFormatRaw = newValue.rawValue }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .auto }
        set { appearanceModeRaw = newValue.rawValue }
    }

    var previewSize: HourPreviewSize {
        get { HourPreviewSize(rawValue: previewSizeRaw) ?? .large }
        set { previewSizeRaw = newValue.rawValue }
    }

    func toStitchOptions() -> StitchOptions {
        StitchOptions(
            sourceDir: sourceDir,
            customOutputDir: useSameFolder ? nil : customOutputDir,
            useSameFolder: useSameFolder,
            overwrite: overwrite,
            deleteAfterCompile: deleteAfterCompile,
            namingFormat: namingPreference.ffiFormat
        )
    }
}
