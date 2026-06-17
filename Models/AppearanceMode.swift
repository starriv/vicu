import SwiftUI

enum AppearanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case dark
    case light

    static let storageKey = "settings.appearanceMode"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system:
            L10n.Settings.themeSystem
        case .dark:
            L10n.Settings.themeDark
        case .light:
            L10n.Settings.themeLight
        }
    }

    func titleText(locale: Locale) -> String {
        switch self {
        case .system:
            L10n.Settings.themeSystemText(locale: locale)
        case .dark:
            L10n.Settings.themeDarkText(locale: locale)
        case .light:
            L10n.Settings.themeLightText(locale: locale)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .dark:
            .dark
        case .light:
            .light
        }
    }
}
