import SwiftUI

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    static let storageKey = "settings.appLanguage"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system:
            L10n.Settings.languageSystem
        case .english:
            L10n.Settings.languageEnglish
        case .simplifiedChinese:
            L10n.Settings.languageSimplifiedChinese
        }
    }

    func titleText(locale: Locale) -> String {
        switch self {
        case .system:
            L10n.Settings.languageSystemText(locale: locale)
        case .english:
            L10n.Settings.languageEnglishText(locale: locale)
        case .simplifiedChinese:
            L10n.Settings.languageSimplifiedChineseText(locale: locale)
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            AppLocale.system
        case .english:
            Locale(identifier: "en")
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        }
    }
}
