import Foundation

struct AppNotificationTemplate: Sendable {
    let title: String
    let body: String
    let categoryIdentifier: String
    let threadIdentifier: String
}

enum AppNotificationTemplates {
    enum CategoryIdentifier {
        static let accountActivityEvent = "ALPACA_ACCOUNT_ACTIVITY"
        static let tradeOrderSubmitted = "ALPACA_ORDER_SUBMITTED"
        static let tradeOrderStatus = "ALPACA_TRADE_ORDER_STATUS"
    }

    private enum ThreadIdentifier {
        static let accountActivityEvent = "alpaca-account-activity"
        static let tradeOrderSubmitted = "alpaca-trade-orders"
        static let tradeOrderStatus = "alpaca-trade-order-status"
    }

    static func accountActivityEvent(_ event: AlpacaActivityEvent, locale: Locale) -> AppNotificationTemplate {
        AppNotificationTemplate(
            title: L10n.ActivityNotification.title(locale: locale),
            body: accountActivityBody(for: event, locale: locale),
            categoryIdentifier: CategoryIdentifier.accountActivityEvent,
            threadIdentifier: ThreadIdentifier.accountActivityEvent
        )
    }

    static func orderSubmitted(order: AlpacaOrder, locale: Locale) -> AppNotificationTemplate {
        AppNotificationTemplate(
            title: L10n.ActivityNotification.orderSubmittedTitle(locale: locale),
            body: orderSubmittedBody(for: order, locale: locale),
            categoryIdentifier: CategoryIdentifier.tradeOrderSubmitted,
            threadIdentifier: ThreadIdentifier.tradeOrderSubmitted
        )
    }

    static func tradeEvent(_ event: AlpacaTradeEvent, locale: Locale) -> AppNotificationTemplate {
        AppNotificationTemplate(
            title: L10n.ActivityNotification.tradeEventTitle(
                status: tradeEventStatusTitle(for: event, locale: locale),
                locale: locale
            ),
            body: tradeEventBody(for: event, locale: locale),
            categoryIdentifier: CategoryIdentifier.tradeOrderStatus,
            threadIdentifier: ThreadIdentifier.tradeOrderStatus
        )
    }

    private static func accountActivityBody(for event: AlpacaActivityEvent, locale: Locale) -> String {
        let kind = activityKindTitle(for: event, locale: locale)
        let subject = subject(for: event)
        let netAmount = formattedNetAmount(for: event)

        switch (subject, netAmount) {
        case (.some(let subject), .some(let netAmount)):
            return L10n.ActivityNotification.bodySubjectAmount(
                kind: kind,
                subject: subject,
                amount: netAmount,
                locale: locale
            )
        case (.some(let subject), .none):
            return L10n.ActivityNotification.bodySubject(
                kind: kind,
                subject: subject,
                locale: locale
            )
        case (.none, .some(let netAmount)):
            return L10n.ActivityNotification.bodyAmount(
                kind: kind,
                amount: netAmount,
                locale: locale
            )
        case (.none, .none):
            return L10n.ActivityNotification.bodyGeneric(kind: kind, locale: locale)
        }
    }

    private static func orderSubmittedBody(for order: AlpacaOrder, locale: Locale) -> String {
        L10n.ActivityNotification.orderSubmittedBody(
            side: orderSideTitle(order.side, locale: locale),
            size: orderSizeText(order, locale: locale),
            symbol: order.symbol.uppercased(),
            type: orderTypeTitle(order.type ?? order.orderType, locale: locale),
            locale: locale
        )
    }

    private static func tradeEventBody(for event: AlpacaTradeEvent, locale: Locale) -> String {
        L10n.ActivityNotification.tradeEventBody(
            side: orderSideTitle(event.order.side, locale: locale),
            size: tradeEventSizeText(event, locale: locale),
            symbol: event.order.symbol.uppercased(),
            type: orderTypeTitle(event.order.type ?? event.order.orderType, locale: locale),
            priceSuffix: tradeEventPriceSuffix(event, locale: locale),
            locale: locale
        )
    }

    private static func tradeEventSizeText(_ event: AlpacaTradeEvent, locale: Locale) -> String {
        let quantityText = AppFormatter.numberText(event.quantity, placeholder: "")
        if !quantityText.isEmpty {
            return L10n.ActivityNotification.orderSubmittedQuantitySize(quantityText, locale: locale)
        }

        let filledQuantity = AppFormatter.numberText(event.order.filledQuantity, placeholder: "")
        if !filledQuantity.isEmpty, event.normalizedEvent == "fill" || event.normalizedEvent == "partial_fill" {
            return L10n.ActivityNotification.orderSubmittedQuantitySize(filledQuantity, locale: locale)
        }

        return orderSizeText(event.order, locale: locale)
    }

    private static func tradeEventPriceSuffix(_ event: AlpacaTradeEvent, locale: Locale) -> String {
        guard let priceText = tradeEventPriceText(event) else {
            return ""
        }

        return L10n.ActivityNotification.tradeEventPriceSuffix(priceText, locale: locale)
    }

    private static func tradeEventStatusTitle(for event: AlpacaTradeEvent, locale: Locale) -> String {
        let key: String
        switch event.normalizedEvent {
        case "accepted":
            key = "accepted"
        case "accepted_for_bidding":
            key = "accepted_for_bidding"
        case "pending_new":
            key = "pending_new"
        case "new":
            key = "new"
        case "partial_fill":
            key = "partial_fill"
        case "fill":
            key = "fill"
        case "done_for_day":
            key = "done_for_day"
        case "canceled", "cancelled":
            key = "canceled"
        case "expired":
            key = "expired"
        case "replaced":
            key = "replaced"
        case "pending_cancel":
            key = "pending_cancel"
        case "pending_replace":
            key = "pending_replace"
        case "stopped":
            key = "stopped"
        case "rejected":
            key = "rejected"
        case "suspended":
            key = "suspended"
        case "calculated":
            key = "calculated"
        case "order_replace_rejected":
            key = "order_replace_rejected"
        case "order_cancel_rejected":
            key = "order_cancel_rejected"
        case "trade_bust":
            key = "trade_bust"
        case "trade_correct":
            key = "trade_correct"
        default:
            return apiValue(event.event)
        }

        return L10n.ActivityNotification.tradeEventStatus(key, locale: locale)
    }

    private static func tradeEventPriceText(_ event: AlpacaTradeEvent) -> String? {
        guard let price = event.price ?? event.order.filledAveragePrice ?? event.order.limitPrice else {
            return nil
        }

        let priceText = AppFormatter.money(price, fractionLength: 4, placeholder: "")
        return priceText.isEmpty ? nil : priceText
    }

    private static func activityKindTitle(for event: AlpacaActivityEvent, locale: Locale) -> String {
        switch event.activityType.uppercased() {
        case "TRD":
            return L10n.AccountActivity.tradeFill(locale: locale)
        case "CSD", "CSW", "ACATC", "ACATS", "FOPT", "JNLC", "JNLS":
            return L10n.AccountActivity.transfer(locale: locale)
        case "DIV", "DIVNRA":
            return L10n.AccountActivity.dividend(locale: locale)
        case "FEE":
            return L10n.AccountActivity.fee(locale: locale)
        case "OPASN", "OPEXC", "OPEXP", "OPTRD", "OPCSH", "OPCA":
            return L10n.AccountActivity.optionEvent(locale: locale)
        case "SPLIT", "SPIN", "MA", "NC", "REORG", "VOF", "FIMAT":
            return L10n.AccountActivity.corporateAction(locale: locale)
        default:
            return L10n.ActivityNotification.genericActivity(locale: locale)
        }
    }

    private static func orderSideTitle(_ side: String?, locale: Locale) -> String {
        switch side?.lowercased() {
        case "buy":
            return L10n.Order.sideBuyText(locale: locale)
        case "sell":
            return L10n.Order.sideSellText(locale: locale)
        default:
            return apiValue(side)
        }
    }

    private static func orderTypeTitle(_ type: String?, locale: Locale) -> String {
        switch type?.lowercased() {
        case "market":
            return L10n.Order.typeMarketText(locale: locale)
        case "limit":
            return L10n.Order.typeLimitText(locale: locale)
        default:
            return apiValue(type)
        }
    }

    private static func orderSizeText(_ order: AlpacaOrder, locale: Locale) -> String {
        let quantityText = AppFormatter.numberText(order.quantity, placeholder: "")
        if !quantityText.isEmpty {
            return L10n.ActivityNotification.orderSubmittedQuantitySize(quantityText, locale: locale)
        }

        let notionalText = AppFormatter.money(order.notional, placeholder: "")
        return notionalText.isEmpty ? AppFormatter.placeholder : notionalText
    }

    private static func apiValue(_ value: String?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty
            ? AppFormatter.placeholder
            : trimmedValue.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private static func subject(for event: AlpacaActivityEvent) -> String? {
        let symbol = event.symbol?.uppercased()

        if event.activityType.uppercased() == "TRD" {
            var parts: [String] = []
            if let side = event.side?.uppercased(), !side.isEmpty {
                parts.append(side)
            }

            if let quantity = event.quantity {
                let quantityText = AppFormatter.numberText(quantity, placeholder: "")
                if !quantityText.isEmpty {
                    parts.append(quantityText)
                }
            }

            if let symbol {
                parts.append(symbol)
            }

            if let price = formattedPrice(for: event) {
                parts.append("@ \(price)")
            }

            return parts.isEmpty ? symbol : parts.joined(separator: " ")
        }

        if let symbol, let subtype = event.activitySubtype, !subtype.isEmpty {
            return "\(symbol) \(subtype)"
        }

        return symbol
    }

    private static func formattedPrice(for event: AlpacaActivityEvent) -> String? {
        guard let price = event.price else {
            return nil
        }

        let priceText = AppFormatter.money(
            price,
            currencyCode: event.currency ?? "USD",
            fractionLength: 4,
            placeholder: ""
        )
        return priceText.isEmpty ? nil : priceText
    }

    private static func formattedNetAmount(for event: AlpacaActivityEvent) -> String? {
        guard let netAmount = event.netAmount else {
            return nil
        }

        let amountText = AppFormatter.money(
            netAmount,
            currencyCode: event.currency ?? "USD",
            fractionLength: 2,
            placeholder: ""
        )
        return amountText.isEmpty ? nil : amountText
    }
}
