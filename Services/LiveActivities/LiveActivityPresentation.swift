import Foundation

/// Turns domain snapshots into the presentational payloads that Live Activities
/// carry. This is the only place allowed to produce user-visible strings for the
/// Lock Screen, because it is the only place that knows the user's app language.
enum LiveActivityPresentation {
    // MARK: - Order

    static func orderAttributes(
        for order: AlpacaOrder,
        locale: Locale
    ) -> OrderActivityAttributes {
        OrderActivityAttributes(
            orderID: order.id,
            symbol: order.symbol,
            side: OrderActivitySide(rawSide: order.side),
            sideLabel: sideLabel(order.side, locale: locale),
            orderTypeLabel: orderTypeLabel(for: order, locale: locale)
        )
    }

    static func orderContent(
        for order: AlpacaOrder,
        additionalWorkingCount: Int,
        locale: Locale,
        now: Date = Date()
    ) -> OrderActivityAttributes.ContentState {
        let phase = LiveActivityPolicy.phase(forStatus: order.status)
        let canCancel = order.supportsCancellation

        return OrderActivityAttributes.ContentState(
            phase: phase,
            statusTitle: L10n.LiveActivity.orderStatus(phase, locale: locale),
            detailLine: detailLine(for: order, locale: locale),
            fillProgress: LiveActivityPolicy.fillProgress(for: order),
            fillRatioText: fillRatioText(for: order),
            asOfText: asOfText(for: LiveActivityPolicy.lastActivityDate(for: order), locale: locale),
            actionTitle: canCancel ? L10n.LiveActivity.cancelActionText(locale: locale) : nil,
            additionalOrdersText: additionalWorkingCount > 0
                ? L10n.LiveActivity.additionalWorking(additionalWorkingCount, locale: locale)
                : nil,
            allowsCancellation: canCancel
        )
    }

    private static func detailLine(for order: AlpacaOrder, locale: Locale) -> String {
        let hasFill = (NumberParser.double(from: order.filledQuantity) ?? 0) > 0

        if hasFill, let averagePrice = order.filledAveragePrice {
            return L10n.LiveActivity.detailAveragePrice(
                AppFormatter.money(averagePrice),
                locale: locale
            )
        }

        if let limitPrice = order.limitPrice, !limitPrice.isEmpty {
            return L10n.LiveActivity.detailLimitPrice(
                AppFormatter.money(limitPrice),
                locale: locale
            )
        }

        if let stopPrice = order.stopPrice, !stopPrice.isEmpty {
            return L10n.LiveActivity.detailPrice(
                AppFormatter.money(stopPrice),
                locale: locale
            )
        }

        if let notional = order.notional, !notional.isEmpty {
            return L10n.LiveActivity.detailNotional(
                AppFormatter.money(notional),
                locale: locale
            )
        }

        return ""
    }

    private static func fillRatioText(for order: AlpacaOrder) -> String {
        let filled = compactQuantityText(order.filledQuantity, placeholder: "0")

        if let quantity = order.quantity, !quantity.isEmpty {
            return "\(filled)/\(compactQuantityText(quantity, placeholder: AppFormatter.placeholder))"
        }

        if let notional = order.notional, !notional.isEmpty {
            return AppFormatter.money(notional)
        }

        return filled
    }

    private static func compactQuantityText(_ raw: String?, placeholder: String) -> String {
        guard let raw, let value = NumberParser.double(from: raw) else {
            return AppFormatter.numberText(raw, placeholder: placeholder)
        }

        if abs(value.rounded() - value) < 0.00001 {
            return String(Int(value.rounded()))
        }

        return value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
    }

    private static func sideLabel(_ side: String?, locale: Locale) -> String {
        switch side?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "buy":
            L10n.Orders.Detail.sideBuy(locale: locale)
        case "sell":
            L10n.Orders.Detail.sideSell(locale: locale)
        default:
            (side ?? "--").uppercased()
        }
    }

    private static func orderTypeLabel(for order: AlpacaOrder, locale: Locale) -> String {
        switch (order.type ?? order.orderType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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
            (order.type ?? order.orderType ?? "--").uppercased()
        }
    }

    // MARK: - Session

    static func sessionAttributes(marketName: String) -> SessionActivityAttributes {
        SessionActivityAttributes(marketName: marketName)
    }

    static func sessionContent(
        active: MarketSessionInterval,
        progress: MarketSessionProgress,
        account: AlpacaAccount?,
        workingOrders: Int,
        marketName: String,
        locale: Locale
    ) -> SessionActivityAttributes.ContentState {
        let segments = progress.intervals.map { interval in
            SessionActivitySegment(
                id: interval.id,
                title: L10n.LiveActivity.sessionPhaseShort(interval.session, locale: locale),
                weight: max(interval.end.timeIntervalSince(interval.start), 1),
                isActive: interval.id == active.id
            )
        }

        let summary = sessionSummary(account: account)

        return SessionActivityAttributes.ContentState(
            phaseTitle: L10n.LiveActivity.sessionPhase(active.session, locale: locale),
            phaseSymbol: sessionSymbol(active.session),
            countdownLabel: countdownLabel(for: active.session, locale: locale),
            sessionStart: active.start,
            transitionAt: active.end,
            cycleStart: progress.intervals.first?.start ?? active.start,
            cycleEnd: progress.intervals.last?.end ?? active.end,
            segments: segments,
            summaryText: summary?.text,
            summaryIsNegative: summary?.isNegative ?? false,
            trailingText: workingOrders > 0
                ? L10n.LiveActivity.workingOrders(workingOrders, locale: locale)
                : L10n.LiveActivity.noWorkingOrders(locale: locale)
        )
    }

    private static func countdownLabel(for session: MarketSessionKind, locale: Locale) -> String {
        switch session {
        case .regular, .afterHours:
            L10n.LiveActivity.sessionCloses(locale: locale)
        case .preMarket, .overnight:
            L10n.LiveActivity.sessionOpens(locale: locale)
        }
    }

    private static func sessionSymbol(_ session: MarketSessionKind) -> String {
        switch session {
        case .overnight:
            "moon.stars.fill"
        case .preMarket:
            "sunrise.fill"
        case .regular:
            "sun.max.fill"
        case .afterHours:
            "sunset.fill"
        }
    }

    /// Day P/L snapshot: `equity` minus the previous close. Returns `nil` when the
    /// account payload does not have enough information to be meaningful.
    private static func sessionSummary(account: AlpacaAccount?) -> (text: String, isNegative: Bool)? {
        guard let equity = NumberParser.double(from: account?.equity),
              let lastEquity = NumberParser.double(from: account?.lastEquity),
              lastEquity > 0 else {
            return nil
        }

        let delta = equity - lastEquity
        let percent = delta / lastEquity
        let text = "\(AppFormatter.signedMoney(delta)) (\(AppFormatter.signedPercent(percent)))"
        return (text, delta < 0)
    }

    static func asOfText(for date: Date, locale: Locale) -> String {
        let time = date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        )
        return L10n.LiveActivity.asOf(time, locale: locale)
    }
}
