import Foundation
import SwiftUI

enum TradeEnvironment: String, CaseIterable, Codable, Identifiable, Sendable {
    case paper
    case live

    static let storageKey = "tradeEnvironment"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .paper:
            L10n.Environment.paper
        case .live:
            L10n.Environment.live
        }
    }

    func titleText(locale: Locale) -> String {
        switch self {
        case .paper:
            L10n.Environment.paperText(locale: locale)
        case .live:
            L10n.Environment.liveText(locale: locale)
        }
    }

    var baseURL: URL {
        switch self {
        case .paper:
            APIPaths.AlpacaTrading.paperBaseURL
        case .live:
            APIPaths.AlpacaTrading.liveBaseURL
        }
    }

    var accountEndpoint: String {
        baseURL.appendingPathComponent(APIPaths.AlpacaTrading.account).absoluteString
    }
}
