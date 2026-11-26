import Foundation

/// Presentational payload for a single local notification. Produced by
/// `NotificationPresentation`, delivered by `NotificationCoordinator`, and
/// rendered directly by `NotificationPreviewView`.
struct NotificationPayload: Equatable, Sendable {
    let requestIdentifier: String
    let title: String
    let subtitle: String
    let body: String
    let categoryIdentifier: String
    let threadIdentifier: String
    let priority: NotificationPriority
    let userInfo: [String: String]
}

/// Turns domain events into concise, scannable iOS notifications following the
/// same 3-tier hierarchy as Vicu's Live Activities:
/// - `title`: Ticker/kind + crisp status (`AAPL · 已成交`, `股息 · AAPL`)
/// - `subtitle`: Key structured context (`买入 10 股 · 限价单`, `+$12.40`)
/// - `body`: Supporting execution detail (`均价 $230.98`, `6/10 · 均价 $230.98`)
enum NotificationPresentation {
    // MARK: - Order submitted

    static func orderSubmitted(
        order: AlpacaOrder,
        locale: Locale
    ) -> NotificationPayload {
        let symbol = order.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let status = L10n.LiveActivity.orderStatus(.submitted, locale: locale)

        return NotificationPayload(
            requestIdentifier: "vicu-order-submitted-\(order.id)",
            title: joined([symbol, status]),
            subtitle: orderSubtitle(for: order, locale: locale),
            body: orderPriceDetail(for: order, locale: locale),
            categoryIdentifier: NotificationPolicy.Category.orderSubmitted,
            threadIdentifier: NotificationPolicy.orderThreadIdentifier(symbol: symbol),
            priority: .normal,
            userInfo: [
                "order_id": order.id,
                "client_order_id": order.clientOrderID ?? "",
                "symbol": symbol,
                "side": order.side ?? "",
                "order_type": order.type ?? order.orderType ?? "",
                "status": order.status ?? ""
            ]
        )
    }

    // MARK: - Trade event

    static func tradeEvent(
        _ event: AlpacaTradeEvent,
        locale: Locale
    ) -> NotificationPayload {
        let order = event.order
        let symbol = order.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let status = tradeEventStatusTitle(for: event, locale: locale)

        return NotificationPayload(
            requestIdentifier: "vicu-trade-event-\(event.id)",
            title: joined([symbol, status]),
            subtitle: orderSubtitle(for: order, locale: locale),
            body: tradeEventBody(for: event, locale: locale),
            categoryIdentifier: NotificationPolicy.Category.orderStatus,
            threadIdentifier: NotificationPolicy.orderThreadIdentifier(symbol: symbol),
            priority: NotificationPolicy.priority(forTradeEvent: event),
            userInfo: [
                "event_id": event.cursorID ?? "",
                "event": event.event,
                "order_id": order.id,
                "symbol": symbol,
                "side": order.side ?? "",
                "order_type": order.type ?? order.orderType ?? "",
                "status": order.status ?? ""
            ]
        )
    }

    // MARK: - Account activity

    static func accountActivity(
        _ event: AlpacaActivityEvent,
        locale: Locale
    ) -> NotificationPayload {
        let kind = activityKindTitle(for: event, locale: locale)
        let symbol = event.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let nonEmptySymbol = (symbol?.isEmpty == false) ? symbol : nil
        let amount = formattedSignedAmount(for: event)

        let title = joined([kind, nonEmptySymbol])
        let subtitle: String
        let body: String

        if let amount {
            subtitle = amount
            body = accountActivityDetail(for: event, locale: locale)
        } else {
            subtitle = accountActivityDetail(for: event, locale: locale)
            body = ""
        }

        var userInfo: [String: String] = [
            "event_id": event.eventID,
            "ref_id": event.refID,
            "activity_type": event.activityType,
            "account_id": event.accountID
        ]
        if let orderID = event.orderID, !orderID.isEmpty {
            userInfo["order_id"] = orderID
        }
        if let nonEmptySymbol {
            userInfo["symbol"] = nonEmptySymbol
        }

        return NotificationPayload(
            requestIdentifier: "vicu-activity-\(event.eventID)",
            title: title,
            subtitle: subtitle,
            body: body,
            categoryIdentifier: NotificationPolicy.Category.accountActivity,
            threadIdentifier: NotificationPolicy.accountThreadIdentifier,
            priority: NotificationPolicy.priority(forActivityEvent: event),
            userInfo: userInfo
        )
    }

    // MARK: - Formatting helpers

    private static func orderSubtitle(for order: AlpacaOrder, locale: Locale) -> String {
        let side = sideLabel(order.side, locale: locale)
        let size = quantityLabel(for: order, locale: locale)
        let type = orderTypeLabel(order.type ?? order.orderType, locale: locale)

        let sideAndSize = [side, size]
            .compactMap { nonEmpty($0) }
            .joined(separator: " ")

        return joined([sideAndSize, type])
    }

    private static func orderPriceDetail(for order: AlpacaOrder, locale: Locale) -> String {
        if let limitPrice = formattedPrice(order.limitPrice) {
            return L10n.LiveActivity.detailLimitPrice(limitPrice, locale: locale)
        }
        if let stopPrice = formattedPrice(order.stopPrice) {
            return L10n.LiveActivity.detailPrice(stopPrice, locale: locale)
        }
        return ""
    }

    private static func tradeEventBody(for event: AlpacaTradeEvent, locale: Locale) -> String {
        let order = event.order
        var parts: [String] = []

        if event.normalizedEvent == "partial_fill",
           let ratio = fillRatioText(for: order) {
            parts.append(ratio)
        }

        if let executionPrice = formattedPrice(event.price ?? order.filledAveragePrice) {
            parts.append(L10n.LiveActivity.detailAveragePrice(executionPrice, locale: locale))
        } else if let limitPrice = formattedPrice(order.limitPrice) {
            parts.append(L10n.LiveActivity.detailLimitPrice(limitPrice, locale: locale))
        } else if let stopPrice = formattedPrice(order.stopPrice) {
            parts.append(L10n.LiveActivity.detailPrice(stopPrice, locale: locale))
        }

        return joined(parts)
    }

    private static func fillRatioText(for order: AlpacaOrder) -> String? {
        let filled = AppFormatter.numberText(order.filledQuantity, placeholder: "")
        let total = AppFormatter.numberText(order.quantity, placeholder: "")
        guard !filled.isEmpty, !total.isEmpty else {
            return nil
        }
        return "\(filled)/\(total)"
    }

    private static func quantityLabel(for order: AlpacaOrder, locale: Locale) -> String? {
        let qty = AppFormatter.numberText(order.quantity, placeholder: "")
        if !qty.isEmpty {
            return L10n.LiveActivity.quantityShares(qty, locale: locale)
        }
        if let notional = formattedPrice(order.notional) {
            return notional
        }
        return nil
    }

    private static func sideLabel(_ side: String?, locale: Locale) -> String? {
        switch side?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "buy":
            L10n.Orders.Detail.sideBuy(locale: locale)
        case "sell":
            L10n.Orders.Detail.sideSell(locale: locale)
        default:
            nil
        }
    }

    private static func orderTypeLabel(_ type: String?, locale: Locale) -> String? {
        switch type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "market":
            L10n.Orders.Detail.orderTypeMarket(locale: locale)
        case "limit":
            L10n.Orders.Detail.orderTypeLimit(locale: locale)
        case "stop":
            L10n.Orders.Detail.orderTypeStop(locale: locale)
        case "stop_limit":
            L10n.Orders.Detail.orderTypeStopLimit(locale: locale)
        case "trailing_stop":
            L10n.Orders.Detail.orderTypeTrailingStop(locale: locale)
        default:
            nil
        }
    }

    private static func tradeEventStatusTitle(for event: AlpacaTradeEvent, locale: Locale) -> String {
        switch event.normalizedEvent {
        case "fill":
            return L10n.LiveActivity.orderStatus(.filled, locale: locale)
        case "partial_fill":
            return L10n.LiveActivity.orderStatus(.partiallyFilled, locale: locale)
        case "canceled", "cancelled":
            return L10n.LiveActivity.orderStatus(.canceled, locale: locale)
        case "rejected":
            return L10n.LiveActivity.orderStatus(.rejected, locale: locale)
        case "expired", "done_for_day":
            return L10n.LiveActivity.orderStatus(.expired, locale: locale)
        case "replaced":
            return L10n.LiveActivity.orderStatus(.replaced, locale: locale)
        case "accepted", "accepted_for_bidding", "pending_new", "new", "pending_cancel",
             "pending_replace", "stopped", "suspended", "calculated",
             "order_replace_rejected", "order_cancel_rejected", "trade_bust", "trade_correct":
            return L10n.ActivityNotification.tradeEventStatus(event.normalizedEvent, locale: locale)
        default:
            return event.event
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    private static func activityKindTitle(for event: AlpacaActivityEvent, locale: Locale) -> String {
        switch event.activityType.uppercased() {
        case "TRD":
            L10n.AccountActivity.tradeFill(locale: locale)
        case "CSD", "CSW", "ACATC", "ACATS", "FOPT", "JNLC", "JNLS":
            L10n.AccountActivity.transfer(locale: locale)
        case "DIV", "DIVNRA":
            L10n.AccountActivity.dividend(locale: locale)
        case "FEE":
            L10n.AccountActivity.fee(locale: locale)
        case "OPASN", "OPEXC", "OPEXP", "OPTRD", "OPCSH", "OPCA":
            L10n.AccountActivity.optionEvent(locale: locale)
        case "SPLIT", "SPIN", "MA", "NC", "REORG", "VOF", "FIMAT":
            L10n.AccountActivity.corporateAction(locale: locale)
        default:
            L10n.ActivityNotification.genericActivity(locale: locale)
        }
    }

    private static func accountActivityDetail(for event: AlpacaActivityEvent, locale: Locale) -> String {
        if event.activityType.uppercased() == "TRD" {
            let side = sideLabel(event.side, locale: locale)
            let qty = AppFormatter.numberText(event.quantity, placeholder: "")
            let qtyText = qty.isEmpty ? nil : L10n.LiveActivity.quantityShares(qty, locale: locale)
            let sideAndQty = [side, qtyText].compactMap { nonEmpty($0) }.joined(separator: " ")
            let price = formattedPrice(event.price, currencyCode: event.currency ?? "USD")
                .map { L10n.LiveActivity.detailPrice($0, locale: locale) }
            return joined([sideAndQty, price])
        }

        if let subtype = nonEmpty(event.activitySubtype) {
            return subtype.replacingOccurrences(of: "_", with: " ").capitalized
        }

        return ""
    }

    /// Uses 2 decimal places for normal prices (>= $1) and up to 4 decimals for
    /// sub-dollar prices, avoiding noisy `$230.9800` formatting.
    static func formattedPrice(_ raw: String?, currencyCode: String = "USD") -> String? {
        guard let raw, let value = NumberParser.double(from: raw), value > 0 else {
            return nil
        }

        let fractionLength = value < 1 ? 4 : 2
        let formatted = AppFormatter.money(
            value,
            currencyCode: currencyCode,
            fractionLength: fractionLength
        )
        return nonEmpty(formatted)
    }

    private static func formattedSignedAmount(for event: AlpacaActivityEvent) -> String? {
        guard let raw = event.netAmount, let value = NumberParser.double(from: raw) else {
            return nil
        }

        let currency = event.currency ?? "USD"
        let formatted = AppFormatter.signedMoney(value, currencyCode: currency)
        return nonEmpty(formatted)
    }

    private static func joined(_ parts: [String?]) -> String {
        parts.compactMap { nonEmpty($0) }.joined(separator: " · ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
