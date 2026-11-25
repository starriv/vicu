import SwiftUI

struct TradeOrderConfirmationSnapshot: Identifiable {
    let id = UUID()
    let clientOrderID: String
    let order: OrderDraft
    let assetName: String
    let estimatedNotional: Decimal?
    let estimatedQuantity: Decimal?
    let estimatedExecutionPrice: Decimal?
    let currencyCode: String
    let environment: TradeEnvironment
    let positionQuantity: Decimal
    let warnings: [String]

    @MainActor
    init(store: TradeStore, environment: TradeEnvironment) {
        clientOrderID = "vicu-\(UUID().uuidString.lowercased())"
        order = store.draft
        assetName = store.assetDisplayName
        estimatedNotional = store.estimatedNotional
        estimatedQuantity = store.estimatedQuantity
        estimatedExecutionPrice = store.estimatedExecutionPrice
        currencyCode = store.currencyCode
        self.environment = environment
        positionQuantity = store.availableSellQuantity
        warnings = store.validation.warnings
    }

    var isShortSell: Bool {
        guard order.side == .sell, hasPositiveSellSize else {
            return false
        }

        if positionQuantity <= 0 {
            return true
        }

        guard let requestedQuantity else {
            return false
        }

        return requestedQuantity > positionQuantity
    }

    private var hasPositiveSellSize: Bool {
        NumberParser.decimal(from: OrderDraft.normalizedSizeText(order.quantityText)) != nil
            || NumberParser.decimal(from: OrderDraft.normalizedSizeText(order.notionalText)) != nil
    }

    private var requestedQuantity: Decimal? {
        if let quantity = NumberParser.decimal(from: OrderDraft.normalizedSizeText(order.quantityText)) {
            return quantity
        }

        if let estimatedQuantity {
            return estimatedQuantity
        }

        guard let notional = NumberParser.decimal(from: OrderDraft.normalizedSizeText(order.notionalText)),
              let estimatedExecutionPrice,
              estimatedExecutionPrice > 0 else {
            return nil
        }

        return notional / estimatedExecutionPrice
    }
}

struct TradeOrderConfirmationSheet: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let snapshot: TradeOrderConfirmationSnapshot
    let onSubmit: () async -> TradeSubmitResult
    let onSubmitted: (AlpacaOrder) -> Void

    @State private var isSubmitting = false

    var body: some View {
        AppActionSheetContainer(
            title: L10n.Trade.simpleReviewOrder(locale: locale),
            isSubmitting: isSubmitting,
            minHeight: 440,
            maxHeight: 740,
            fallbackHeight: 310 + CGFloat(detailItems.count) * 46 + (warningMessages.isEmpty ? 0 : 76)
        ) {
            VStack(spacing: 0) {
                TradeOrderConfirmationHeroHeader(snapshot: snapshot)
                    .padding(.top, 6)
                    .padding(.bottom, 22)

                AppSheetInfoCard(items: detailItems)

                if !warningMessages.isEmpty {
                    AppSheetWarningBanner(messages: warningMessages)
                        .padding(.top, 12)
                }

                AppSheetActionButton(
                    title: actionButtonTitle,
                    accessibilityTitle: actionButtonTitle,
                    submittingTitle: L10n.Trade.simpleSubmitting(locale: locale),
                    tint: sideTint,
                    isSubmitting: isSubmitting
                ) {
                    await submit()
                }
                .padding(.top, 22)
                .padding(.bottom, 12)
            }
        }
    }

    private var actionButtonTitle: String {
        L10n.Trade.limitTitle(
            side: snapshot.order.side.titleText(locale: locale),
            symbol: snapshot.order.normalizedSymbol,
            locale: locale
        )
    }

    private var warningMessages: [String] {
        var messages = snapshot.warnings

        if snapshot.isShortSell {
            messages.append(L10n.Trade.confirmShortSellWarning(locale: locale))
        }

        return messages
    }

    private var detailItems: [AppSheetInfoItem] {
        var items: [AppSheetInfoItem] = []

        if let limitPrice = TradeOrderConfirmationFormat.priceText(
            snapshot.order.limitPriceText,
            currency: snapshot.currencyCode
        ) {
            items.append(AppSheetInfoItem(
                title: L10n.Trade.confirmLimitPrice(locale: locale),
                value: limitPrice
            ))
        } else {
            items.append(AppSheetInfoItem(
                title: L10n.Trade.confirmEstimatedPrice(locale: locale),
                value: TradeOrderConfirmationFormat.price(snapshot.estimatedExecutionPrice, currency: snapshot.currencyCode)
            ))
        }

        items.append(contentsOf: [
            AppSheetInfoItem(
                title: L10n.Trade.confirmEnvironment(locale: locale),
                value: snapshot.environment.titleText(locale: locale)
            ),
            AppSheetInfoItem(
                title: L10n.Trade.confirmTimeInForce(locale: locale),
                value: snapshot.order.timeInForce.title
            ),
            AppSheetInfoItem(
                title: L10n.Trade.confirmSession(locale: locale),
                value: snapshot.order.extendedHours
                    ? L10n.Orders.Detail.extendedSession(locale: locale)
                    : L10n.Orders.Detail.regularSession(locale: locale)
            )
        ])

        return items
    }

    private var sideTint: Color {
        snapshot.order.side.tradeActionTint
    }

    private func submit() async {
        guard !isSubmitting else {
            return
        }

        isSubmitting = true
        let result = await onSubmit()
        finishSubmission(result)
    }

    private func finishSubmission(_ result: TradeSubmitResult) {
        switch result {
        case .success(let submittedOrder):
            dismiss()
            showToastAfterSheetDismissal(.success(L10n.Trade.orderSubmitted(locale: locale)))
            onSubmitted(submittedOrder)
        case .failure(let message):
            isSubmitting = false
            dismiss()
            showToastAfterSheetDismissal(.error(message))
        }
    }

    private func showToastAfterSheetDismissal(_ feedback: TradeOrderConfirmationFeedback) {
        Task { @MainActor [toastCenter] in
            try? await Task.sleep(for: .milliseconds(320))

            switch feedback {
            case .success(let message):
                toastCenter.show(message)
            case .error(let message):
                toastCenter.showErrorMessage(message)
            }
        }
    }
}

private enum TradeOrderConfirmationFeedback {
    case success(String)
    case error(String)
}

private struct TradeOrderConfirmationHeroHeader: View {
    @Environment(\.locale) private var locale

    let snapshot: TradeOrderConfirmationSnapshot

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack(spacing: 6) {
                AppSheetBadgePill(title: sideOrderBadgeText, tint: sideTint)

                if snapshot.isShortSell {
                    AppSheetBadgePill(
                        title: L10n.Trade.confirmShortSellTag(locale: locale),
                        tint: AppTheme.ColorToken.warning,
                        horizontalPadding: 10,
                        backgroundOpacity: 0.14
                    )
                }
            }

            Text(heroPrimaryText)
                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.top, 14)

            if let shareSummaryText {
                Text(shareSummaryText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 6)
            }

            if let companySubtitle {
                Text(companySubtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var sideTint: Color {
        snapshot.order.side.tradeActionTint
    }

    private var sideOrderBadgeText: String {
        let orderTypeLabel: String
        if snapshot.order.orderType == .market {
            orderTypeLabel = L10n.Trade.simpleMarketOrder(locale: locale)
        } else {
            orderTypeLabel = L10n.Trade.simpleOrderTypeTitle(
                orderType: snapshot.order.orderType.titleText(locale: locale),
                locale: locale
            )
        }
        return "\(snapshot.order.side.titleText(locale: locale)) · \(orderTypeLabel)"
    }

    private var heroPrimaryText: String {
        if let notional = snapshot.estimatedNotional {
            return TradeOrderConfirmationFormat.money(notional, currency: snapshot.currencyCode)
        }
        if let quantityText = TradeOrderConfirmationFormat.quantity(snapshot.order.quantityText) {
            return "\(quantityText) \(snapshot.order.normalizedSymbol)"
        }
        return AppFormatter.placeholder
    }

    private var shareSummaryText: String? {
        guard snapshot.estimatedNotional != nil else {
            return nil
        }
        if let quantityText = TradeOrderConfirmationFormat.quantity(snapshot.order.quantityText) {
            return "\(quantityText) \(snapshot.order.normalizedSymbol)"
        }
        if let estimatedShares = TradeOrderConfirmationFormat.quantityDecimal(snapshot.estimatedQuantity) {
            return "≈ \(estimatedShares) \(snapshot.order.normalizedSymbol)"
        }
        return snapshot.order.normalizedSymbol
    }

    private var companySubtitle: String? {
        let name = snapshot.assetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != AppFormatter.placeholder else {
            return nil
        }
        return name
    }
}

private enum TradeOrderConfirmationFormat {
    static func money(_ value: Decimal?, currency: String) -> String {
        AppFormatter.money(value, currencyCode: currency)
    }

    static func price(_ value: Decimal?, currency: String) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        let absValue = abs(NSDecimalNumber(decimal: value).doubleValue)
        let fractionLength = absValue > 0 && absValue < 1 ? 4 : 2
        return AppFormatter.money(value, currencyCode: currency, fractionLength: fractionLength)
    }

    static func priceText(_ text: String, currency: String) -> String? {
        let normalized = NumberText.trimTrailingZeros(text)
        guard let value = NumberParser.decimal(from: normalized), value > 0 else {
            return nil
        }

        return price(value, currency: currency)
    }

    static func quantity(_ text: String) -> String? {
        let normalized = NumberText.trimTrailingZeros(OrderDraft.normalizedSizeText(text))
        return normalized.isEmpty ? nil : normalized
    }

    static func quantityDecimal(_ value: Decimal?) -> String? {
        guard let value, value > 0 else {
            return nil
        }

        var copy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, 6, .down)
        let normalized = NumberText.trimTrailingZeros(NSDecimalNumber(decimal: rounded).stringValue)
        return normalized.isEmpty ? nil : normalized
    }
}
