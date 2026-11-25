import Foundation

struct AlpacaPosition: Codable, Hashable, Identifiable, Sendable {
    let assetID: String?
    let symbol: String
    let exchange: String?
    let assetClass: String?
    let assetMarginable: Bool?
    let quantity: String?
    let quantityAvailable: String?
    let averageEntryPrice: String?
    let side: String?
    let marketValue: String?
    let costBasis: String?
    let unrealizedPL: String?
    let unrealizedPLPC: String?
    let unrealizedIntradayPL: String?
    let unrealizedIntradayPLPC: String?
    let currentPrice: String?
    let lastDayPrice: String?
    let changeToday: String?

    var id: String { assetID ?? symbol }
    var assetCategory: PositionAssetCategory {
        PositionAssetCategory(position: self)
    }

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case symbol
        case exchange
        case assetClass = "asset_class"
        case assetMarginable = "asset_marginable"
        case quantity = "qty"
        case quantityAvailable = "qty_available"
        case averageEntryPrice = "avg_entry_price"
        case side
        case marketValue = "market_value"
        case costBasis = "cost_basis"
        case unrealizedPL = "unrealized_pl"
        case unrealizedPLPC = "unrealized_plpc"
        case unrealizedIntradayPL = "unrealized_intraday_pl"
        case unrealizedIntradayPLPC = "unrealized_intraday_plpc"
        case currentPrice = "current_price"
        case lastDayPrice = "lastday_price"
        case changeToday = "change_today"
    }
}

enum PositionAssetCategory: String, CaseIterable, Identifiable, Sendable {
    case stock
    case etf
    case option
    case crypto

    var id: String { rawValue }

    var title: String {
        title(locale: AppLocale.current)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .stock:
            L10n.PositionCategory.title(self, locale: locale)
        case .etf:
            L10n.PositionCategory.title(self, locale: locale)
        case .option:
            L10n.PositionCategory.title(self, locale: locale)
        case .crypto:
            L10n.PositionCategory.title(self, locale: locale)
        }
    }

    var systemImage: String {
        switch self {
        case .stock:
            AppIcon.Position.stock
        case .etf:
            AppIcon.Position.etf
        case .option:
            AppIcon.Position.option
        case .crypto:
            AppIcon.Position.crypto
        }
    }

    var emptyTitle: String {
        emptyTitle(locale: AppLocale.current)
    }

    func emptyTitle(locale: Locale) -> String {
        switch self {
        case .stock:
            L10n.PositionCategory.emptyTitle(self, locale: locale)
        case .etf:
            L10n.PositionCategory.emptyTitle(self, locale: locale)
        case .option:
            L10n.PositionCategory.emptyTitle(self, locale: locale)
        case .crypto:
            L10n.PositionCategory.emptyTitle(self, locale: locale)
        }
    }

    fileprivate init(position: AlpacaPosition) {
        let normalizedAssetClass = position.assetClass?.lowercased() ?? ""
        let normalizedSymbol = position.symbol.uppercased().replacingOccurrences(of: " ", with: "")

        if normalizedAssetClass.contains("crypto") || normalizedSymbol.contains("/") {
            self = .crypto
            return
        }

        if normalizedAssetClass.contains("option") || Self.looksLikeOptionSymbol(normalizedSymbol) {
            self = .option
            return
        }

        if normalizedAssetClass.contains("etf") || Self.knownETFSymbols.contains(normalizedSymbol) {
            self = .etf
            return
        }

        self = .stock
    }

    private static func looksLikeOptionSymbol(_ symbol: String) -> Bool {
        guard symbol.count >= 15 else {
            return false
        }

        let contractSuffix = symbol.suffix(15)
        let date = contractSuffix.prefix(6)
        let type = contractSuffix.dropFirst(6).prefix(1)
        let strike = contractSuffix.suffix(8)

        return date.allSatisfy(\.isNumber)
            && (type == "C" || type == "P")
            && strike.allSatisfy(\.isNumber)
    }

    // Alpaca positions can report ETFs as us_equity, so use a conservative ticker fallback until asset enrichment is added.
    private static let knownETFSymbols: Set<String> = [
        "ARKK", "BIL", "BOXX", "DIA", "EEM", "EFA", "GLD", "HYG", "IAU", "ICLN",
        "IEF", "IJH", "IWM", "IYR", "KWEB", "LQD", "MBB", "QQQ", "SCHD", "SHV",
        "SHY", "SLV", "SMH", "SOXX", "SPY", "TLT", "TQQQ", "UNG", "USO", "VEA",
        "VGT", "VNQ", "VOO", "VTI", "VTV", "VUG", "VXUS", "XBI", "XLE", "XLF",
        "XLK", "XLU", "XLY"
    ]
}
