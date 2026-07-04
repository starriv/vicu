import Foundation

struct AlpacaOrder: Codable, Identifiable, Sendable {
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
    let position_intent: String?
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
    static func navigationPlaceholder(id: String, symbol: String?) -> AlpacaOrder {
        let normalizedSymbol = symbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let displaySymbol: String
        if let normalizedSymbol, !normalizedSymbol.isEmpty {
            displaySymbol = normalizedSymbol
        } else {
            displaySymbol = "--"
        }
        return AlpacaOrder(
            id: id,
            clientOrderID: nil,
            createdAt: nil,
            updatedAt: nil,
            submittedAt: nil,
            filledAt: nil,
            expiredAt: nil,
            canceledAt: nil,
            failedAt: nil,
            replacedAt: nil,
            replacedBy: nil,
            replaces: nil,
            assetID: nil,
            symbol: displaySymbol,
            assetClass: nil,
            quantity: nil,
            filledQuantity: nil,
            filledAveragePrice: nil,
            notional: nil,
            orderClass: nil,
            orderType: nil,
            side: nil,
            type: nil,
            positionIntent: nil,
            timeInForce: nil,
            limitPrice: nil,
            stopPrice: nil,
            status: nil,
            extendedHours: nil,
            legs: nil,
            trailPercent: nil,
            trailPrice: nil,
            highWaterMark: nil,
            subtag: nil,
            source: nil,
            expiresAt: nil
        )
    }

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
