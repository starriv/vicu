import SwiftUI

struct TradeOrderConfirmationSnapshot: Identifiable {
    let id = UUID()
    let clientOrderID: String
    let order: OrderDraft
    let assetName: String
    let estimatedNotional: Decimal?
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
        estimatedExecutionPrice = store.estimatedExecutionPrice
        currencyCode = store.currencyCode
        self.environment = environment
        positionQuantity = store.positionQuantity
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
        VStack(spacing: 0) {
            header

            Form {
                Section {
                    TradeOrderConfirmationIdentityCard(snapshot: snapshot)
                }

                Section {
                    ForEach(detailItems.indices, id: \.self) { index in
                        TradeOrderConfirmationInfoRow(item: detailItems[index])
                    }
                }

                if !snapshot.warnings.isEmpty {
                    Section {
                        ForEach(snapshot.warnings, id: \.self) { warning in
                            TradeOrderConfirmationWarningRow(warning: warning)
                        }
                    }
                }

                if snapshot.isShortSell {
                    Section {
                        TradeOrderConfirmationWarningRow(
                            warning: L10n.Trade.confirmShortSellWarning(locale: locale)
                        )
                    }
                }

                Section {
                    Text(L10n.Trade.confirmMessage(
                        environment: snapshot.environment.titleText(locale: locale),
                        locale: locale
                    ))
                    .font(AppTypography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .presentationDetents([.height(580), .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 58, height: 5)
                .padding(.top, 10)

            HStack {
                Button(L10n.Common.cancelText(locale: locale)) {
                    dismiss()
                }
                .font(AppTypography.control)
                .foregroundStyle(.secondary)
                .disabled(isSubmitting)

                Spacer(minLength: 12)

                Text(L10n.Trade.simpleReviewOrder(locale: locale))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Color.clear
                    .frame(width: 52, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var footer: some View {
        HoldToConfirmButton(
            title: L10n.Trade.confirmHoldAction(
                side: snapshot.order.side.titleText(locale: locale),
                locale: locale
            ),
            progressTitle: L10n.Trade.confirmHoldProgress(locale: locale),
            submittingTitle: L10n.Trade.simpleSubmitting(locale: locale),
            tint: snapshot.order.side.tradeActionTint,
            isSubmitting: isSubmitting
        ) {
            await submit()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(.regularMaterial)
    }

    private var detailItems: [TradeOrderConfirmationInfoItem] {
        var items: [TradeOrderConfirmationInfoItem] = [
            TradeOrderConfirmationInfoItem(
                title: L10n.Trade.confirmSide(locale: locale),
                value: snapshot.order.side.titleText(locale: locale),
                tint: sideTint
            ),
            TradeOrderConfirmationInfoItem(
                title: L10n.Trade.confirmOrderType(locale: locale),
                value: snapshot.order.orderType.titleText(locale: locale)
            )
        ]

        if let quantityText = TradeOrderConfirmationFormat.quantity(snapshot.order.quantityText) {
            items.append(TradeOrderConfirmationInfoItem(
                title: L10n.Trade.confirmQuantity(locale: locale),
                value: quantityText
            ))
        }

        if let notionalText = TradeOrderConfirmationFormat.moneyText(
            snapshot.order.notionalText,
            currency: snapshot.currencyCode
        ) {
            items.append(TradeOrderConfirmationInfoItem(
                title: L10n.Trade.confirmAmount(locale: locale),
                value: notionalText
            ))
        }

        items.append(TradeOrderConfirmationInfoItem(
            title: L10n.Trade.confirmEstimatedPrice(locale: locale),
            value: TradeOrderConfirmationFormat.price(snapshot.estimatedExecutionPrice, currency: snapshot.currencyCode)
        ))

        if let limitPrice = TradeOrderConfirmationFormat.priceText(
            snapshot.order.limitPriceText,
            currency: snapshot.currencyCode
        ) {
            items.append(TradeOrderConfirmationInfoItem(
                title: L10n.Trade.confirmLimitPrice(locale: locale),
                value: limitPrice
            ))
        }

        items.append(contentsOf: [
            TradeOrderConfirmationInfoItem(
                title: snapshot.order.side == .buy
                    ? L10n.Trade.simpleEstimatedDebit(locale: locale)
                    : L10n.Trade.simpleEstimatedCredit(locale: locale),
                value: TradeOrderConfirmationFormat.money(snapshot.estimatedNotional, currency: snapshot.currencyCode)
            ),
            TradeOrderConfirmationInfoItem(
                title: L10n.Trade.confirmTimeInForce(locale: locale),
                value: snapshot.order.timeInForce.title
            ),
            TradeOrderConfirmationInfoItem(
                title: L10n.Trade.confirmSession(locale: locale),
                value: snapshot.order.extendedHours
                    ? L10n.Orders.Detail.extendedSession(locale: locale)
                    : L10n.Orders.Detail.regularSession(locale: locale)
            ),
            TradeOrderConfirmationInfoItem(
                title: L10n.Trade.confirmEnvironment(locale: locale),
                value: snapshot.environment.titleText(locale: locale)
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
        isSubmitting = false

        switch result {
        case .success(let submittedOrder):
            dismiss()
            onSubmitted(submittedOrder)
        case .failure(let message):
            toastCenter.showErrorMessage(message)
        }
    }
}

private struct TradeOrderConfirmationIdentityCard: View {
    @Environment(\.locale) private var locale

    let snapshot: TradeOrderConfirmationSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
                    Text(snapshot.order.normalizedSymbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if snapshot.isShortSell {
                        Text(L10n.Trade.confirmShortSellTag(locale: locale))
                            .font(AppTypography.badge)
                            .foregroundStyle(AppTheme.ColorToken.warning)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(AppTheme.ColorToken.warning.opacity(0.12), in: Capsule())
                    }
                }

                Text(snapshot.assetName)
                    .font(AppTypography.rowMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LabeledContent {
                Text(TradeOrderConfirmationFormat.money(snapshot.estimatedNotional, currency: snapshot.currencyCode))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } label: {
                Text(snapshot.order.side == .buy
                    ? L10n.Trade.simpleEstimatedDebit(locale: locale)
                    : L10n.Trade.simpleEstimatedCredit(locale: locale)
                )
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct TradeOrderConfirmationInfoItem {
    let title: String
    let value: String
    var tint: Color = .primary
}

private struct TradeOrderConfirmationInfoRow: View {
    let item: TradeOrderConfirmationInfoItem

    var body: some View {
        LabeledContent {
            Text(item.value)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        } label: {
            Text(item.title)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TradeOrderConfirmationWarningRow: View {
    let warning: String
    var systemImage = "exclamationmark.circle.fill"
    var tint = AppTheme.ColorToken.warning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)

            Text(warning)
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum TradeOrderConfirmationFormat {
    static func money(_ value: Decimal?, currency: String) -> String {
        AppFormatter.money(value, currencyCode: currency)
    }

    static func moneyText(_ text: String, currency: String) -> String? {
        guard let value = NumberParser.decimal(from: OrderDraft.normalizedSizeText(text)) else {
            return nil
        }

        return money(value, currency: currency)
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

    static func percent(_ text: String) -> String? {
        let normalized = NumberText.trimTrailingZeros(text)
        guard !normalized.isEmpty else {
            return nil
        }

        return "\(normalized)%"
    }
}
