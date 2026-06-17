import Foundation
import SwiftUI

struct OrderDraft: Equatable, Sendable {
    var symbol = "AAPL"
    var side: OrderSide = .buy
    var orderType: OrderType = .market
    var timeInForce: TimeInForce = .day
    var quantityText = ""
    var notionalText = ""
    var limitPriceText = ""
    var extendedHours = false

    var normalizedSymbol: String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var estimatedNotional: Decimal? {
        NumberParser.decimal(from: notionalText)
    }

    func requestPayload(clientOrderID: String? = nil) throws -> AlpacaOrderRequest {
        let cleanSymbol = normalizedSymbol
        guard !cleanSymbol.isEmpty else {
            throw OrderDraftError.missingSymbol
        }

        let quantity = Self.normalizedSizeText(quantityText)
        let notional = Self.normalizedSizeText(notionalText)
        let limitPrice = orderType.requiresLimitPrice ? NumberText.trimTrailingZeros(limitPriceText) : ""

        guard !quantity.isEmpty || !notional.isEmpty else {
            throw OrderDraftError.missingSize
        }

        if !quantity.isEmpty, !notional.isEmpty {
            throw OrderDraftError.conflictingSize
        }

        if !quantity.isEmpty {
            try Self.requirePositiveDecimal(quantity, error: .invalidQuantity)
            try Self.requireValidStockQuantity(quantity)
        }

        if !notional.isEmpty {
            try Self.requirePositiveDecimal(notional, error: .invalidNotional)
            if timeInForce != .day {
                throw OrderDraftError.notionalRequiresDay
            }
        }

        if orderType.requiresLimitPrice, limitPrice.isEmpty {
            throw OrderDraftError.missingLimitPrice
        }

        if !limitPrice.isEmpty {
            try Self.requirePositiveDecimal(limitPrice, error: .invalidLimitPrice)
            try Self.requireValidPriceIncrement(limitPrice, error: .invalidLimitPriceIncrement)
        }

        if extendedHours, orderType != .limit || !(timeInForce == .day || timeInForce == .gtc) {
            throw OrderDraftError.extendedHoursRequiresLimitDayOrGTC
        }

        return AlpacaOrderRequest(
            symbol: cleanSymbol,
            qty: NumberText.nilIfEmpty(quantity),
            notional: NumberText.nilIfEmpty(notional),
            side: side.rawValue,
            type: orderType.rawValue,
            time_in_force: timeInForce.rawValue,
            limit_price: NumberText.nilIfEmpty(limitPrice),
            stop_price: nil,
            trail_price: nil,
            trail_percent: nil,
            extended_hours: extendedHours ? true : nil,
            client_order_id: NumberText.nilIfEmpty(clientOrderID ?? "")
        )
    }

    private static func requirePositiveDecimal(_ text: String, error: OrderDraftError) throws {
        guard let value = NumberParser.decimal(from: text), value > 0 else {
            throw error
        }
    }

    static func normalizedSizeText(_ text: String) -> String {
        let normalized = NumberText.trimTrailingZeros(text)
        guard let value = NumberParser.decimal(from: normalized), value == 0 else {
            return normalized
        }
        return ""
    }

    private static func requireValidStockQuantity(_ text: String) throws {
        let pattern = #"^(?:0|[1-9]\d*)(?:\.\d{1,6})?$"#
        guard text.range(of: pattern, options: .regularExpression) != nil else {
            throw OrderDraftError.invalidQuantityFormat
        }
    }

    private static func requireValidPriceIncrement(_ text: String, error: OrderDraftError) throws {
        guard let value = NumberParser.decimal(from: text) else {
            throw error
        }

        let fractionLength: Int
        if let decimalSeparatorIndex = text.firstIndex(of: ".") {
            fractionLength = text[text.index(after: decimalSeparatorIndex)...].count
        } else {
            fractionLength = 0
        }

        if value >= 1, fractionLength > 2 {
            throw error
        }

        if value < 1, fractionLength > 4 {
            throw error
        }
    }
}

enum OrderSide: String, CaseIterable, Identifiable, Sendable {
    case buy
    case sell

    var id: String { rawValue }

    func titleText(locale: Locale) -> String {
        switch self {
        case .buy:
            L10n.Order.sideBuyText(locale: locale)
        case .sell:
            L10n.Order.sideSellText(locale: locale)
        }
    }

    var tradeActionTint: Color {
        switch self {
        case .buy:
            AppTheme.ColorToken.positive
        case .sell:
            AppTheme.ColorToken.negative
        }
    }
}

enum OrderType: String, CaseIterable, Identifiable, Sendable {
    case market
    case limit

    var id: String { rawValue }

    func titleText(locale: Locale) -> String {
        switch self {
        case .market:
            L10n.Order.typeMarketText(locale: locale)
        case .limit:
            L10n.Order.typeLimitText(locale: locale)
        }
    }

    var requiresLimitPrice: Bool {
        self == .limit
    }
}

enum TimeInForce: String, CaseIterable, Identifiable, Sendable {
    case day
    case gtc
    case opg
    case cls
    case ioc
    case fok

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum OrderDraftError: LocalizedError {
    case missingSymbol
    case missingSize
    case conflictingSize
    case invalidQuantity
    case invalidQuantityFormat
    case invalidNotional
    case missingLimitPrice
    case invalidLimitPrice
    case invalidLimitPriceIncrement
    case notionalRequiresDay
    case extendedHoursRequiresLimitDayOrGTC

    var errorDescription: String? {
        errorDescription(locale: AppLocale.current)
    }

    func errorDescription(locale: Locale) -> String {
        switch self {
        case .missingSymbol:
            L10n.Order.missingSymbol(locale: locale)
        case .missingSize:
            L10n.Order.missingSize(locale: locale)
        case .conflictingSize:
            L10n.Order.conflictingSize(locale: locale)
        case .invalidQuantity:
            L10n.Order.invalidQuantity(locale: locale)
        case .invalidQuantityFormat:
            L10n.Order.invalidQuantityFormat(locale: locale)
        case .invalidNotional:
            L10n.Order.invalidNotional(locale: locale)
        case .missingLimitPrice:
            L10n.Order.missingLimitPrice(locale: locale)
        case .invalidLimitPrice:
            L10n.Order.invalidLimitPrice(locale: locale)
        case .invalidLimitPriceIncrement:
            L10n.Order.invalidLimitPriceIncrement(locale: locale)
        case .notionalRequiresDay:
            L10n.Order.notionalRequiresDay(locale: locale)
        case .extendedHoursRequiresLimitDayOrGTC:
            L10n.Order.extendedHoursRequiresLimitDayOrGTC(locale: locale)
        }
    }
}
