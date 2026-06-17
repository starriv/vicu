import SwiftUI

struct TradeView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var store: TradeStore
    @State private var confirmation: TradeOrderConfirmationSnapshot?
    @State private var submittedOrder: TradeSubmittedOrderDestination?
    @State private var isShowingLimitOrder = false

    private let submittedOrderHandler: ((AlpacaOrder) -> Void)?

    init(
        symbol: String? = nil,
        side: OrderSide = .buy,
        onSubmittedOrder: ((AlpacaOrder) -> Void)? = nil
    ) {
        _store = State(initialValue: TradeStore(symbol: symbol, side: side, orderType: .market, sizingMode: .shares))
        submittedOrderHandler = onSubmittedOrder
    }

    var body: some View {
        TradeSimpleView(
            store: store,
            canUseAPI: app.canUseAlpacaAPI,
            close: { dismiss() },
            review: reviewOrder,
            showLimitOrder: showLimitOrder
        )
        .task(id: store.normalizedSymbol) {
            guard !store.normalizedSymbol.isEmpty else { return }
            store.loadContext(app: app, force: true)
        }
        .onChange(of: store.draft.orderType) { _, orderType in
            store.normalizeForOrderType(orderType)
        }
        .onChange(of: store.draft.timeInForce) { _, timeInForce in
            store.normalizeForTimeInForce(timeInForce)
        }
        .onChange(of: store.contextErrorMessage) { _, message in
            showErrorMessage(message)
        }
        .onAppear {
            store.updateLocale(app.appLanguage.locale)
        }
        .onChange(of: app.appLanguage) { _, language in
            store.updateLocale(language.locale)
        }
        .onDisappear {
            store.stopPolling()
        }
        .navigationDestination(isPresented: $isShowingLimitOrder) {
            TradeLimitOrderView(
                store: store,
                canUseAPI: app.canUseAlpacaAPI,
                onSubmittedOrder: { showSubmittedOrder($0) }
            )
        }
        .navigationDestination(item: $submittedOrder) { destination in
            OrderDetailView(order: destination.order)
        }
        .sheet(item: $confirmation) { snapshot in
            TradeOrderConfirmationSheet(snapshot: snapshot) {
                await store.submit(snapshot.order, clientOrderID: snapshot.clientOrderID, app: app)
            } onSubmitted: { order in
                showSubmittedOrder(order)
            }
        }
    }

    private func reviewOrder() {
        let validation = store.validation
        if validation.canSubmit {
            confirmation = TradeOrderConfirmationSnapshot(store: store, environment: app.environment)
        } else {
            store.message = validation.errors.first
        }
    }

    private func showLimitOrder() {
        store.prepareLimitOrder()
        isShowingLimitOrder = true
    }

    private func showSubmittedOrder(_ order: AlpacaOrder) {
        if let submittedOrderHandler {
            store.stopPolling()
            isShowingLimitOrder = false
            submittedOrderHandler(order)
            return
        }

        submittedOrder = TradeSubmittedOrderDestination(order: order)
    }

    private func showErrorMessage(_ message: String?) {
        guard let message else {
            return
        }

        toastCenter.showErrorMessage(message)
    }
}

private struct TradeSubmittedOrderDestination: Identifiable, Hashable {
    let order: AlpacaOrder

    var id: String { order.id }

    static func == (lhs: TradeSubmittedOrderDestination, rhs: TradeSubmittedOrderDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private enum TradeLimitFocusedField {
    case quantity
    case limitPrice
}

private struct TradeLimitOrderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let store: TradeStore
    let canUseAPI: Bool
    let onSubmittedOrder: (AlpacaOrder) -> Void

    @State private var focusedField: TradeLimitFocusedField = .quantity
    @State private var confirmation: TradeOrderConfirmationSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            TradeLimitTopBar(title: orderTypeTitle) {
                dismiss()
            }
            .padding(.top, 8)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(L10n.Trade.limitSharesAvailable(TradeFormat.quantity(store.positionQuantity), locale: locale))
                        .font(AppTypography.description)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppTheme.Spacing.pageTop)

                VStack(spacing: 0) {
                    TradeLimitInputRow(
                        title: L10n.Trade.limitNumberOfShares(locale: locale),
                        value: quantityDisplayValue,
                        isFocused: focusedField == .quantity
                    ) {
                        focusedField = .quantity
                    }

                    if !limitQuickFillItems.isEmpty {
                        TradeSimpleQuickFillRow(items: limitQuickFillItems, style: .compact) { percent in
                            applyLimitQuickFill(percent)
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                    }

                    TradeLimitDivider()

                    TradeLimitInputRow(
                        title: L10n.Trade.limitPrice(locale: locale),
                        subtitle: L10n.Trade.limitBidAsk(
                            bid: TradeFormat.price(store.bidPrice, currency: store.currencyCode),
                            ask: TradeFormat.price(store.askPrice, currency: store.currencyCode),
                            locale: locale
                        ),
                        value: priceDisplayValue,
                        isFocused: focusedField == .limitPrice,
                        trailingHelp: true
                    ) {
                        focusedField = .limitPrice
                    }

                    priceFillActions
                        .padding(.top, 10)

                    TradeLimitDivider()
                        .padding(.top, 14)

                    TradeLimitSummaryRow(
                        title: store.draft.side == .buy
                            ? L10n.Trade.simpleEstimatedDebit(locale: locale)
                            : L10n.Trade.simpleEstimatedCredit(locale: locale),
                        value: AppFormatter.money(store.estimatedNotional, currencyCode: store.currencyCode)
                    )
                }
                .padding(.top, 18)

                TradeSimpleStatusLine(status: status)
                    .padding(.top, 16)

                Spacer(minLength: 16)

                TradeSimpleInputActionButton(state: limitActionButtonState) {
                    reviewOrder()
                }
                .padding(.bottom, 6)

                TradeNumberPad(action: applyKey(_:))
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            store.message = nil
        }
        .sheet(item: $confirmation) { snapshot in
            TradeOrderConfirmationSheet(snapshot: snapshot) {
                await store.submit(snapshot.order, clientOrderID: snapshot.clientOrderID, app: app)
            } onSubmitted: { order in
                onSubmittedOrder(order)
            }
        }
    }

    private var titleText: String {
        L10n.Trade.limitTitle(
            side: store.draft.side.titleText(locale: locale),
            symbol: store.draft.normalizedSymbol,
            locale: locale
        )
    }

    private var orderTypeTitle: String {
        L10n.Trade.simpleOrderTypeTitle(
            orderType: store.draft.orderType.titleText(locale: locale),
            locale: locale
        )
    }

    private var priceDisplayValue: String {
        let text = displayValue(store.draft.limitPriceText)
        return text == AppFormatter.placeholder ? text : "$\(text)"
    }

    private var canContinue: Bool {
        canUseAPI && store.validation.canSubmit && !store.isLoadingContext && !store.isSubmitting
    }

    private var limitActionButtonState: TradeSimpleInputActionButtonState {
        let tint = store.draft.side.tradeActionTint

        if store.isSubmitting {
            return TradeSimpleInputActionButtonState(
                title: L10n.Trade.simpleSubmitting(locale: locale),
                tint: tint,
                isEnabled: false,
                showsProgress: true
            )
        }

        if !canUseAPI {
            return TradeSimpleInputActionButtonState(
                title: L10n.Trade.addCredentialsBeforeOrder(locale: locale),
                tint: AppTheme.ColorToken.warning,
                isEnabled: false
            )
        }

        if hasRequiredLimitInputs, let issue = store.validation.firstIssue {
            return TradeSimpleInputActionButtonState(
                title: limitActionTitle(for: issue),
                tint: AppTheme.ColorToken.negative,
                isEnabled: false
            )
        }

        return TradeSimpleInputActionButtonState(
            title: L10n.Trade.simpleContinue(locale: locale),
            tint: canContinue ? tint : Color(.secondaryLabel),
            isEnabled: canContinue
        )
    }

    private var status: TradeSimpleStatus? {
        if !canUseAPI {
            return TradeSimpleStatus(
                systemImage: "key",
                text: L10n.Trade.addCredentialsBeforeOrder(locale: locale),
                tint: AppTheme.ColorToken.warning
            )
        }

        if let error = store.validation.errors.first, hasRequiredLimitInputs {
            return TradeSimpleStatus(systemImage: "exclamationmark.triangle.fill", text: error, tint: AppTheme.ColorToken.negative)
        }

        if let warning = store.validation.warnings.first, hasRequiredLimitInputs {
            return TradeSimpleStatus(systemImage: "exclamationmark.circle", text: warning, tint: AppTheme.ColorToken.warning)
        }

        if let message = store.message, hasRequiredLimitInputs {
            return TradeSimpleStatus(systemImage: "info.circle", text: message, tint: AppTheme.ColorToken.icon)
        }

        return nil
    }

    private var hasRequiredLimitInputs: Bool {
        TradeInputFormat.hasPositiveValue(store.draft.quantityText)
            && TradeInputFormat.hasPositiveValue(store.draft.limitPriceText)
    }

    private var quantityDisplayValue: String {
        let normalized = NumberText.trimTrailingZeros(store.draft.quantityText)
        return normalized.isEmpty ? "0" : normalized
    }

    private func displayValue(_ text: String) -> String {
        let normalized = NumberText.trimTrailingZeros(text)
        return normalized.isEmpty ? AppFormatter.placeholder : normalized
    }

    private func reviewOrder() {
        let validation = store.validation
        if validation.canSubmit {
            confirmation = TradeOrderConfirmationSnapshot(store: store, environment: app.environment)
        } else if hasRequiredLimitInputs {
            store.message = validation.errors.first
        } else {
            store.message = nil
        }
    }

    private func limitActionTitle(for issue: TradeValidationIssue) -> String {
        switch issue.kind {
        case .missingInput:
            return L10n.Trade.simpleEnterAmount(locale: locale)
        case .buyExceedsBuyingPower, .shortExceedsBuyingPower:
            return L10n.Trade.simpleInsufficientBuyingPower(locale: locale)
        case .sellExceedsPosition:
            return L10n.Trade.simpleExceedsPosition(locale: locale)
        case .fractionalShortSaleUnsupported:
            return L10n.Trade.simpleShortUnavailable(locale: locale)
        case .generic:
            return L10n.Trade.simpleOrderUnavailable(locale: locale)
        }
    }

    private func applyKey(_ key: TradeNumberPadKey) {
        store.message = nil
        switch focusedField {
        case .quantity:
            store.draft.quantityText = TradeInputFormat.text(
                updatedText(store.draft.quantityText, key: key),
                kind: .quantity
            )
        case .limitPrice:
            store.draft.limitPriceText = TradeInputFormat.text(
                updatedText(store.draft.limitPriceText, key: key),
                kind: .decimal(maxFractionDigits: priceFractionDigits)
            )
        }
    }

    private var priceFractionDigits: Int {
        guard let value = NumberParser.decimal(from: store.draft.limitPriceText) else {
            return 4
        }

        return value >= 1 ? 2 : 4
    }

    private func updatedText(_ text: String, key: TradeNumberPadKey) -> String {
        var value = text
        switch key {
        case .digit(let digit):
            value.append(digit)
        case .decimal:
            guard !value.contains(".") else { return value }
            value.append(".")
        case .backspace:
            guard !value.isEmpty else { return value }
            value.removeLast()
        case .clear:
            value = ""
        }
        return value
    }

    @ViewBuilder
    private var priceFillActions: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                priceFillButtons
            }
        } else {
            priceFillButtons
        }
    }

    private var priceFillButtons: some View {
        HStack(spacing: 10) {
            TradeSmallAction(
                title: L10n.Trade.limitBid(locale: locale),
                tint: Color(.secondaryLabel)
            ) {
                store.fillLimitFromBid()
                focusedField = .limitPrice
            }
            .disabled(store.bidPrice == nil)

            TradeSmallAction(
                title: L10n.Trade.limitMid(locale: locale),
                tint: Color(.secondaryLabel)
            ) {
                store.fillLimitFromMid()
                focusedField = .limitPrice
            }
            .disabled(store.lastPrice == nil)

            TradeSmallAction(
                title: L10n.Trade.limitAsk(locale: locale),
                tint: Color(.secondaryLabel)
            ) {
                store.fillLimitFromAsk()
                focusedField = .limitPrice
            }
            .disabled(store.askPrice == nil)

            Spacer(minLength: 0)
        }
    }

    private var limitQuickFillItems: [TradeSimpleQuickFillItem] {
        guard let base = limitQuickFillBase, base > 0 else {
            return []
        }

        return [
            TradeSimpleQuickFillItem(title: "25%", percent: Decimal(string: "0.25")!),
            TradeSimpleQuickFillItem(title: "50%", percent: Decimal(string: "0.50")!),
            TradeSimpleQuickFillItem(title: L10n.Trade.simpleMax(locale: locale), percent: Decimal(string: "1.0")!)
        ]
    }

    private var limitQuickFillBase: Decimal? {
        switch store.draft.side {
        case .buy:
            guard let buyingPower = store.buyingPower,
                  let price = store.estimatedExecutionPrice,
                  price > 0 else {
                return nil
            }
            return buyingPower / price
        case .sell:
            return store.sellQuickFillQuantityBase
        }
    }

    private func applyLimitQuickFill(_ percent: Decimal) {
        store.message = nil
        store.fillQuantity(percent: percent)
        focusedField = .quantity
    }
}

private struct TradeLimitTopBar: View {
    let title: String
    let back: () -> Void

    var body: some View {
        AppScreenHeader(background: AppTheme.ColorToken.pageBackground) {
            AppGlassIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: L10n.Common.back,
                action: back
            )
        } center: {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

private struct TradeLimitInputRow: View {
    let title: String
    var subtitle: String?
    let value: String
    let isFocused: Bool
    var trailingHelp = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(AppTypography.description)
                            .foregroundStyle(.primary)

                        if trailingHelp {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.brandDark)
                        }
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                Spacer(minLength: 10)

                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(value == AppFormatter.placeholder ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if isFocused {
                    TradeLimitBlinkingCursor()
                }
            }
            .frame(minHeight: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TradeLimitBlinkingCursor: View {
    @State private var isVisible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(AppTheme.ColorToken.brandDark)
            .frame(width: 2, height: 28)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                isVisible = true
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
            .onDisappear {
                isVisible = true
            }
    }
}

private struct TradeLimitSummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppTypography.description)
                .foregroundStyle(.primary)

            Spacer(minLength: 10)

            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(value == AppFormatter.placeholder ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minHeight: 64)
    }
}

private struct TradeLimitDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.22))
            .frame(height: 0.5)
    }
}

private struct TradeSimpleView: View {
    let store: TradeStore
    let canUseAPI: Bool
    let close: () -> Void
    let review: () -> Void
    let showLimitOrder: () -> Void

    @Environment(\.locale) private var locale
    @State private var notionalInputText = ""

    var body: some View {
        VStack(spacing: 0) {
            TradeSimpleTopBar(
                store: store,
                close: close,
                setSizingMode: setSizingMode(_:),
                showLimitOrder: showLimitOrder
            )
            .padding(.top, 8)

            Group {
                if showsSkeleton {
                    TradeSimpleContentSkeleton()
                        .transition(.opacity)
                } else {
                    tradeContent
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 22)
        }
        .animation(.snappy(duration: 0.18), value: showsSkeleton)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: store.estimatedExecutionPrice) { _, _ in
            syncNotionalInputForCurrentOrder()
        }
        .onChange(of: store.draft.orderType) { _, _ in
            syncNotionalInputForCurrentOrder()
        }
        .onChange(of: store.draft.timeInForce) { _, _ in
            syncNotionalInputForCurrentOrder()
        }
    }

    private var showsSkeleton: Bool {
        canUseAPI && store.context == nil && store.message == nil
    }

    private var tradeContent: some View {
        VStack(spacing: 0) {
            TradeSimpleDisplayRegion(
                amountText: primaryAmountText,
                showsCurrencyMark: store.sizingMode == .notional,
                unit: store.sizingMode == .shares ? L10n.Trade.simpleShares(locale: locale) : nil
            )
            .padding(.top, 46)

            Spacer(minLength: 0)

            TradeSimpleStatusLine(status: status, layout: .centered)
                .padding(.bottom, 10)

            Text(availabilityText)
                .font(AppTypography.description)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.bottom, 14)

            Group {
                if hasAnyInput {
                    TradeSimpleInputActionButton(state: inputActionButtonState) {
                        review()
                    }
                } else {
                    TradeSimpleQuickFillRow(items: quickFillItems) { percent in
                        applyQuickFill(percent)
                    }
                }
            }
            .animation(.snappy(duration: 0.18), value: hasAnyInput)
            .frame(height: 44)
            .padding(.bottom, 6)

            TradeNumberPad(action: applyKey(_:))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeInputText: String {
        switch store.sizingMode {
        case .shares:
            store.draft.quantityText
        case .notional:
            store.supportsNotionalOrder ? store.draft.notionalText : notionalInputText
        }
    }

    private var primaryAmountText: String {
        activeInputText.isEmpty ? "0" : activeInputText
    }

    private var availabilityText: String {
        switch store.draft.side {
        case .buy:
            let value = AppFormatter.money(store.buyingPower, currencyCode: store.currencyCode)
            return L10n.Trade.simpleBuyingPowerAvailable(value, locale: locale)
        case .sell:
            let quantity = TradeFormat.quantity(store.positionQuantity)
            let value = AppFormatter.money(store.positionMarketValue, currencyCode: store.currencyCode)
            return L10n.Trade.simplePositionAvailable(quantity: quantity, value: value, locale: locale)
        }
    }

    private var status: TradeSimpleStatus? {
        if store.isLoadingContext {
            return nil
        }

        if !canUseAPI {
            return TradeSimpleStatus(
                systemImage: "key",
                text: L10n.Trade.addCredentialsBeforeOrder(locale: locale),
                tint: AppTheme.ColorToken.warning
            )
        }

        if hasPositiveInput {
            if let error = store.validation.errors.first {
                return TradeSimpleStatus(systemImage: "exclamationmark.triangle.fill", text: error, tint: AppTheme.ColorToken.negative)
            }

            if let warning = store.validation.warnings.first {
                return TradeSimpleStatus(systemImage: "exclamationmark.circle", text: warning, tint: AppTheme.ColorToken.warning)
            }
        }

        if let message = store.message {
            return TradeSimpleStatus(systemImage: "info.circle", text: message, tint: AppTheme.ColorToken.icon)
        }

        return nil
    }

    private var hasPositiveInput: Bool {
        TradeInputFormat.hasPositiveValue(activeInputText)
    }

    private var hasAnyInput: Bool {
        !activeInputText.isEmpty
    }

    private var inputActionButtonState: TradeSimpleInputActionButtonState {
        let actionTint = store.draft.side.tradeActionTint

        if store.isLoadingContext {
            return TradeSimpleInputActionButtonState(
                title: L10n.Trade.simpleReviewOrder(locale: locale),
                tint: actionTint,
                isEnabled: false
            )
        }

        if store.isSubmitting {
            return TradeSimpleInputActionButtonState(
                title: L10n.Trade.simpleSubmitting(locale: locale),
                tint: actionTint,
                isEnabled: false,
                showsProgress: true
            )
        }

        if !canUseAPI {
            return TradeSimpleInputActionButtonState(
                title: L10n.Trade.addCredentialsBeforeOrder(locale: locale),
                tint: AppTheme.ColorToken.warning,
                isEnabled: false
            )
        }

        if let issue = store.validation.firstIssue {
            return TradeSimpleInputActionButtonState(
                title: actionTitle(for: issue),
                tint: AppTheme.ColorToken.negative,
                isEnabled: false
            )
        }

        return TradeSimpleInputActionButtonState(
            title: L10n.Trade.simpleReviewOrder(locale: locale),
            tint: actionTint,
            isEnabled: true
        )
    }

    private func actionTitle(for issue: TradeValidationIssue) -> String {
        switch issue.kind {
        case .missingInput:
            return L10n.Trade.simpleEnterAmount(locale: locale)
        case .buyExceedsBuyingPower, .shortExceedsBuyingPower:
            return L10n.Trade.simpleInsufficientBuyingPower(locale: locale)
        case .sellExceedsPosition:
            return L10n.Trade.simpleExceedsPosition(locale: locale)
        case .fractionalShortSaleUnsupported:
            return L10n.Trade.simpleShortUnavailable(locale: locale)
        case .generic:
            return L10n.Trade.simpleOrderUnavailable(locale: locale)
        }
    }

    private var quickFillItems: [TradeSimpleQuickFillItem] {
        guard let base = quickFillBase, base > 0 else {
            return []
        }

        return [
            TradeSimpleQuickFillItem(title: "25%", percent: Decimal(string: "0.25")!),
            TradeSimpleQuickFillItem(title: "50%", percent: Decimal(string: "0.50")!),
            TradeSimpleQuickFillItem(title: L10n.Trade.simpleMax(locale: locale), percent: Decimal(string: "1.0")!)
        ]
    }

    private var quickFillBase: Decimal? {
        switch store.sizingMode {
        case .notional:
            switch store.draft.side {
            case .buy:
                return store.buyingPower
            case .sell:
                return store.sellQuickFillNotionalBase
            }
        case .shares:
            switch store.draft.side {
            case .buy:
                guard let buyingPower = store.buyingPower,
                      let price = store.estimatedExecutionPrice,
                      price > 0 else {
                    return nil
                }
                return buyingPower / price
            case .sell:
                return store.sellQuickFillQuantityBase
            }
        }
    }

    private func applyQuickFill(_ percent: Decimal) {
        store.message = nil
        switch store.sizingMode {
        case .shares:
            store.fillQuantity(percent: percent)
        case .notional:
            guard let base = quickFillBase else { return }
            setActiveInputText(roundedDecimalText(base * percent, scale: 2))
        }
    }

    private func applyKey(_ key: TradeNumberPadKey) {
        store.message = nil
        var value = activeInputText

        switch key {
        case .digit(let digit):
            value.append(digit)
        case .decimal:
            guard !value.contains(".") else { return }
            value.append(".")
        case .backspace:
            guard !value.isEmpty else { return }
            value.removeLast()
        case .clear:
            value = ""
        }

        setActiveInputText(value)
    }

    private func setActiveInputText(_ value: String) {
        switch store.sizingMode {
        case .shares:
            store.draft.quantityText = TradeInputFormat.text(value, kind: .quantity)
            notionalInputText = ""
        case .notional:
            let text = TradeInputFormat.text(value, kind: .decimal(maxFractionDigits: 2))
            if store.supportsNotionalOrder {
                store.draft.quantityText = ""
                store.draft.notionalText = text
                notionalInputText = ""
            } else {
                notionalInputText = text
                store.draft.notionalText = ""
                store.draft.quantityText = quantityText(forNotionalText: text)
            }
        }
    }

    private func setSizingMode(_ mode: TradeSizingMode) {
        store.message = nil
        guard store.sizingMode != mode else { return }

        switch mode {
        case .shares:
            if store.sizingMode == .notional {
                store.draft.quantityText = quantityText(forNotionalText: activeInputText)
            }
            store.sizingMode = .shares
            store.draft.notionalText = ""
            notionalInputText = ""
        case .notional:
            let text = notionalTextForCurrentInput()
            store.sizingMode = .notional
            setActiveInputText(text)
        }
    }

    private func syncNotionalInputForCurrentOrder() {
        guard store.sizingMode == .notional else { return }
        let text: String
        if store.supportsNotionalOrder {
            text = notionalInputText.isEmpty ? store.draft.notionalText : notionalInputText
        } else {
            text = notionalInputText.isEmpty ? store.draft.notionalText : notionalInputText
        }
        setActiveInputText(text)
    }

    private func notionalTextForCurrentInput() -> String {
        if store.sizingMode == .notional {
            return activeInputText
        }

        guard let quantity = NumberParser.decimal(from: store.draft.quantityText),
              let price = store.estimatedExecutionPrice,
              price > 0 else {
            return ""
        }

        return roundedDecimalText(quantity * price, scale: 2)
    }

    private func quantityText(forNotionalText text: String) -> String {
        guard let notional = NumberParser.decimal(from: text),
              let price = store.estimatedExecutionPrice,
              price > 0 else {
            return ""
        }

        return TradeInputFormat.text(roundedDecimalText(notional / price, scale: 6), kind: .quantity)
    }

    private func roundedDecimalText(_ value: Decimal, scale: Int) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, scale, .plain)
        return NumberText.trimTrailingZeros(NSDecimalNumber(decimal: rounded).stringValue)
    }
}

private struct TradeSimpleTopBar: View {
    let store: TradeStore
    let close: () -> Void
    let setSizingMode: (TradeSizingMode) -> Void
    let showLimitOrder: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var store = store

        AppScreenHeader(background: AppTheme.ColorToken.pageBackground) {
            AppGlassIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: L10n.Common.back,
                action: close
            )
        } center: {
            Menu {
                Button(L10n.Trade.simpleMarketOrder(locale: locale)) {
                    store.prepareMarketOrder()
                }

                Divider()

                Button(OrderType.limit.titleText(locale: locale)) {
                    showLimitOrder()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(orderTypeTitle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(height: 44)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } trailing: {
            Menu {
                Button(L10n.Trade.simpleDollars(locale: locale)) {
                    setSizingMode(.notional)
                }

                Button(L10n.Trade.simpleShares(locale: locale)) {
                    setSizingMode(.shares)
                }
            } label: {
                HStack(spacing: 5) {
                    Text(sizingModeTitle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ColorToken.brandDark)
                .frame(minWidth: 96, alignment: .trailing)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var sizingModeTitle: String {
        switch store.sizingMode {
        case .shares:
            return L10n.Trade.simpleShares(locale: locale)
        case .notional:
            return L10n.Trade.simpleDollars(locale: locale)
        }
    }

    private var orderTypeTitle: String {
        if store.draft.orderType == .market {
            return L10n.Trade.simpleMarketOrder(locale: locale)
        }

        return L10n.Trade.simpleOrderTypeTitle(
            orderType: store.draft.orderType.titleText(locale: locale),
            locale: locale
        )
    }
}

private struct TradeSimpleDisplayRegion: View {
    let amountText: String
    let showsCurrencyMark: Bool
    let unit: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                TradeSimplePrimaryAmount(
                    text: amountText,
                    showsCurrencyMark: showsCurrencyMark,
                    unit: unit
                )
                .frame(width: proxy.size.width)
                .position(x: proxy.size.width / 2, y: 130)
            }
        }
        .frame(height: 292)
    }
}

private struct TradeSimplePrimaryAmount: View {
    let text: String
    let showsCurrencyMark: Bool
    let unit: String?

    var body: some View {
        VStack(spacing: 8) {
            amountLine

            if let unit {
                Text(unit)
                    .font(AppTypography.control)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var amountLine: some View {
        HStack(alignment: .top, spacing: 2) {
            if showsCurrencyMark {
                Text("$")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.top, 9)
            }

            Text(text)
                .font(.system(size: 78, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct TradeSimpleInputActionButtonState {
    let title: String
    let tint: Color
    let isEnabled: Bool
    var showsProgress = false
}

private struct TradeSimpleInputActionButton: View {
    let state: TradeSimpleInputActionButtonState
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                button(usesGlass: true)
            }
        } else {
            button(usesGlass: false)
        }
    }

    @ViewBuilder
    private func button(usesGlass: Bool) -> some View {
        let button = Button(action: action) {
            HStack(spacing: 8) {
                if state.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(state.title)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }
            .foregroundStyle(state.tint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!state.isEnabled)

        if usesGlass {
            if #available(iOS 26.0, *) {
                button
                    .glassEffect(
                        .regular.tint(state.tint.opacity(state.isEnabled ? 0.22 : 0.12)).interactive(state.isEnabled),
                        in: .capsule
                    )
            } else {
                button
            }
        } else {
            button
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(state.tint.opacity(state.isEnabled ? 0.30 : 0.18), lineWidth: 0.75)
                }
        }
    }
}

private struct TradeSimpleQuickFillRow: View {
    enum Style {
        case regular
        case compact

        var height: CGFloat {
            switch self {
            case .regular:
                38
            case .compact:
                28
            }
        }

        var spacing: CGFloat {
            switch self {
            case .regular:
                10
            case .compact:
                8
            }
        }

        var width: CGFloat? {
            switch self {
            case .regular:
                nil
            case .compact:
                68
            }
        }

        var alignment: Alignment {
            switch self {
            case .regular:
                .center
            case .compact:
                .trailing
            }
        }

        var font: Font {
            switch self {
            case .regular:
                .subheadline.weight(.bold).monospacedDigit()
            case .compact:
                .caption.weight(.bold).monospacedDigit()
            }
        }

        var tint: Color {
            switch self {
            case .regular:
                AppTheme.ColorToken.brandDark
            case .compact:
                Color(.secondaryLabel)
            }
        }

        var glassTintOpacity: Double {
            switch self {
            case .regular:
                0.16
            case .compact:
                0.08
            }
        }

        var strokeOpacity: Double {
            switch self {
            case .regular:
                0.22
            case .compact:
                0.14
            }
        }
    }

    let items: [TradeSimpleQuickFillItem]
    var style: Style = .regular
    let action: (Decimal) -> Void

    var body: some View {
        Group {
            if !items.isEmpty {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: style.spacing) {
                        quickFillButtons(usesGlass: true)
                    }
                } else {
                    quickFillButtons(usesGlass: false)
                }
            }
        }
        .frame(minHeight: items.isEmpty ? 0 : style.height)
    }

    private func quickFillButtons(usesGlass: Bool) -> some View {
        HStack(spacing: style.spacing) {
            ForEach(items) { item in
                quickFillButton(item, usesGlass: usesGlass)
            }
        }
        .frame(maxWidth: .infinity, alignment: style.alignment)
    }

    @ViewBuilder
    private func quickFillButton(_ item: TradeSimpleQuickFillItem, usesGlass: Bool) -> some View {
        let button = Button {
            action(item.percent)
        } label: {
            Text(item.title)
                .font(style.font)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(style.tint)
                .frame(width: style.width)
                .frame(maxWidth: style.width == nil ? .infinity : nil)
                .frame(height: style.height)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)

        if usesGlass {
            if #available(iOS 26.0, *) {
                button
                    .glassEffect(
                        .regular.tint(style.tint.opacity(style.glassTintOpacity)).interactive(),
                        in: .capsule
                    )
            } else {
                button
            }
        } else {
            button
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(style.tint.opacity(style.strokeOpacity), lineWidth: 0.75)
                }
        }
    }
}

private struct TradeSimpleQuickFillItem: Identifiable {
    let title: String
    let percent: Decimal

    var id: String {
        "\(title)-\(percent)"
    }
}

private enum TradeSimpleStatusLineLayout: Equatable {
    case leading
    case centered
}

private struct TradeSimpleStatusLine: View {
    let status: TradeSimpleStatus?
    var layout: TradeSimpleStatusLineLayout = .leading

    var body: some View {
        Group {
            if let status {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: status.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(status.tint)
                        .frame(width: 18, height: 18)

                    Text(status.text)
                        .font(AppTypography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(layout == .centered ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if layout == .leading {
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: layout == .centered ? .center : .topLeading)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: layout == .centered ? .center : .topLeading)
    }
}

private struct TradeSimpleStatus {
    let systemImage: String
    let text: String
    let tint: Color
}

private enum TradeNumberPadKey: Identifiable, Equatable {
    case digit(String)
    case decimal
    case backspace
    case clear

    var id: String {
        switch self {
        case .digit(let value):
            return value
        case .decimal:
            return "decimal"
        case .backspace:
            return "backspace"
        case .clear:
            return "clear"
        }
    }
}

private struct TradeNumberPad: View {
    let action: (TradeNumberPadKey) -> Void

    @Environment(\.locale) private var locale

    private let rows: [[TradeNumberPadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.decimal, .digit("0"), .backspace]
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 10) {
                    ForEach(rows[rowIndex]) { key in
                        Button {
                            action(key)
                        } label: {
                            TradeNumberPadKeyLabel(key: key)
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: key))
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.45)
                                .onEnded { _ in
                                    guard key == .backspace else { return }
                                    action(.clear)
                                }
                        )
                    }
                }
            }
        }
    }

    private func accessibilityLabel(for key: TradeNumberPadKey) -> String {
        switch key {
        case .digit(let value):
            return value
        case .decimal:
            return L10n.Trade.simpleDecimalPoint(locale: locale)
        case .backspace:
            return L10n.Trade.simpleDelete(locale: locale)
        case .clear:
            return L10n.Trade.simpleDelete(locale: locale)
        }
    }
}

private struct TradeNumberPadKeyLabel: View {
    let key: TradeNumberPadKey

    var body: some View {
        Group {
            switch key {
            case .digit(let value):
                Text(value)
                    .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
            case .decimal:
                Text(".")
                    .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
            case .backspace:
                Image(systemName: "delete.left")
                    .font(.system(size: 24, weight: .semibold))
            case .clear:
                Image(systemName: "delete.left")
                    .font(.system(size: 24, weight: .semibold))
            }
        }
        .foregroundStyle(AppTheme.ColorToken.brandDark)
    }
}

private struct TradeSmallAction: View {
    let title: String
    let tint: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if #available(iOS 26.0, *) {
            button
                .glassEffect(
                    .regular.tint(tint.opacity(isEnabled ? 0.08 : 0.05)).interactive(isEnabled),
                    in: .capsule
                )
        } else {
            button
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(foreground.opacity(0.16), lineWidth: 0.8)
                }
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 76, height: 30)
                .foregroundStyle(foreground)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        isEnabled ? tint : Color(.secondaryLabel)
    }
}

private struct TradeGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.14)).interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(0.18))
                }
                .shadow(color: .black.opacity(0.10), radius: 14, y: 5)
        }
    }
}

private extension View {
    func tradeGlassCapsule() -> some View {
        modifier(TradeGlassCapsuleModifier())
    }
}

private enum TradeFormat {
    static func price(_ value: Decimal?, currency: String) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        let absValue = abs(NSDecimalNumber(decimal: value).doubleValue)
        let fractionLength = absValue > 0 && absValue < 1 ? 4 : 2
        return AppFormatter.money(value, currencyCode: currency, fractionLength: fractionLength)
    }

    static func quantity(_ value: Decimal) -> String {
        let text = NSDecimalNumber(decimal: value).stringValue
        let normalized = NumberText.trimTrailingZeros(text)
        return normalized.isEmpty ? "0" : normalized
    }
}

private enum TradeInputKind {
    case quantity
    case decimal(maxFractionDigits: Int)
}

private enum TradeInputFormat {
    static func text(_ value: String, kind: TradeInputKind) -> String {
        switch kind {
        case .quantity:
            return normalizedDecimal(value, maxFractionDigits: 6, inputPattern: #"^\d+(?:\.\d{0,6})?$"#)
        case .decimal(let maxFractionDigits):
            return normalizedDecimal(value, maxFractionDigits: maxFractionDigits, inputPattern: #"^\d+(?:\.\d{0,\#(maxFractionDigits)})?$"#)
        }
    }

    static func hasPositiveValue(_ value: String) -> Bool {
        guard let decimal = NumberParser.decimal(from: NumberText.trimTrailingZeros(value)) else {
            return false
        }

        return decimal > 0
    }

    private static func normalizedDecimal(_ value: String, maxFractionDigits: Int, inputPattern: String) -> String {
        let digitText = value.replacingOccurrences(
            of: #"[^0-9.]"#,
            with: "",
            options: .regularExpression
        )
        var result = ""
        var hasDecimalSeparator = false

        for character in digitText {
            if let scalar = character.unicodeScalars.first, scalar.value >= 48, scalar.value <= 57 {
                result.append(character)
            } else if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                result.append(character)
            }
        }

        guard !result.isEmpty else {
            return ""
        }

        let normalized: String
        if let separatorIndex = result.firstIndex(of: ".") {
            var integerPart = String(result[..<separatorIndex])
            let rawFractionPart = String(result[result.index(after: separatorIndex)...])
            let fractionPart = String(rawFractionPart.prefix(maxFractionDigits))
            integerPart = normalizedInteger(integerPart)
            normalized = "\(integerPart).\(fractionPart)"
        } else {
            normalized = normalizedInteger(result)
        }

        guard normalized.range(of: inputPattern, options: .regularExpression) != nil else {
            return ""
        }
        return normalized
    }

    private static func normalizedInteger(_ value: String) -> String {
        let trimmed = value.drop { $0 == "0" }
        if trimmed.isEmpty {
            return value.isEmpty ? "0" : "0"
        }
        return String(trimmed)
    }
}

#Preview {
    NavigationStack {
        TradeView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
