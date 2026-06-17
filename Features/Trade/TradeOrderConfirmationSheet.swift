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
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .presentationDetents([.large])
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

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                TradeOrderConfirmationIdentityCard(snapshot: snapshot)
                    .tradeConfirmationCard()

                detailCard

                if !warningMessages.isEmpty {
                    warningCard
                }

                confirmationMessage

                TradeOrderConfirmationActionButton(
                    title: snapshot.order.side.titleText(locale: locale),
                    accessibilityTitle: snapshot.order.side.titleText(locale: locale),
                    submittingTitle: L10n.Trade.simpleSubmitting(locale: locale),
                    tint: snapshot.order.side.tradeActionTint,
                    isSubmitting: isSubmitting
                ) {
                    await submit()
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.top, 8)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
        }
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            ForEach(detailItems.indices, id: \.self) { index in
                TradeOrderConfirmationInfoRow(item: detailItems[index])

                if index < detailItems.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .tradeConfirmationCard(padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    private var warningCard: some View {
        VStack(spacing: 12) {
            ForEach(warningMessages, id: \.self) { warning in
                TradeOrderConfirmationWarningRow(warning: warning)
            }
        }
        .tradeConfirmationCard()
    }

    private var confirmationMessage: some View {
        Text(L10n.Trade.confirmMessage(
            environment: snapshot.environment.titleText(locale: locale),
            locale: locale
        ))
        .font(AppTypography.detail)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .tradeConfirmationCard(padding: EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
    }

    private var warningMessages: [String] {
        var messages = snapshot.warnings

        if snapshot.isShortSell {
            messages.append(L10n.Trade.confirmShortSellWarning(locale: locale))
        }

        return messages
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

private struct TradeOrderConfirmationActionButton: View {
    let title: String
    let accessibilityTitle: String
    let submittingTitle: String
    let tint: Color
    let isSubmitting: Bool
    let action: () async -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            glassButton
        } else {
            fallbackButton
        }
    }

    @available(iOS 26.0, *)
    private var glassButton: some View {
        Button {
            Task { await action() }
        } label: {
            label
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(tint)
        .disabled(isSubmitting)
        .accessibilityLabel(isSubmitting ? submittingTitle : accessibilityTitle)
    }

    private var fallbackButton: some View {
        Button {
            Task { await action() }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(isSubmitting ? 0.18 : 0.34), lineWidth: 0.75)
        }
        .shadow(color: tint.opacity(0.12), radius: 18, y: 7)
        .disabled(isSubmitting)
        .accessibilityLabel(isSubmitting ? submittingTitle : accessibilityTitle)
    }

    private var label: some View {
        HStack(spacing: 9) {
            if isSubmitting {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
            } else {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(Capsule())
    }
}

private extension View {
    func tradeConfirmationCard(
        padding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.10))
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
        .padding(.vertical, 14)
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
