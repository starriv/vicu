import Foundation
import SwiftUI

struct AlpacaAccount: Decodable, Sendable {
    let id: String
    let accountNumber: String?
    let createdAt: String?
    let status: String?
    let currency: String?
    let buyingPower: String?
    let regtBuyingPower: String?
    let daytradingBuyingPower: String?
    let effectiveBuyingPower: String?
    let nonMarginableBuyingPower: String?
    let optionsBuyingPower: String?
    let bodDtbp: String?
    let cash: String?
    let accruedFees: String?
    let portfolioValue: String?
    let patternDayTrader: Bool?
    let tradingBlocked: Bool?
    let transfersBlocked: Bool?
    let accountBlocked: Bool?
    let tradeSuspendedByUser: Bool?
    let multiplier: String?
    let shortingEnabled: Bool?
    let equity: String?
    let lastEquity: String?
    let longMarketValue: String?
    let shortMarketValue: String?
    let positionMarketValue: String?
    let initialMargin: String?
    let maintenanceMargin: String?
    let lastMaintenanceMargin: String?
    let sma: String?
    let daytradeCount: Int?
    let balanceAsOf: String?
    let cryptoStatus: String?
    let optionsApprovedLevel: Int?
    let optionsTradingLevel: Int?
    let cryptoTier: Int?
    let intradayAdjustments: String?
    let pendingRegTAFFees: String?

    enum CodingKeys: String, CodingKey {
        case id
        case accountNumber = "account_number"
        case createdAt = "created_at"
        case status
        case currency
        case buyingPower = "buying_power"
        case regtBuyingPower = "regt_buying_power"
        case daytradingBuyingPower = "daytrading_buying_power"
        case effectiveBuyingPower = "effective_buying_power"
        case nonMarginableBuyingPower = "non_marginable_buying_power"
        case optionsBuyingPower = "options_buying_power"
        case bodDtbp = "bod_dtbp"
        case cash
        case accruedFees = "accrued_fees"
        case portfolioValue = "portfolio_value"
        case patternDayTrader = "pattern_day_trader"
        case tradingBlocked = "trading_blocked"
        case transfersBlocked = "transfers_blocked"
        case accountBlocked = "account_blocked"
        case tradeSuspendedByUser = "trade_suspended_by_user"
        case multiplier
        case shortingEnabled = "shorting_enabled"
        case equity
        case lastEquity = "last_equity"
        case longMarketValue = "long_market_value"
        case shortMarketValue = "short_market_value"
        case positionMarketValue = "position_market_value"
        case initialMargin = "initial_margin"
        case maintenanceMargin = "maintenance_margin"
        case lastMaintenanceMargin = "last_maintenance_margin"
        case sma
        case daytradeCount = "daytrade_count"
        case balanceAsOf = "balance_asof"
        case cryptoStatus = "crypto_status"
        case optionsApprovedLevel = "options_approved_level"
        case optionsTradingLevel = "options_trading_level"
        case cryptoTier = "crypto_tier"
        case intradayAdjustments = "intraday_adjustments"
        case pendingRegTAFFees = "pending_reg_taf_fees"
    }
}

struct AlpacaAccountActivitiesPage: Sendable {
    let activities: [AlpacaAccountActivity]
    let nextPageToken: String?
}

struct AlpacaAccountActivity: Decodable, Identifiable, Sendable {
    let activityType: String
    let id: String
    let cumulativeQuantity: String?
    let leavesQuantity: String?
    let price: String?
    let quantity: String?
    let side: String?
    let symbol: String?
    let transactionTime: String?
    let orderID: String?
    let type: String?
    let date: String?
    let netAmount: String?
    let cusip: String?
    let perShareAmount: String?
    let description: String?

    var occurredAt: Date? {
        AlpacaDateParser.date(transactionTime) ?? AlpacaDateParser.date(date)
    }

    enum CodingKeys: String, CodingKey {
        case activityType = "activity_type"
        case id
        case cumulativeQuantity = "cum_qty"
        case leavesQuantity = "leaves_qty"
        case price
        case quantity = "qty"
        case side
        case symbol
        case transactionTime = "transaction_time"
        case orderID = "order_id"
        case type
        case date
        case netAmount = "net_amount"
        case cusip
        case perShareAmount = "per_share_amount"
        case description
    }
}

struct AlpacaPosition: Decodable, Identifiable, Sendable {
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
        title(locale: .current)
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
        emptyTitle(locale: .current)
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

struct AlpacaOrder: Decodable, Identifiable, Sendable {
    let id: String
    let clientOrderID: String?
    let createdAt: String?
    let updatedAt: String?
    let submittedAt: String?
    let filledAt: String?
    let expiredAt: String?
    let canceledAt: String?
    let failedAt: String?
    let replacedAt: String?
    let replacedBy: String?
    let replaces: String?
    let assetID: String?
    let symbol: String
    let assetClass: String?
    let quantity: String?
    let filledQuantity: String?
    let filledAveragePrice: String?
    let notional: String?
    let orderClass: String?
    let orderType: String?
    let side: String?
    let type: String?
    let positionIntent: String?
    let timeInForce: String?
    let limitPrice: String?
    let stopPrice: String?
    let status: String?
    let extendedHours: Bool?
    let legs: [AlpacaOrder]?
    let trailPercent: String?
    let trailPrice: String?
    let highWaterMark: String?
    let subtag: String?
    let source: String?
    let expiresAt: String?

    var summary: String {
        "\(side?.uppercased() ?? "ORDER") \(quantity ?? notional ?? "--") \(symbol) \(status ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case clientOrderID = "client_order_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case submittedAt = "submitted_at"
        case filledAt = "filled_at"
        case expiredAt = "expired_at"
        case canceledAt = "canceled_at"
        case failedAt = "failed_at"
        case replacedAt = "replaced_at"
        case replacedBy = "replaced_by"
        case replaces
        case assetID = "asset_id"
        case symbol
        case assetClass = "asset_class"
        case quantity = "qty"
        case filledQuantity = "filled_qty"
        case filledAveragePrice = "filled_avg_price"
        case notional
        case orderClass = "order_class"
        case orderType = "order_type"
        case side
        case type
        case positionIntent = "position_intent"
        case timeInForce = "time_in_force"
        case limitPrice = "limit_price"
        case stopPrice = "stop_price"
        case status
        case extendedHours = "extended_hours"
        case legs
        case trailPercent = "trail_percent"
        case trailPrice = "trail_price"
        case highWaterMark = "hwm"
        case subtag
        case source
        case expiresAt = "expires_at"
    }
}

struct AlpacaOrderRequest: Encodable, Sendable {
    let symbol: String
    let qty: String?
    let notional: String?
    let side: String
    let type: String
    let time_in_force: String
    let limit_price: String?
    let stop_price: String?
    let trail_price: String?
    let trail_percent: String?
    let extended_hours: Bool?
    let client_order_id: String?
}

struct AlpacaReplaceOrderRequest: Encodable, Sendable {
    let qty: String?
    let notional: String?
    let time_in_force: String?
    let limit_price: String?
    let stop_price: String?
    let trail: String?
    let client_order_id: String?

    static func priceUpdate(_ value: String, field: AlpacaOrderPriceField) -> AlpacaReplaceOrderRequest {
        switch field {
        case .limitPrice:
            AlpacaReplaceOrderRequest(
                qty: nil,
                notional: nil,
                time_in_force: nil,
                limit_price: value,
                stop_price: nil,
                trail: nil,
                client_order_id: nil
            )
        case .stopPrice:
            AlpacaReplaceOrderRequest(
                qty: nil,
                notional: nil,
                time_in_force: nil,
                limit_price: nil,
                stop_price: value,
                trail: nil,
                client_order_id: nil
            )
        case .trail:
            AlpacaReplaceOrderRequest(
                qty: nil,
                notional: nil,
                time_in_force: nil,
                limit_price: nil,
                stop_price: nil,
                trail: value,
                client_order_id: nil
            )
        }
    }
}

enum AlpacaOrderPriceField: String, Identifiable, Sendable {
    case limitPrice
    case stopPrice
    case trail

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .limitPrice:
            L10n.string("orders.detail.limit_price", locale: locale)
        case .stopPrice:
            L10n.string("orders.detail.stop_price", locale: locale)
        case .trail:
            L10n.string("orders.detail.trail_price", locale: locale)
        }
    }

    func currentValue(in order: AlpacaOrder) -> String? {
        switch self {
        case .limitPrice:
            order.limitPrice
        case .stopPrice:
            order.stopPrice
        case .trail:
            order.trailPrice ?? order.trailPercent
        }
    }
}

extension AlpacaOrder {
    var supportsCancellation: Bool {
        guard let status = normalizedStatus else {
            return false
        }

        return [
            "accepted",
            "accepted_for_bidding",
            "new",
            "pending_new",
            "partially_filled",
            "held",
            "stopped",
            "suspended",
            "calculated"
        ].contains(status)
    }

    var supportsPriceReplacement: Bool {
        guard editablePriceField != nil,
              let status = normalizedStatus,
              !isNotionalOrder else {
            return false
        }

        let blockedStatuses: Set<String> = [
            "accepted",
            "pending_new",
            "pending_cancel",
            "pending_replace",
            "filled",
            "canceled",
            "expired",
            "rejected",
            "failed"
        ]
        return !blockedStatuses.contains(status)
    }

    var editablePriceField: AlpacaOrderPriceField? {
        switch normalizedType {
        case "limit":
            .limitPrice
        case "stop":
            .stopPrice
        case "stop_limit":
            limitPrice == nil && stopPrice != nil ? .stopPrice : .limitPrice
        case "trailing_stop":
            .trail
        default:
            nil
        }
    }

    private var normalizedType: String {
        (type ?? orderType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedStatus: String? {
        let value = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return value.isEmpty ? nil : value
    }

    private var isNotionalOrder: Bool {
        guard let notional else {
            return false
        }

        return !notional.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AlpacaAsset: Decodable, Identifiable, Sendable {
    let id: String
    let assetClass: String?
    let exchange: String?
    let symbol: String
    let name: String?
    let status: String?
    let tradable: Bool?
    let marginable: Bool?
    let maintenanceMarginRequirement: Double?
    let marginRequirementLong: String?
    let marginRequirementShort: String?
    let shortable: Bool?
    let easyToBorrow: Bool?
    let borrowStatus: String?
    let fractionable: Bool?
    let attributes: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case assetClass = "class"
        case exchange
        case symbol
        case name
        case status
        case tradable
        case marginable
        case maintenanceMarginRequirement = "maintenance_margin_requirement"
        case marginRequirementLong = "margin_requirement_long"
        case marginRequirementShort = "margin_requirement_short"
        case shortable
        case easyToBorrow = "easy_to_borrow"
        case borrowStatus = "borrow_status"
        case fractionable
        case attributes
    }
}

struct AlpacaWatchlist: Decodable, Identifiable, Sendable {
    let id: String
    let accountID: String?
    let name: String
    let assets: [AlpacaAsset]?
    let createdAt: String?
    let updatedAt: String?

    var symbols: [String] {
        (assets ?? []).map { $0.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case name
        case assets
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AlpacaWatchlistRequest: Encodable, Sendable {
    let name: String
    let symbols: [String]?
}

struct AlpacaWatchlistAssetRequest: Encodable, Sendable {
    let symbol: String
}

struct MarketOverview: Sendable {
    let clock: AlpacaMarketClock
    let calendar: [AlpacaCalendarDay]
    let overnightCalendar: [AlpacaCalendarDay]
    let indexQuotes: [MarketIndexQuote]
    let gainers: [MarketMover]
    let losers: [MarketMover]
    let mostActive: [MarketActiveSymbol]

    var isEmpty: Bool {
        indexQuotes.isEmpty && gainers.isEmpty && losers.isEmpty && mostActive.isEmpty
    }

    func nextCoreOpen() -> String? {
        nextCalendarValue(\.coreStart)
    }

    func nextCoreClose() -> String? {
        nextCalendarValue(\.coreEnd)
    }

    private func nextCalendarValue(_ keyPath: KeyPath<AlpacaCalendarDay, String>) -> String? {
        let referenceDate = AlpacaDateParser.date(clock.timestamp) ?? Date()
        return calendar
            .compactMap { day -> (value: String, date: Date)? in
                let value = day[keyPath: keyPath]
                guard let date = AlpacaDateParser.date(value), date > referenceDate else {
                    return nil
                }

                return (value, date)
            }
            .min { $0.date < $1.date }?
            .value
    }
}

struct AlpacaMarketCalendarResponse: Decodable, Sendable {
    let calendar: [AlpacaCalendarDay]
}

struct AlpacaCalendarDay: Decodable, Identifiable, Sendable {
    let date: String
    let coreStart: String
    let coreEnd: String
    let preStart: String?
    let preEnd: String?
    let postStart: String?
    let postEnd: String?
    let settlementDate: String?

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date
        case coreStart = "core_start"
        case coreEnd = "core_end"
        case preStart = "pre_start"
        case preEnd = "pre_end"
        case postStart = "post_start"
        case postEnd = "post_end"
        case settlementDate = "settlement_date"
    }
}

enum MarketSessionKind: String, Sendable {
    case overnight
    case preMarket
    case regular
    case afterHours

    var activePriority: Int {
        switch self {
        case .regular:
            0
        case .preMarket:
            1
        case .afterHours:
            2
        case .overnight:
            3
        }
    }
}

struct MarketSessionInterval: Identifiable, Sendable {
    let session: MarketSessionKind
    let start: Date
    let end: Date
    let marketDate: String

    var id: String {
        "\(marketDate)-\(session.rawValue)"
    }

    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

struct MarketSessionProgress: Sendable {
    let intervals: [MarketSessionInterval]
    let referenceDate: Date

    var cycleStart: Date? {
        intervals.first?.start
    }

    var cycleEnd: Date? {
        intervals.last?.end
    }
}

enum MarketSessionSchedule {
    static func intervals(
        from days: [AlpacaCalendarDay],
        overnightDays: [AlpacaCalendarDay] = []
    ) -> [MarketSessionInterval] {
        days.flatMap { intervals(for: $0, overnightDays: overnightDays) }
            .filter { $0.start < $0.end }
            .sorted { $0.start < $1.start }
    }

    static func activeInterval(
        at date: Date,
        in days: [AlpacaCalendarDay],
        overnightDays: [AlpacaCalendarDay] = []
    ) -> MarketSessionInterval? {
        intervals(from: days, overnightDays: overnightDays)
            .filter { $0.contains(date) }
            .min { lhs, rhs in
                if lhs.session.activePriority == rhs.session.activePriority {
                    return lhs.start < rhs.start
                }

                return lhs.session.activePriority < rhs.session.activePriority
            }
    }

    static func latestRegularInterval(
        before date: Date,
        in days: [AlpacaCalendarDay],
        overnightDays: [AlpacaCalendarDay] = []
    ) -> MarketSessionInterval? {
        intervals(from: days, overnightDays: overnightDays)
            .filter { $0.session == .regular && $0.start <= date }
            .map { interval in
                MarketSessionInterval(
                    session: interval.session,
                    start: interval.start,
                    end: min(date, interval.end),
                    marketDate: interval.marketDate
                )
            }
            .filter { $0.start < $0.end }
            .sorted { $0.start < $1.start }
            .last
    }

    static func progress(
        for activeInterval: MarketSessionInterval,
        in days: [AlpacaCalendarDay],
        overnightDays: [AlpacaCalendarDay] = [],
        at date: Date
    ) -> MarketSessionProgress {
        let cycleIntervals = intervals(from: days, overnightDays: overnightDays)
            .filter { $0.marketDate == activeInterval.marketDate }
        return MarketSessionProgress(intervals: cycleIntervals, referenceDate: date)
    }

    private static func intervals(
        for day: AlpacaCalendarDay,
        overnightDays: [AlpacaCalendarDay]
    ) -> [MarketSessionInterval] {
        var intervals: [MarketSessionInterval] = []

        if let overnightInterval = overnightInterval(for: day, overnightDays: overnightDays) {
            intervals.append(overnightInterval)
        }

        if let preStart = AlpacaDateParser.date(day.preStart),
           let preEnd = AlpacaDateParser.date(day.preEnd) ?? AlpacaDateParser.date(day.coreStart) {
            intervals.append(
                MarketSessionInterval(
                    session: .preMarket,
                    start: preStart,
                    end: preEnd,
                    marketDate: day.date
                )
            )
        }

        if let coreStart = AlpacaDateParser.date(day.coreStart),
           let coreEnd = AlpacaDateParser.date(day.coreEnd) {
            intervals.append(
                MarketSessionInterval(
                    session: .regular,
                    start: coreStart,
                    end: coreEnd,
                    marketDate: day.date
                )
            )
        }

        if let postStart = AlpacaDateParser.date(day.postStart) ?? AlpacaDateParser.date(day.coreEnd),
           let postEnd = AlpacaDateParser.date(day.postEnd) {
            intervals.append(
                MarketSessionInterval(
                    session: .afterHours,
                    start: postStart,
                    end: postEnd,
                    marketDate: day.date
                )
            )
        }

        return intervals
    }

    private static func overnightInterval(
        for day: AlpacaCalendarDay,
        overnightDays: [AlpacaCalendarDay]
    ) -> MarketSessionInterval? {
        if let actualInterval = actualOvernightInterval(for: day, overnightDays: overnightDays) {
            return actualInterval
        }

        guard let overnightStart = overnightStart(forMarketDate: day.date),
              let overnightEnd = AlpacaDateParser.date(day.preStart) else {
            return nil
        }

        return MarketSessionInterval(
            session: .overnight,
            start: overnightStart,
            end: overnightEnd,
            marketDate: day.date
        )
    }

    private static func actualOvernightInterval(
        for day: AlpacaCalendarDay,
        overnightDays: [AlpacaCalendarDay]
    ) -> MarketSessionInterval? {
        guard let expectedStart = overnightStart(forMarketDate: day.date),
              let expectedEnd = AlpacaDateParser.date(day.preStart) ?? AlpacaDateParser.date(day.coreStart) else {
            return nil
        }

        let lowerBound = expectedStart.addingTimeInterval(-60 * 60)
        let upperBound = expectedEnd.addingTimeInterval(60 * 60)
        let candidate = overnightDays
            .compactMap { overnightDay -> (start: Date, end: Date)? in
                guard let start = AlpacaDateParser.date(overnightDay.coreStart),
                      let end = AlpacaDateParser.date(overnightDay.coreEnd),
                      start < end else {
                    return nil
                }

                return (start, end)
            }
            .filter { interval in
                interval.start >= lowerBound
                    && interval.end <= upperBound
                    && interval.end <= expectedEnd.addingTimeInterval(60 * 5)
            }
            .max { lhs, rhs in
                lhs.end < rhs.end
            }

        guard let candidate else {
            return nil
        }

        return MarketSessionInterval(
            session: .overnight,
            start: candidate.start,
            end: candidate.end,
            marketDate: day.date
        )
    }

    private static func overnightStart(forMarketDate dateText: String) -> Date? {
        let parts = dateText.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        guard let marketDate = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2]
            )
        ),
              let previousDate = calendar.date(byAdding: .day, value: -1, to: marketDate) else {
            return nil
        }

        let previousComponents = calendar.dateComponents([.year, .month, .day], from: previousDate)
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: previousComponents.year,
                month: previousComponents.month,
                day: previousComponents.day,
                hour: 20,
                minute: 0,
                second: 0
            )
        )
    }
}

struct AlpacaMarketClockResponse: Decodable, Sendable {
    private let clocks: [AlpacaMarketClockPayload]

    enum CodingKeys: String, CodingKey {
        case clocks
    }

    func clock(market: String) throws -> AlpacaMarketClock {
        guard let marketClock = clocks.first(where: { $0.market.acronym == market }) else {
            throw APIClientError.decodingFailed(
                type: String(describing: Self.self),
                message: "Missing \(market) clock in v3 clock response."
            )
        }

        return marketClock.clock()
    }
}

private struct AlpacaMarketClockPayload: Decodable, Sendable {
    let isMarketDay: Bool
    let market: AlpacaClockMarket
    let timestamp: String?
    let nextOpen: String?
    let nextClose: String?
    let phase: String?
    let phaseUntil: String?

    enum CodingKeys: String, CodingKey {
        case isMarketDay = "is_market_day"
        case market
        case timestamp
        case nextOpen = "next_market_open"
        case nextClose = "next_market_close"
        case phase
        case phaseUntil = "phase_until"
    }

    func clock() -> AlpacaMarketClock {
        AlpacaMarketClock(
            timestamp: timestamp,
            isOpen: phase == "open",
            nextOpen: nextOpen,
            nextClose: nextClose,
            phase: phase,
            phaseUntil: phaseUntil
        )
    }
}

private struct AlpacaClockMarket: Decodable, Sendable {
    let acronym: String
    let mic: String?
    let name: String?
    let timezone: String?
}

struct AlpacaMarketClock: Sendable {
    let timestamp: String?
    let isOpen: Bool
    let nextOpen: String?
    let nextClose: String?
    let phase: String?
    let phaseUntil: String?
}

enum AlpacaDateParser {
    static func date(_ text: String?) -> Date? {
        guard let text else {
            return nil
        }

        return parser.date(from: text)
    }

    private static let parser = LockedAlpacaDateParser()
}

private final class LockedAlpacaDateParser: @unchecked Sendable {
    private let lock = NSLock()
    private let fractionalSecondsFormatter = makeFormatter(fractionalSeconds: true)
    private let standardFormatter = makeFormatter(fractionalSeconds: false)
    private let dateOnlyFormatter = makeDateOnlyFormatter()

    func date(from text: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        return fractionalSecondsFormatter.date(from: text)
            ?? standardFormatter.date(from: text)
            ?? dateOnlyFormatter.date(from: text)
    }

    private static func makeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withColonSeparatorInTimeZone
        ]
        if fractionalSeconds {
            formatter.formatOptions.insert(.withFractionalSeconds)
        }
        return formatter
    }

    private static func makeDateOnlyFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }
}

struct MarketIndexQuote: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let price: Double?
    let change: Double?
    let percentChange: Double?

    var isPositive: Bool {
        (change ?? 0) >= 0
    }

    func updating(price latestPrice: Double) -> MarketIndexQuote {
        let previousClose = inferredPreviousClose
        let latestChange = previousClose.map { latestPrice - $0 }
        let latestPercentChange = previousClose.flatMap { close -> Double? in
            close == 0 ? nil : (latestPrice - close) / close
        }

        return MarketIndexQuote(
            id: id,
            title: title,
            symbol: symbol,
            price: latestPrice,
            change: latestChange,
            percentChange: latestPercentChange
        )
    }

    private var inferredPreviousClose: Double? {
        if let price, let change {
            return price - change
        }

        if let price, let percentChange, percentChange != -1 {
            return price / (1 + percentChange)
        }

        return nil
    }
}

struct MarketMover: Decodable, Identifiable, Sendable {
    let symbol: String
    let price: Double?
    let change: Double?
    let percentChange: Double?

    var id: String { symbol }
    var isPositive: Bool {
        (change ?? 0) >= 0
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case price
        case change
        case percentChange = "percent_change"
    }
}

struct MarketActiveSymbol: Decodable, Identifiable, Sendable {
    let symbol: String
    let companyName: String?
    let price: Double?
    let change: Double?
    let percentChange: Double?
    let volume: Double?
    let tradeCount: Double?

    var id: String { symbol }
    var isPositive: Bool {
        (change ?? 0) >= 0
    }

    init(
        symbol: String,
        companyName: String? = nil,
        price: Double?,
        change: Double?,
        percentChange: Double?,
        volume: Double?,
        tradeCount: Double?
    ) {
        self.symbol = symbol
        self.companyName = companyName
        self.price = price
        self.change = change
        self.percentChange = percentChange
        self.volume = volume
        self.tradeCount = tradeCount
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case companyName = "company_name"
        case price
        case change
        case percentChange = "percent_change"
        case volume
        case tradeCount = "trade_count"
    }
}

struct MarketSearchResult: Identifiable, Sendable {
    let asset: AlpacaAsset
    let quote: MarketActiveSymbol?

    var id: String { asset.symbol }
    var symbol: String { asset.symbol }
    var companyName: String { asset.name ?? AppFormatter.placeholder }
    var exchange: String { asset.exchange ?? AppFormatter.placeholder }
    var price: Double? { quote?.price }
    var percentChange: Double? { quote?.percentChange }
    var isPositive: Bool { quote?.isPositive ?? true }
}

enum MarketMostActiveSort: String, CaseIterable, Identifiable, Sendable {
    case volume
    case trades

    static var displayCases: [MarketMostActiveSort] {
        [.trades, .volume]
    }

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .volume:
            L10n.Markets.sortVolume
        case .trades:
            L10n.Markets.sortTrades
        }
    }

    var searchPopularSubtitle: LocalizedStringKey {
        switch self {
        case .volume:
            L10n.Markets.searchPopularVolumeSubtitle
        case .trades:
            L10n.Markets.searchPopularTradesSubtitle
        }
    }

    var icon: String {
        switch self {
        case .volume:
            "chart.bar.fill"
        case .trades:
            "flame"
        }
    }
}

enum AlpacaMarketDataFeed: String, CaseIterable, Identifiable, Sendable {
    case iex
    case sip
    case delayedSIP = "delayed_sip"
    case boats
    case overnight

    var id: String { rawValue }

    var streamPath: String {
        switch self {
        case .iex, .sip, .delayedSIP:
            "v2/\(rawValue)"
        case .boats, .overnight:
            "v1beta1/\(rawValue)"
        }
    }
}

enum AssetChartRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case oneDay
    case oneWeek
    case oneMonth
    case threeMonths
    case oneYear
    case yearToDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay:
            "1D"
        case .oneWeek:
            "1W"
        case .oneMonth:
            "1M"
        case .threeMonths:
            "3M"
        case .oneYear:
            "1Y"
        case .yearToDate:
            "YTD"
        }
    }

    var timeframe: String {
        switch self {
        case .oneDay:
            "5Min"
        case .oneWeek:
            "15Min"
        case .oneMonth, .threeMonths, .yearToDate:
            "1Day"
        case .oneYear:
            "1Week"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .oneDay, .oneWeek:
            .day
        case .oneMonth, .threeMonths:
            .month
        case .oneYear, .yearToDate:
            .year
        }
    }

    var calendarValue: Int {
        switch self {
        case .oneDay:
            -1
        case .oneWeek:
            -7
        case .oneMonth:
            -1
        case .threeMonths:
            -3
        case .oneYear, .yearToDate:
            -1
        }
    }

    var requestLimit: Int {
        switch self {
        case .oneDay:
            10000
        case .oneWeek:
            900
        case .oneMonth:
            160
        case .threeMonths:
            260
        case .oneYear, .yearToDate:
            260
        }
    }

    func startDate(now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        if self == .yearToDate {
            let year = calendar.component(.year, from: now)
            return calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        }

        return calendar.date(byAdding: calendarComponent, value: calendarValue, to: now) ?? now
    }
}

struct AssetDetailSnapshot: Sendable {
    let asset: AlpacaAsset
    let stockSnapshot: AlpacaStockSnapshot?
    let bars: [AlpacaMarketBar]
    let chartBaseline: Double?
    let range: AssetChartRange
    let feed: AlpacaMarketDataFeed
    let sessionProgress: MarketSessionProgress?
    let latestBar: AlpacaMarketBar?
}

struct AlpacaResolvedStockSnapshot: Sendable {
    let snapshot: AlpacaStockSnapshot?
    let feed: AlpacaMarketDataFeed
    let activeSession: MarketSessionKind?
    let latestBar: AlpacaMarketBar?
}

struct AlpacaStockSnapshotsResponse: Decodable, Sendable {
    let snapshots: [String: AlpacaStockSnapshot]

    init(snapshots: [String: AlpacaStockSnapshot]) {
        self.snapshots = snapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.snapshots) {
            snapshots = try container.decode([String: AlpacaStockSnapshot].self, forKey: .snapshots)
        } else {
            snapshots = try [String: AlpacaStockSnapshot](from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case snapshots
    }
}

struct AlpacaLatestStockTradeResponse: Decodable, Sendable {
    let symbol: String?
    let trade: AlpacaStockTrade?
}

struct AlpacaLatestStockQuotesResponse: Decodable, Sendable {
    let quotes: [String: AlpacaStockQuote]
}

struct AlpacaStockQuotesResponse: Decodable, Sendable {
    let quotes: [String: [AlpacaStockQuote]]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case quotes
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaStockQuotesPage: Sendable {
    let quotes: [AlpacaStockQuote]
    let nextPageToken: String?
}

enum AlpacaOptionFeed: String, CaseIterable, Identifiable, Sendable {
    case indicative
    case opra

    var id: String { rawValue }
}

enum AlpacaOptionContractType: String, CaseIterable, Identifiable, Sendable {
    case call
    case put

    var id: String { rawValue }

    var title: String {
        switch self {
        case .call:
            "Calls"
        case .put:
            "Puts"
        }
    }
}

struct AlpacaOptionChainResponse: Decodable, Sendable {
    let snapshots: [String: AlpacaOptionSnapshotPayload]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case snapshots
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaOptionChainPage: Sendable {
    let snapshots: [AlpacaOptionSnapshot]
    let nextPageToken: String?
}

struct AlpacaOptionSnapshotsResponse: Decodable, Sendable {
    let snapshots: [String: AlpacaOptionSnapshotPayload]
    let nextPageToken: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        snapshots = try container.decodeIfPresent([String: AlpacaOptionSnapshotPayload].self, forKey: .snapshots) ?? [:]
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }

    private enum CodingKeys: String, CodingKey {
        case snapshots
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaOptionSnapshotsPage: Sendable {
    let snapshots: [AlpacaOptionSnapshot]
    let nextPageToken: String?
}

struct AlpacaOptionBarsResponse: Decodable, Sendable {
    let bars: [String: [AlpacaMarketBar]]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case bars
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaOptionBarsPage: Sendable {
    let bars: [AlpacaMarketBar]
    let nextPageToken: String?
}

struct AlpacaOptionTradesResponse: Decodable, Sendable {
    let trades: [String: [AlpacaOptionTrade]]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case trades
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaOptionTradesPage: Sendable {
    let trades: [AlpacaOptionTrade]
    let nextPageToken: String?
}

struct AlpacaLatestOptionTradesResponse: Decodable, Sendable {
    let trades: [String: AlpacaOptionTrade]
}

struct AlpacaOptionContractsResponse: Decodable, Sendable {
    let contracts: [AlpacaOptionContract]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case optionContracts = "option_contracts"
        case contracts
        case nextPageToken = "next_page_token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contracts = try container.decodeIfPresent([AlpacaOptionContract].self, forKey: .optionContracts)
            ?? container.decodeIfPresent([AlpacaOptionContract].self, forKey: .contracts)
            ?? []
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

struct AlpacaOptionContractsPage: Sendable {
    let contracts: [AlpacaOptionContract]
    let nextPageToken: String?
}

struct AlpacaOptionContract: Decodable, Identifiable, Sendable {
    let contractID: String?
    let symbol: String
    let name: String?
    let status: String?
    let expirationDate: String?
    let rootSymbol: String?
    let underlyingSymbol: String?
    let type: String?
    let strikePrice: String?

    var id: String { contractID ?? symbol }

    enum CodingKeys: String, CodingKey {
        case contractID = "id"
        case symbol
        case name
        case status
        case expirationDate = "expiration_date"
        case rootSymbol = "root_symbol"
        case underlyingSymbol = "underlying_symbol"
        case type
        case strikePrice = "strike_price"
    }
}

struct AlpacaOptionSnapshot: Identifiable, Equatable, Sendable {
    let contractSymbol: String
    let latestTrade: AlpacaOptionTrade?
    let latestQuote: AlpacaOptionQuote?
    let greeks: AlpacaOptionGreeks?
    let impliedVolatility: Double?

    var id: String { contractSymbol }

    init(contractSymbol: String, payload: AlpacaOptionSnapshotPayload) {
        self.contractSymbol = contractSymbol
        self.latestTrade = payload.latestTrade
        self.latestQuote = payload.latestQuote
        self.greeks = payload.greeks
        self.impliedVolatility = payload.impliedVolatility
    }
}

struct AlpacaOptionSnapshotPayload: Decodable, Equatable, Sendable {
    let latestTrade: AlpacaOptionTrade?
    let latestQuote: AlpacaOptionQuote?
    let greeks: AlpacaOptionGreeks?
    let impliedVolatility: Double?

    enum CodingKeys: String, CodingKey {
        case latestTrade
        case latestQuote
        case greeks
        case impliedVolatility
        case impliedVolatilitySnake = "implied_volatility"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latestTrade = try container.decodeIfPresent(AlpacaOptionTrade.self, forKey: .latestTrade)
        latestQuote = try container.decodeIfPresent(AlpacaOptionQuote.self, forKey: .latestQuote)
        greeks = try container.decodeIfPresent(AlpacaOptionGreeks.self, forKey: .greeks)
        let camelCaseIV = try container.decodeIfPresent(Double.self, forKey: .impliedVolatility)
        let snakeCaseIV = try container.decodeIfPresent(Double.self, forKey: .impliedVolatilitySnake)
        impliedVolatility = camelCaseIV ?? snakeCaseIV
    }
}

struct AlpacaOptionTrade: Decodable, Equatable, Sendable {
    let exchange: String?
    let price: Double?
    let size: Double?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case exchange = "x"
        case price = "p"
        case size = "s"
        case timestamp = "t"
    }
}

struct AlpacaOptionQuote: Decodable, Equatable, Sendable {
    let askExchange: String?
    let askPrice: Double?
    let askSize: Double?
    let bidExchange: String?
    let bidPrice: Double?
    let bidSize: Double?
    let timestamp: String?

    var spread: Double? {
        guard let askPrice, let bidPrice else {
            return nil
        }

        return max(0, askPrice - bidPrice)
    }

    var midpoint: Double? {
        guard let askPrice, let bidPrice else {
            return nil
        }

        return (askPrice + bidPrice) / 2
    }

    enum CodingKeys: String, CodingKey {
        case askExchange = "ax"
        case askPrice = "ap"
        case askSize = "as"
        case bidExchange = "bx"
        case bidPrice = "bp"
        case bidSize = "bs"
        case timestamp = "t"
    }
}

struct AlpacaOptionGreeks: Decodable, Equatable, Sendable {
    let delta: Double?
    let gamma: Double?
    let rho: Double?
    let theta: Double?
    let vega: Double?
}

struct AlpacaNewsResponse: Decodable, Sendable {
    let news: [AlpacaNewsArticle]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case news
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaNewsPage: Sendable {
    let articles: [AlpacaNewsArticle]
    let nextPageToken: String?
}

struct AlpacaNewsArticle: Decodable, Identifiable, Equatable, Sendable {
    let articleID: String?
    let headline: String?
    let summary: String?
    let author: String?
    let createdAt: String?
    let updatedAt: String?
    let url: String?
    let symbols: [String]
    let source: String?

    var id: String {
        articleID ?? [
            headline ?? "",
            updatedAt ?? createdAt ?? "",
            url ?? ""
        ].joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case headline
        case summary
        case author
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case url
        case symbols
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        articleID = Self.decodeStringOrInteger(container, forKey: .id)
        headline = try container.decodeIfPresent(String.self, forKey: .headline)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        symbols = (try? container.decode([String].self, forKey: .symbols)) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    private static func decodeStringOrInteger(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let value = try? container.decode(String.self, forKey: key), !value.isEmpty {
            return value
        }

        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }

        return nil
    }
}

enum AlpacaSortDirection: String, Sendable {
    case asc
    case desc
}

struct AlpacaLatestStockBarsResponse: Decodable, Sendable {
    let bars: [String: AlpacaMarketBar]
}

struct AlpacaStockSnapshot: Decodable, Sendable {
    let latestTrade: AlpacaStockTrade?
    let latestQuote: AlpacaStockQuote?
    let minuteBar: AlpacaMarketBar?
    let dailyBar: AlpacaMarketBar?
    let previousDailyBar: AlpacaMarketBar?

    static let empty = AlpacaStockSnapshot(
        latestTrade: nil,
        latestQuote: nil,
        minuteBar: nil,
        dailyBar: nil,
        previousDailyBar: nil
    )

    init(
        latestTrade: AlpacaStockTrade?,
        latestQuote: AlpacaStockQuote?,
        minuteBar: AlpacaMarketBar?,
        dailyBar: AlpacaMarketBar?,
        previousDailyBar: AlpacaMarketBar?
    ) {
        self.latestTrade = latestTrade
        self.latestQuote = latestQuote
        self.minuteBar = minuteBar
        self.dailyBar = dailyBar
        self.previousDailyBar = previousDailyBar
    }

    func withLatestTrade(_ trade: AlpacaStockTrade?) -> AlpacaStockSnapshot {
        AlpacaStockSnapshot(
            latestTrade: trade ?? latestTrade,
            latestQuote: latestQuote,
            minuteBar: minuteBar,
            dailyBar: dailyBar,
            previousDailyBar: previousDailyBar
        )
    }

    func withLatestQuote(_ quote: AlpacaStockQuote?) -> AlpacaStockSnapshot {
        AlpacaStockSnapshot(
            latestTrade: latestTrade,
            latestQuote: quote ?? latestQuote,
            minuteBar: minuteBar,
            dailyBar: dailyBar,
            previousDailyBar: previousDailyBar
        )
    }

    enum CodingKeys: String, CodingKey {
        case latestTrade
        case latestQuote
        case minuteBar
        case dailyBar
        case previousDailyBar = "prevDailyBar"
    }
}

struct AlpacaStockTrade: Decodable, Sendable {
    let symbol: String?
    let exchange: String?
    let price: Double?
    let size: Double?
    let timestamp: String?
    let conditions: [String]?
    let tape: String?

    enum CodingKeys: String, CodingKey {
        case symbol = "S"
        case exchange = "x"
        case price = "p"
        case size = "s"
        case timestamp = "t"
        case conditions = "c"
        case tape = "z"
    }
}

struct AlpacaStockQuote: Decodable, Sendable {
    let symbol: String?
    let askExchange: String?
    let askPrice: Double?
    let askSize: Double?
    let bidExchange: String?
    let bidPrice: Double?
    let bidSize: Double?
    let conditions: [String]?
    let timestamp: String?
    let tape: String?

    var spread: Double? {
        guard let askPrice, let bidPrice else {
            return nil
        }

        return max(0, askPrice - bidPrice)
    }

    enum CodingKeys: String, CodingKey {
        case symbol = "S"
        case askExchange = "ax"
        case askPrice = "ap"
        case askSize = "as"
        case bidExchange = "bx"
        case bidPrice = "bp"
        case bidSize = "bs"
        case conditions = "c"
        case timestamp = "t"
        case tape = "z"
    }
}

struct AlpacaMarketBar: Decodable, Sendable, Equatable {
    let symbol: String?
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double?
    let volume: Double?
    let vwap: Double?
    let tradeCount: Double?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case symbol = "S"
        case open = "o"
        case high = "h"
        case low = "l"
        case close = "c"
        case volume = "v"
        case vwap = "vw"
        case tradeCount = "n"
        case timestamp = "t"
    }
}

struct AlpacaStockBarsResponse: Decodable, Sendable {
    let bars: [String: [AlpacaMarketBar]]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case bars
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaMarketMoversResponse: Decodable, Sendable {
    let gainers: [MarketMover]
    let losers: [MarketMover]
}

struct AlpacaMostActivesResponse: Decodable, Sendable {
    let mostActives: [MarketActiveSymbol]

    enum CodingKeys: String, CodingKey {
        case mostActives = "most_actives"
    }
}

enum PortfolioHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case oneDay
    case oneWeek
    case oneMonth
    case threeMonths
    case oneYear
    case yearToDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay:
            "1D"
        case .oneWeek:
            "1W"
        case .oneMonth:
            "1M"
        case .threeMonths:
            "3M"
        case .oneYear:
            "1Y"
        case .yearToDate:
            "YTD"
        }
    }

    func queryItems(accountCreatedAt: String?) -> [URLQueryItem] {
        switch self {
        case .oneDay:
            return [
                URLQueryItem(name: "period", value: "1D"),
                URLQueryItem(name: "timeframe", value: "5Min"),
                URLQueryItem(name: "intraday_reporting", value: "continuous")
            ]
        case .oneWeek:
            return [
                URLQueryItem(name: "period", value: "1W"),
                URLQueryItem(name: "timeframe", value: "1H"),
                URLQueryItem(name: "intraday_reporting", value: "continuous"),
                URLQueryItem(name: "pnl_reset", value: "no_reset")
            ]
        case .oneMonth:
            return [
                URLQueryItem(name: "period", value: "1M"),
                URLQueryItem(name: "timeframe", value: "1D")
            ]
        case .threeMonths:
            return [
                URLQueryItem(name: "period", value: "3M"),
                URLQueryItem(name: "timeframe", value: "1D")
            ]
        case .oneYear:
            return [
                URLQueryItem(name: "period", value: "1A"),
                URLQueryItem(name: "timeframe", value: "1D")
            ]
        case .yearToDate:
            return [
                URLQueryItem(name: "start", value: Self.yearToDateStart()),
                URLQueryItem(name: "timeframe", value: "1D")
            ]
        }
    }

    private static func yearToDateStart(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        let year = calendar.component(.year, from: now)
        let start = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: 1,
                day: 1,
                hour: 0,
                minute: 0,
                second: 0
            )
        ) ?? now

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: start)
    }
}

struct AlpacaPortfolioHistory: Decodable, Sendable {
    let timestamp: [Int]?
    let equity: [Double?]?
    let profitLoss: [Double?]?
    let profitLossPct: [Double?]?
    let baseValue: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case equity
        case profitLoss = "profit_loss"
        case profitLossPct = "profit_loss_pct"
        case baseValue = "base_value"
    }

    func points() -> [PortfolioHistoryPoint] {
        guard let timestamp, let equity else { return [] }

        return timestamp.indices.compactMap { index -> PortfolioHistoryPoint? in
            guard index < equity.count, let value = equity[index] else {
                return nil
            }

            return PortfolioHistoryPoint(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp[index])),
                equity: value,
                profitLoss: optionalValue(at: index, in: profitLoss),
                profitLossPercent: optionalValue(at: index, in: profitLossPct)
            )
        }
    }

    private func optionalValue(at index: Int, in values: [Double?]?) -> Double? {
        guard let values, index < values.count else {
            return nil
        }
        return values[index]
    }
}

struct PortfolioHistoryPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let equity: Double
    let profitLoss: Double?
    let profitLossPercent: Double?

    var id: Date { date }
}
