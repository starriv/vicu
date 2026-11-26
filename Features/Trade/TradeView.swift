import Observation
import SwiftUI
import UIKit

struct TradeView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var store: TradeStore
    @State private var confirmation: TradeOrderConfirmationSnapshot?

    private let submittedOrderHandler: ((AlpacaOrder) -> Void)?

    init(
        symbol: String? = nil,
        side: OrderSide = .buy,
        seed: TradeSeedContext? = nil,
        onSubmittedOrder: ((AlpacaOrder) -> Void)? = nil
    ) {
        let defaultSizingMode: TradeSizingMode = {
            if seed?.asset?.fractionable == false {
                return .shares
            }
            if side == .sell, (NumberParser.decimal(from: seed?.position?.quantity) ?? 0) <= 0 {
                return .shares
            }
            return .notional
        }()

        _store = State(initialValue: TradeStore(
            symbol: symbol,
            side: side,
            orderType: .market,
            sizingMode: defaultSizingMode,
            seed: seed
        ))
        submittedOrderHandler = onSubmittedOrder
    }

    var body: some View {
        TradeSimpleView(
            store: store,
            canUseAPI: app.canUseAlpacaAPI,
            environment: app.environment,
            close: { dismiss() },
            review: reviewOrder
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
            guard confirmation == nil else {
                return
            }

            store.stopPolling()
        }
        .sheet(item: $confirmation) { snapshot in
            TradeOrderConfirmationSheet(snapshot: snapshot) {
                await store.submit(snapshot.order, clientOrderID: snapshot.clientOrderID, confirmedEnvironment: snapshot.environment, app: app)
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

    private func showSubmittedOrder(_ order: AlpacaOrder) {
        if let submittedOrderHandler {
            store.stopPolling()
            submittedOrderHandler(order)
            return
        }

        store.stopPolling()
        dismiss()
    }

    private func showErrorMessage(_ message: String?) {
        guard let message else {
            return
        }

        toastCenter.showErrorMessage(message)
    }
}

// MARK: - Unified Trade Simple & Limit Container

private struct TradeSimpleView: View {
    let store: TradeStore
    let canUseAPI: Bool
    let environment: TradeEnvironment
    let close: () -> Void
    let review: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TradeSimpleTopBar(
                store: store,
                close: close
            )
            .padding(.top, 4)

            Group {
                if showsSkeleton {
                    TradeSimpleContentSkeleton()
                        .transition(.opacity)
                } else {
                    TradeOrderModeHost(
                        store: store,
                        canUseAPI: canUseAPI,
                        environment: environment,
                        review: review
                    )
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
        }
        .animation(.snappy(duration: 0.16), value: showsSkeleton)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var showsSkeleton: Bool {
        canUseAPI && store.normalizedSymbol.isEmpty && store.context == nil && store.isLoadingContext
    }
}

private struct TradeOrderModeHost: View {
    let store: TradeStore
    let canUseAPI: Bool
    let environment: TradeEnvironment
    let review: () -> Void

    var body: some View {
        Group {
            switch store.draft.orderType {
            case .market:
                TradeMarketContentLayout(
                    store: store,
                    canUseAPI: canUseAPI,
                    environment: environment,
                    review: review
                )
                .transition(.opacity)
            case .limit:
                TradeLimitContentLayout(
                    store: store,
                    canUseAPI: canUseAPI,
                    review: review
                )
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: store.draft.orderType)
    }
}

private struct TradeSimpleTopBar: View {
    let store: TradeStore
    let close: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        AppScreenHeader(background: AppTheme.ColorToken.pageBackground) {
            AppGlassIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: L10n.Common.back,
                action: close
            )
        } center: {
            EmptyView()
        } trailing: {
            Menu {
                Button {
                    TradeKeypadHaptics.selection()
                    store.prepareMarketOrder()
                } label: {
                    if store.draft.orderType == .market {
                        Label(L10n.Trade.simpleMarketOrder(locale: locale), systemImage: "checkmark")
                    } else {
                        Text(L10n.Trade.simpleMarketOrder(locale: locale))
                    }
                }

                Button {
                    TradeKeypadHaptics.selection()
                    store.prepareLimitOrder()
                } label: {
                    let limitTitle = L10n.Trade.simpleOrderTypeTitle(
                        orderType: OrderType.limit.titleText(locale: locale),
                        locale: locale
                    )
                    if store.draft.orderType == .limit {
                        Label(limitTitle, systemImage: "checkmark")
                    } else {
                        Text(limitTitle)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(orderTypeTitle)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(AppTheme.ColorToken.groupedSurface, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(0.18), lineWidth: 0.75)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
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

// MARK: - OKX Simple Mode Market Order Layout

/// Isolates `@Observable` reads into focused child views so `TradeNumberPad`
/// and static chrome never re-evaluate on keystrokes or quote ticks.
private struct TradeMarketContentLayout: View {
    let store: TradeStore
    let canUseAPI: Bool
    let environment: TradeEnvironment
    let review: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            TradeSimpleHeroInput(store: store, canUseAPI: canUseAPI)

            Spacer(minLength: 16)

            TradeSimpleOrderCard(store: store)
                .padding(.bottom, 12)

            TradeSimpleQuickFillSection(store: store)
                .padding(.bottom, 10)

            TradeSimpleActionSection(
                store: store,
                canUseAPI: canUseAPI,
                review: review
            )
            .padding(.bottom, 8)

            TradeNumberPad(action: handleMarketKey(_:))
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleMarketKey(_ key: TradeNumberPadKey) {
        let current = store.activeInputText
        let updated: String
        switch store.sizingMode {
        case .notional:
            updated = TradeInputFormat.applyKey(
                key,
                to: current,
                maxIntegerDigits: TradeInputLimit.notionalMaxIntegerDigits,
                maxFractionDigits: 2,
                maxTotalDigits: TradeInputLimit.notionalMaxTotalDigits
            )
        case .shares:
            updated = TradeInputFormat.applyKey(
                key,
                to: current,
                maxIntegerDigits: TradeInputLimit.sharesMaxIntegerDigits,
                maxFractionDigits: store.maxShareInputScale,
                maxTotalDigits: TradeInputLimit.sharesMaxTotalDigits
            )
        }
        guard updated != current else { return }
        store.setSimpleInputText(updated)
    }
}

private struct TradeSimpleHeroInput: View {
    let store: TradeStore
    let canUseAPI: Bool

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let swapDirection: CGFloat = store.sizingMode == .shares ? 1 : -1

        VStack(alignment: .center, spacing: 14) {
            ZStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formattedPrimaryText)
                        .font(.system(size: primaryFontSize, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .overlay(alignment: .trailing) {
                            TradeBlinkingCursor(
                                color: store.draft.side.tradeActionTint,
                                width: 2.5,
                                height: cursorHeight
                            )
                            .offset(x: 5)
                        }
                        .padding(.trailing, 6)

                    Text(primaryUnitLabel)
                        .font(.system(size: unitFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .id(store.sizingMode)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10 * swapDirection)),
                        removal: .opacity.combined(with: .offset(y: -10 * swapDirection))
                    )
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84, alignment: .center)
            .clipped()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(formattedPrimaryText) \(primaryUnitLabel)")

            Button {
                guard canToggleSizingMode else { return }
                TradeKeypadHaptics.selection()
                withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                    store.toggleSizingMode()
                }
            } label: {
                HStack(spacing: 7) {
                    if canToggleSizingMode {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(adaptiveAccentColor)
                            .rotationEffect(.degrees(store.sizingMode == .shares ? 180 : 0))
                    }

                    ZStack {
                        Text(secondaryEstimateText)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(canToggleSizingMode ? .primary : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .id(store.sizingMode)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -7 * swapDirection)),
                                    removal: .opacity.combined(with: .offset(y: 7 * swapDirection))
                                )
                            )
                    }
                    .frame(height: 22)
                    .clipped()
                }
                .padding(.horizontal, 16)
                .frame(minWidth: 168, minHeight: 36, maxHeight: 36)
                .background(
                    AppTheme.ColorToken.groupedSurface,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            Color(.separator).opacity(canToggleSizingMode ? 0.20 : 0.10),
                            lineWidth: 0.75
                        )
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canToggleSizingMode)
            .accessibilityLabel(L10n.Trade.simpleSwitchUnit(locale: locale))
            .accessibilityValue(secondaryEstimateText)

            TradeInlineStatusStrip(status: status, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 4)
    }

    private var adaptiveAccentColor: Color {
        colorScheme == .light
            ? Color(red: 0.70, green: 0.51, blue: 0.0)
            : AppTheme.ColorToken.brandDark
    }

    private var rawInputText: String {
        store.activeInputText
    }

    private var formattedPrimaryText: String {
        TradeInputFormat.formattedDisplay(rawInputText)
    }

    private var primaryFontSize: CGFloat {
        switch formattedPrimaryText.count {
        case 0...5:
            return 68
        case 6...7:
            return 56
        case 8...10:
            return 44
        default:
            return 34
        }
    }

    private var unitFontSize: CGFloat {
        switch formattedPrimaryText.count {
        case 0...5:
            return 32
        case 6...7:
            return 28
        case 8...10:
            return 24
        default:
            return 20
        }
    }

    private var cursorHeight: CGFloat {
        round(primaryFontSize * 0.80)
    }

    private var primaryUnitLabel: String {
        switch store.sizingMode {
        case .notional:
            return store.currencyCode
        case .shares:
            let symbol = store.normalizedSymbol
            return symbol.isEmpty ? L10n.Trade.simpleShares(locale: locale) : symbol
        }
    }

    private var canToggleSizingMode: Bool {
        switch store.sizingMode {
        case .notional:
            return true
        case .shares:
            guard store.canUseNotionalSizing else { return false }
            if store.draft.side == .sell, store.availableSellQuantity <= 0 {
                return false
            }
            return true
        }
    }

    private var secondaryEstimateText: String {
        let symbol = store.normalizedSymbol.isEmpty
            ? L10n.Trade.simpleShares(locale: locale)
            : store.normalizedSymbol

        switch store.sizingMode {
        case .notional:
            guard TradeInputFormat.hasPositiveValue(rawInputText) else {
                return "≈ 0 \(symbol)"
            }
            guard let estimatedQty = store.estimatedQuantity, estimatedQty > 0 else {
                return "≈ \(AppFormatter.placeholder) \(symbol)"
            }
            return "≈ \(TradeFormat.quantity(estimatedQty)) \(symbol)"
        case .shares:
            guard TradeInputFormat.hasPositiveValue(rawInputText) else {
                return "≈ \(AppFormatter.money(Decimal.zero, currencyCode: store.currencyCode))"
            }
            guard let estimatedNotional = store.estimatedNotional, estimatedNotional > 0 else {
                return "≈ \(AppFormatter.placeholder)"
            }
            return "≈ \(AppFormatter.money(estimatedNotional, currencyCode: store.currencyCode))"
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

        if TradeInputFormat.hasPositiveValue(rawInputText) {
            if let error = store.validation.errors.first {
                return TradeSimpleStatus(
                    systemImage: "exclamationmark.triangle.fill",
                    text: error,
                    tint: AppTheme.ColorToken.negative
                )
            }

            if let warning = store.validation.warnings.first {
                return TradeSimpleStatus(
                    systemImage: "exclamationmark.circle",
                    text: warning,
                    tint: AppTheme.ColorToken.warning
                )
            }
        }

        if let message = store.message {
            return TradeSimpleStatus(
                systemImage: "info.circle",
                text: message,
                tint: AppTheme.ColorToken.icon
            )
        }

        return nil
    }
}

private struct TradeSimpleOrderCard: View {
    let store: TradeStore

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            assetRow
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            Rectangle()
                .fill(Color(.separator).opacity(0.18))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            fundingRow
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            if store.canToggleMarginMode {
                Rectangle()
                    .fill(Color(.separator).opacity(0.18))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)

                marginToggleRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(
            AppTheme.ColorToken.groupedSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.14), lineWidth: 0.75)
        }
    }

    private var assetRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(store.draft.side.titleText(locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(store.draft.side.tradeActionTint)

                    Text(store.normalizedSymbol)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .lineLimit(1)

                Text(store.assetDisplayName)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(TradeFormat.price(store.estimatedExecutionPrice, currency: store.currencyCode))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(priceSourceLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var fundingRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fundingTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let fundingSubtitle {
                    Text(fundingSubtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(fundingPrimaryValue)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let fundingSecondaryValue {
                    Text(fundingSecondaryValue)
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private var priceSourceLabel: String {
        switch store.estimatedExecutionPriceSource {
        case .ask:
            return L10n.Trade.simplePriceSourceAsk(locale: locale)
        case .bid:
            return L10n.Trade.simplePriceSourceBid(locale: locale)
        case .last:
            return L10n.Trade.simplePriceSourceLast(locale: locale)
        case .limit, .none:
            return L10n.Trade.simpleEstimatedPrice(locale: locale)
        }
    }

    private var marginToggleRow: some View {
        HStack(spacing: 12) {
            Text(
                store.draft.side == .buy
                    ? L10n.Trade.marginToggleBuy(locale: locale)
                    : L10n.Trade.marginToggleSell(locale: locale)
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(store.isMarginEnabled ? AppTheme.ColorToken.warning : .secondary)
            .lineLimit(1)

            Spacer(minLength: 8)

            Toggle(
                "",
                isOn: Binding(
                    get: { store.isMarginEnabled },
                    set: { enabled in
                        TradeKeypadHaptics.selection()
                        store.setMarginEnabled(enabled)
                    }
                )
            )
            .labelsHidden()
            .tint(AppTheme.ColorToken.warning)
        }
    }

    private var fundingTitle: String {
        switch store.draft.side {
        case .buy:
            return store.isMarginEnabled
                ? L10n.Trade.simpleMarginBuyingPower(locale: locale)
                : L10n.Trade.simpleCashBuyingPower(locale: locale)
        case .sell:
            return store.isShortSellModeActive
                ? L10n.Trade.simpleShortBuyingPower(locale: locale)
                : L10n.Trade.simpleAvailablePosition(locale: locale)
        }
    }

    private var fundingSubtitle: String? {
        if !store.supportsFractionalShares {
            return L10n.Trade.simpleWholeSharesOnly(locale: locale)
        }
        return nil
    }

    private var fundingPrimaryValue: String {
        switch store.draft.side {
        case .buy:
            return AppFormatter.money(store.effectiveBuyingPower, currencyCode: store.currencyCode)
        case .sell:
            if store.isShortSellModeActive {
                return AppFormatter.money(store.accountBuyingPower, currencyCode: store.currencyCode)
            }
            let qty = TradeFormat.quantity(store.availableSellQuantity)
            let symbol = store.normalizedSymbol
            return symbol.isEmpty ? qty : "\(qty) \(symbol)"
        }
    }

    private var fundingSecondaryValue: String? {
        if store.draft.side == .sell, store.availableSellQuantity > 0 {
            return "≈ \(AppFormatter.money(store.availableSellMarketValue, currencyCode: store.currencyCode))"
        }
        return nil
    }
}

private struct TradeSimpleQuickFillSection: View {
    let store: TradeStore

    @Environment(\.locale) private var locale

    var body: some View {
        TradeSimpleQuickFillRow(
            items: quickFillItems,
            selectedPercent: store.activeQuickFillPercent,
            isDisabled: !store.quickFillAvailable
        ) { percent in
            TradeKeypadHaptics.selection()
            store.fillQuickAmount(percent: percent)
        }
    }

    private var quickFillItems: [TradeSimpleQuickFillItem] {
        [
            TradeSimpleQuickFillItem(title: "25%", percent: Decimal(string: "0.25")!),
            TradeSimpleQuickFillItem(title: "50%", percent: Decimal(string: "0.50")!),
            TradeSimpleQuickFillItem(title: "75%", percent: Decimal(string: "0.75")!),
            TradeSimpleQuickFillItem(title: L10n.Trade.simpleMax(locale: locale), percent: Decimal(string: "1.0")!)
        ]
    }
}

private struct TradeSimpleActionSection: View {
    let store: TradeStore
    let canUseAPI: Bool
    let review: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        TradeSimpleActionButton(state: buttonState, action: review)
    }

    private var buttonState: TradeSimpleActionButtonState {
        let actionTint = store.draft.side.tradeActionTint

        if store.isLoadingContext {
            return TradeSimpleActionButtonState(
                title: L10n.Trade.simpleReviewOrder(locale: locale),
                tint: actionTint,
                isEnabled: false
            )
        }

        if store.isSubmitting {
            return TradeSimpleActionButtonState(
                title: L10n.Trade.simpleSubmitting(locale: locale),
                tint: actionTint,
                isEnabled: false,
                showsProgress: true
            )
        }

        if !canUseAPI {
            return TradeSimpleActionButtonState(
                title: L10n.Trade.addCredentialsBeforeOrder(locale: locale),
                tint: AppTheme.ColorToken.warning,
                isEnabled: false,
                isError: true
            )
        }

        let hasInput = !store.activeInputText.isEmpty
        if hasInput, let issue = store.validation.firstIssue {
            return TradeSimpleActionButtonState(
                title: TradeValidationActionTitle.title(for: issue, locale: locale),
                tint: AppTheme.ColorToken.negative,
                isEnabled: false,
                isError: issue.kind != .missingInput
            )
        }

        return TradeSimpleActionButtonState(
            title: L10n.Trade.simpleReviewOrder(locale: locale),
            tint: actionTint,
            isEnabled: store.validation.canSubmit
        )
    }
}

// MARK: - Refactored OKX-Style Limit Order Layout

private enum TradeLimitFocusedField: Equatable {
    case quantity
    case limitPrice
}

@MainActor
@Observable
private final class TradeLimitFocusController {
    var focusedField: TradeLimitFocusedField = .quantity
    var replaceLimitPriceOnNextDigit = false

    func focusLimitPrice(selectForReplacement: Bool = true) {
        let wasAlreadyFocused = focusedField == .limitPrice
        focusedField = .limitPrice
        if selectForReplacement, !wasAlreadyFocused {
            replaceLimitPriceOnNextDigit = true
        }
    }

    func focusQuantity() {
        focusedField = .quantity
        replaceLimitPriceOnNextDigit = false
    }

    func commitLimitPriceEdit() {
        focusedField = .limitPrice
        replaceLimitPriceOnNextDigit = false
    }
}

/// Fine-grained limit order layout: none of the volatile `@Observable` fields
/// are read directly in this `body`, keeping `TradeNumberPad` completely immune
/// to keystroke and 120ms quote-tick invalidations.
private struct TradeLimitContentLayout: View {
    let store: TradeStore
    let canUseAPI: Bool
    let review: () -> Void

    @State private var focusState = TradeLimitFocusController()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    TradeLimitAssetHeader(store: store)
                        .padding(.top, 10)
                        .padding(.bottom, 2)

                    TradeLimitPriceCard(store: store, focusState: focusState)

                    TradeLimitQuantityCard(store: store, focusState: focusState)

                    TradeLimitOptionsBar(store: store)

                    TradeLimitStatusSection(store: store, canUseAPI: canUseAPI)
                }
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            TradeLimitActionSection(
                store: store,
                canUseAPI: canUseAPI,
                review: review
            )
            .padding(.top, 4)
            .padding(.bottom, 10)

            TradeNumberPad(action: handleLimitKey(_:))
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleLimitKey(_ key: TradeNumberPadKey) {
        switch focusState.focusedField {
        case .quantity:
            let current = store.draft.quantityText
            let updated = TradeInputFormat.applyKey(
                key,
                to: current,
                maxIntegerDigits: TradeInputLimit.sharesMaxIntegerDigits,
                maxFractionDigits: store.maxShareInputScale,
                maxTotalDigits: TradeInputLimit.sharesMaxTotalDigits
            )
            guard updated != current else { return }
            store.setLimitQuantityText(updated)

        case .limitPrice:
            let current = store.draft.limitPriceText
            let shouldReplace = focusState.replaceLimitPriceOnNextDigit
            let baseText: String
            switch key {
            case .digit, .decimal:
                baseText = shouldReplace ? "" : current
            case .backspace, .clear:
                baseText = current
            }
            focusState.replaceLimitPriceOnNextDigit = false

            let maxDecimals = priceFractionDigits(for: baseText)
            let updated = TradeInputFormat.applyKey(
                key,
                to: baseText,
                maxIntegerDigits: TradeInputLimit.priceMaxIntegerDigits,
                maxFractionDigits: maxDecimals,
                maxTotalDigits: TradeInputLimit.priceMaxTotalDigits
            )
            guard updated != current else { return }
            store.setLimitPriceText(updated)
        }
    }

    private func priceFractionDigits(for text: String) -> Int {
        guard let value = NumberParser.decimal(from: text) else {
            return 4
        }
        return value >= 1 ? 2 : 4
    }
}

private struct TradeLimitAssetHeader: View {
    let store: TradeStore

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            SymbolLogoView(symbol: store.normalizedSymbol, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.draft.side.titleText(locale: locale))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(store.draft.side.tradeActionTint)

                    Text(store.normalizedSymbol)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .lineLimit(1)

                Text(
                    L10n.Trade.limitMarketPrice(
                        TradeFormat.price(store.marketReferencePrice, currency: store.currencyCode),
                        locale: locale
                    )
                )
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(availablePrimaryValue)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(availableLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
    }

    private var availableLabel: String {
        switch store.draft.side {
        case .buy:
            return store.isMarginEnabled
                ? L10n.Trade.simpleMarginBuyingPower(locale: locale)
                : L10n.Trade.simpleCashBuyingPower(locale: locale)
        case .sell:
            return store.isShortSellModeActive
                ? L10n.Trade.simpleShortBuyingPower(locale: locale)
                : L10n.Trade.simpleAvailablePosition(locale: locale)
        }
    }

    private var availablePrimaryValue: String {
        switch store.draft.side {
        case .buy:
            return AppFormatter.money(store.effectiveBuyingPower, currencyCode: store.currencyCode)
        case .sell:
            if store.isShortSellModeActive {
                return AppFormatter.money(store.accountBuyingPower, currencyCode: store.currencyCode)
            }
            let qty = TradeFormat.quantity(store.availableSellQuantity)
            let symbol = store.normalizedSymbol
            return symbol.isEmpty ? qty : "\(qty) \(symbol)"
        }
    }
}

private struct TradeLimitPriceCard: View {
    let store: TradeStore
    let focusState: TradeLimitFocusController

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(L10n.Trade.limitPrice(locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFocused ? .primary : .secondary)

                Spacer(minLength: 8)

                if let deltaInfo = priceDeltaDisplay {
                    Text(deltaInfo.text)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(deltaInfo.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(deltaInfo.tint.opacity(0.12), in: Capsule())
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 22)

            HStack(spacing: 12) {
                TradeLimitStepperButton(
                    systemImage: "minus",
                    accessibilityLabel: L10n.Trade.limitDecreasePrice(locale: locale)
                ) {
                    TradeKeypadHaptics.keyTap()
                    focusState.commitLimitPriceEdit()
                    store.stepLimitPrice(steps: -1)
                }
                .disabled(!canStepPrice)

                Button {
                    TradeKeypadHaptics.selection()
                    focusState.focusLimitPrice(selectForReplacement: !store.draft.limitPriceText.isEmpty)
                } label: {
                    HStack(alignment: .center, spacing: 3) {
                        Text("$")
                            .font(.system(size: priceCurrencyFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(hasPrice ? .secondary : Color(.tertiaryLabel))
                            .fixedSize(horizontal: true, vertical: false)

                        Text(priceDisplayText)
                            .font(.system(size: priceFontSize, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(hasPrice ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .padding(.horizontal, isSelectedForReplace ? 8 : 0)
                            .padding(.vertical, 2)
                            .background(
                                isSelectedForReplace ? Color.primary.opacity(0.10) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )

                        if isFocused {
                            TradeBlinkingCursor(
                                color: store.draft.side.tradeActionTint,
                                width: 2.5,
                                height: round(priceFontSize * 0.86)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                TradeLimitStepperButton(
                    systemImage: "plus",
                    accessibilityLabel: L10n.Trade.limitIncreasePrice(locale: locale)
                ) {
                    TradeKeypadHaptics.keyTap()
                    focusState.commitLimitPriceEdit()
                    store.stepLimitPrice(steps: 1)
                }
                .disabled(!canStepPrice)
            }

            HStack(spacing: 8) {
                TradeLimitBookChip(
                    title: L10n.Trade.limitBid(locale: locale),
                    price: store.bidPrice,
                    currencyCode: store.currencyCode
                ) {
                    TradeKeypadHaptics.selection()
                    focusState.commitLimitPriceEdit()
                    store.fillLimitFromBid()
                }

                TradeLimitBookChip(
                    title: L10n.Trade.limitMid(locale: locale),
                    price: store.defaultLimitReferencePrice,
                    currencyCode: store.currencyCode
                ) {
                    TradeKeypadHaptics.selection()
                    focusState.commitLimitPriceEdit()
                    store.fillLimitFromMid()
                }

                TradeLimitBookChip(
                    title: L10n.Trade.limitAsk(locale: locale),
                    price: store.askPrice,
                    currencyCode: store.currencyCode
                ) {
                    TradeKeypadHaptics.selection()
                    focusState.commitLimitPriceEdit()
                    store.fillLimitFromAsk()
                }
            }
        }
        .padding(18)
        .background(
            AppTheme.ColorToken.groupedSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isFocused ? store.draft.side.tradeActionTint.opacity(0.55) : Color(.separator).opacity(0.16),
                    lineWidth: isFocused ? 1.5 : 0.75
                )
        }
    }

    private var isFocused: Bool {
        focusState.focusedField == .limitPrice
    }

    private var isSelectedForReplace: Bool {
        isFocused && focusState.replaceLimitPriceOnNextDigit && hasPrice
    }

    private var hasPrice: Bool {
        !store.draft.limitPriceText.isEmpty
    }

    private var canStepPrice: Bool {
        hasPrice || store.defaultLimitReferencePrice != nil || store.marketReferencePrice != nil
    }

    private var priceDisplayText: String {
        guard hasPrice else { return AppFormatter.placeholder }
        return TradeInputFormat.formattedDisplay(store.draft.limitPriceText)
    }

    private var priceFontSize: CGFloat {
        switch priceDisplayText.count {
        case 0...6:
            return 38
        case 7...8:
            return 32
        default:
            return 26
        }
    }

    private var priceCurrencyFontSize: CGFloat {
        max(18, round(priceFontSize * 0.58))
    }

    private var priceDeltaDisplay: (text: String, tint: Color)? {
        guard let fraction = store.limitPriceDeltaFraction, abs(fraction) >= 0.0001 else {
            return nil
        }

        let isPositive = fraction > 0
        let sign = isPositive ? "+" : ""
        let percentText = "\(sign)\(AppFormatter.percent(fraction, fractionLength: 2))"
        let label = L10n.Trade.limitVsMarket(percentText, locale: locale)
        let tint: Color = isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
        return (label, tint)
    }
}

private struct TradeLimitQuantityCard: View {
    let store: TradeStore
    let focusState: TradeLimitFocusController

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(L10n.Trade.limitNumberOfShares(locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFocused ? .primary : .secondary)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Text(
                        store.draft.side == .buy
                            ? L10n.Trade.simpleEstimatedDebit(locale: locale)
                            : L10n.Trade.simpleEstimatedCredit(locale: locale)
                    )
                    .foregroundStyle(.secondary)

                    Text(AppFormatter.money(store.estimatedNotional, currencyCode: store.currencyCode))
                        .foregroundStyle(store.estimatedNotional != nil ? .primary : .secondary)
                }
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            ZStack {
                Button {
                    TradeKeypadHaptics.selection()
                    focusState.focusQuantity()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        HStack(alignment: .center, spacing: 2) {
                            Text(quantityDisplayText)
                                .font(.system(size: quantityFontSize, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)

                            if isFocused {
                                TradeBlinkingCursor(
                                    color: store.draft.side.tradeActionTint,
                                    width: 2.5,
                                    height: round(quantityFontSize * 0.86)
                                )
                            }
                        }

                        Text(unitLabel)
                            .font(.system(size: quantityUnitFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 34)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !store.draft.quantityText.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            TradeKeypadHaptics.keyTap()
                            focusState.focusQuantity()
                            store.setLimitQuantityText("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color(.tertiaryLabel))
                                .frame(width: 30, height: 30)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.Trade.simpleDelete(locale: locale))
                    }
                }
            }
            .frame(height: 52)

            TradeSimpleQuickFillRow(
                items: quickFillItems,
                selectedPercent: store.activeQuickFillPercent,
                style: .embedded,
                isDisabled: !store.quickFillAvailable
            ) { percent in
                TradeKeypadHaptics.selection()
                focusState.focusQuantity()
                store.fillQuickAmount(percent: percent)
            }
        }
        .padding(18)
        .background(
            AppTheme.ColorToken.groupedSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isFocused ? store.draft.side.tradeActionTint.opacity(0.55) : Color(.separator).opacity(0.16),
                    lineWidth: isFocused ? 1.5 : 0.75
                )
        }
    }

    private var isFocused: Bool {
        focusState.focusedField == .quantity
    }

    private var quantityDisplayText: String {
        TradeInputFormat.formattedDisplay(store.draft.quantityText)
    }

    private var quantityFontSize: CGFloat {
        switch quantityDisplayText.count {
        case 0...6:
            return 38
        case 7...9:
            return 32
        default:
            return 26
        }
    }

    private var quantityUnitFontSize: CGFloat {
        max(16, round(quantityFontSize * 0.54))
    }

    private var unitLabel: String {
        let symbol = store.normalizedSymbol
        return symbol.isEmpty ? L10n.Trade.simpleShares(locale: locale) : symbol
    }

    private var quickFillItems: [TradeSimpleQuickFillItem] {
        [
            TradeSimpleQuickFillItem(title: "25%", percent: Decimal(string: "0.25")!),
            TradeSimpleQuickFillItem(title: "50%", percent: Decimal(string: "0.50")!),
            TradeSimpleQuickFillItem(title: "75%", percent: Decimal(string: "0.75")!),
            TradeSimpleQuickFillItem(title: L10n.Trade.simpleMax(locale: locale), percent: Decimal(string: "1.0")!)
        ]
    }
}

private struct TradeLimitOptionsBar: View {
    let store: TradeStore

    @Environment(\.locale) private var locale

    private let options: [TimeInForce] = [.day, .gtc]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(options) { tif in
                    let isSelected = store.draft.timeInForce == tif
                    Button {
                        TradeKeypadHaptics.selection()
                        store.setTimeInForce(tif)
                    } label: {
                        Text(tif.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(
                                isSelected ? Color(.tertiarySystemFill) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(TradeFlatPressButtonStyle())
                }
            }
            .padding(4)
            .background(
                AppTheme.ColorToken.groupedSurface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.16), lineWidth: 0.75)
            }

            Spacer(minLength: 6)

            if store.canToggleMarginMode {
                Button {
                    TradeKeypadHaptics.selection()
                    store.setMarginEnabled(!store.isMarginEnabled)
                } label: {
                    Text(
                        store.draft.side == .buy
                            ? L10n.Trade.marginChipBuy(locale: locale)
                            : L10n.Trade.marginChipSell(locale: locale)
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(store.isMarginEnabled ? AppTheme.ColorToken.warning : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(
                        store.isMarginEnabled
                            ? AppTheme.ColorToken.warning.opacity(0.14)
                            : AppTheme.ColorToken.groupedSurface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                store.isMarginEnabled
                                    ? AppTheme.ColorToken.warning.opacity(0.42)
                                    : Color(.separator).opacity(0.16),
                                lineWidth: store.isMarginEnabled ? 1.1 : 0.75
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(TradeFlatPressButtonStyle())
            }

            Button {
                TradeKeypadHaptics.selection()
                store.setExtendedHours(!store.draft.extendedHours)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.draft.extendedHours ? "moon.stars.fill" : "moon.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(store.draft.extendedHours ? AppTheme.ColorToken.warning : .secondary)

                    Text(L10n.Trade.limitExtendedHours(locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(store.draft.extendedHours ? .primary : .secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(
                    store.draft.extendedHours
                        ? Color(.tertiarySystemFill)
                        : AppTheme.ColorToken.groupedSurface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            store.draft.extendedHours
                                ? Color.primary.opacity(0.32)
                                : Color(.separator).opacity(0.16),
                            lineWidth: store.draft.extendedHours ? 1.1 : 0.75
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(TradeFlatPressButtonStyle())
        }
    }
}

private struct TradeLimitStatusSection: View {
    let store: TradeStore
    let canUseAPI: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        TradeInlineStatusStrip(status: status)
            .padding(.horizontal, 4)
    }

    private var hasRequiredInputs: Bool {
        TradeInputFormat.hasPositiveValue(store.draft.quantityText)
            && TradeInputFormat.hasPositiveValue(store.draft.limitPriceText)
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

        if hasRequiredInputs {
            if let error = store.validation.errors.first {
                return TradeSimpleStatus(
                    systemImage: "exclamationmark.triangle.fill",
                    text: error,
                    tint: AppTheme.ColorToken.negative
                )
            }

            if let warning = store.validation.warnings.first {
                return TradeSimpleStatus(
                    systemImage: "exclamationmark.circle",
                    text: warning,
                    tint: AppTheme.ColorToken.warning
                )
            }
        }

        if let message = store.message, hasRequiredInputs {
            return TradeSimpleStatus(
                systemImage: "info.circle",
                text: message,
                tint: AppTheme.ColorToken.icon
            )
        }

        return nil
    }
}

private struct TradeLimitActionSection: View {
    let store: TradeStore
    let canUseAPI: Bool
    let review: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        TradeSimpleActionButton(state: buttonState, action: review)
    }

    private var hasRequiredInputs: Bool {
        TradeInputFormat.hasPositiveValue(store.draft.quantityText)
            && TradeInputFormat.hasPositiveValue(store.draft.limitPriceText)
    }

    private var buttonState: TradeSimpleActionButtonState {
        let tint = store.draft.side.tradeActionTint

        if store.isLoadingContext {
            return TradeSimpleActionButtonState(
                title: L10n.Trade.simpleReviewOrder(locale: locale),
                tint: tint,
                isEnabled: false
            )
        }

        if store.isSubmitting {
            return TradeSimpleActionButtonState(
                title: L10n.Trade.simpleSubmitting(locale: locale),
                tint: tint,
                isEnabled: false,
                showsProgress: true
            )
        }

        if !canUseAPI {
            return TradeSimpleActionButtonState(
                title: L10n.Trade.addCredentialsBeforeOrder(locale: locale),
                tint: AppTheme.ColorToken.warning,
                isEnabled: false,
                isError: true
            )
        }

        if hasRequiredInputs, let issue = store.validation.firstIssue {
            return TradeSimpleActionButtonState(
                title: TradeValidationActionTitle.title(for: issue, locale: locale),
                tint: AppTheme.ColorToken.negative,
                isEnabled: false,
                isError: issue.kind != .missingInput
            )
        }

        return TradeSimpleActionButtonState(
            title: L10n.Trade.simpleReviewOrder(locale: locale),
            tint: tint,
            isEnabled: store.validation.canSubmit
        )
    }
}

struct TradeLimitStepperButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isEnabled ? .primary : Color(.tertiaryLabel))
                .frame(width: 42, height: 42)
                .background(
                    Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(TradeFlatPressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TradeLimitBookChip: View {
    let title: String
    let price: Decimal?
    let currencyCode: String
    var priceFormatter: ((Decimal?) -> String)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(price != nil ? .secondary : Color(.tertiaryLabel))

                Text(formattedPrice)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(price != nil ? .primary : Color(.tertiaryLabel))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                Color(.tertiarySystemFill).opacity(price != nil ? 0.72 : 0.35),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(TradeFlatPressButtonStyle())
        .disabled(price == nil)
    }

    private var formattedPrice: String {
        if let priceFormatter {
            return priceFormatter(price)
        }
        return TradeFormat.price(price, currency: currencyCode)
    }
}

// MARK: - Shared Controls & Flat Non-Glass Components

enum TradeValidationActionTitle {
    static func title(for issue: TradeValidationIssue, locale: Locale) -> String {
        switch issue.kind {
        case .missingInput:
            return L10n.Trade.simpleEnterAmount(locale: locale)
        case .notionalBelowMinimum:
            return L10n.Trade.simpleNotionalMinShort(locale: locale)
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
}

struct TradeBlinkingCursor: View {
    let color: Color
    var width: CGFloat = 2.5
    var height: CGFloat = 46

    @State private var isVisible = true

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
            .opacity(isVisible ? 1 : 0.08)
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

struct TradeInlineStatusStrip: View {
    let status: TradeSimpleStatus?
    var alignment: Alignment = .leading

    var body: some View {
        Group {
            if let status {
                HStack(spacing: 6) {
                    Image(systemName: status.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(status.tint)

                    Text(status.text)
                        .font(AppTypography.caption.weight(.medium))
                        .foregroundStyle(status.tint == AppTheme.ColorToken.negative ? AppTheme.ColorToken.negative : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .frame(maxWidth: .infinity, alignment: alignment)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20, alignment: alignment)
    }
}

struct TradeSimpleStatus {
    let systemImage: String
    let text: String
    let tint: Color
}

struct TradeSimpleActionButtonState {
    let title: String
    let tint: Color
    let isEnabled: Bool
    var isError = false
    var showsProgress = false
}

struct TradeSimpleActionButton: View {
    let state: TradeSimpleActionButtonState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if state.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(state.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(backgroundColor, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(TradeFlatPressButtonStyle())
        .disabled(!state.isEnabled)
    }

    private var foregroundColor: Color {
        if state.isEnabled || state.showsProgress {
            return .white
        }
        if state.isError {
            return state.tint
        }
        return Color(.secondaryLabel)
    }

    private var backgroundColor: Color {
        if state.isEnabled || state.showsProgress {
            return state.tint
        }
        if state.isError {
            return state.tint.opacity(0.14)
        }
        return Color(.tertiarySystemFill)
    }
}

struct TradeSimpleQuickFillRow: View {
    enum Style {
        case regular
        case embedded

        var height: CGFloat {
            switch self {
            case .regular:
                40
            case .embedded:
                38
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .regular:
                10
            case .embedded:
                10
            }
        }

        var spacing: CGFloat {
            8
        }

        var font: Font {
            .subheadline.weight(.semibold).monospacedDigit()
        }
    }

    let items: [TradeSimpleQuickFillItem]
    var selectedPercent: Decimal? = nil
    var style: Style = .regular
    var isDisabled = false
    let action: (Decimal) -> Void

    var body: some View {
        HStack(spacing: style.spacing) {
            ForEach(items) { item in
                let isSelected = !isDisabled && selectedPercent == item.percent
                Button {
                    action(item.percent)
                } label: {
                    Text(item.title)
                        .font(style.font)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(textColor(isSelected: isSelected))
                        .frame(maxWidth: .infinity)
                        .frame(height: style.height)
                        .background(
                            fillColor(isSelected: isSelected),
                            in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                                .strokeBorder(borderColor(isSelected: isSelected), lineWidth: isSelected ? 1.2 : 0.75)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                }
                .buttonStyle(TradeFlatPressButtonStyle())
                .disabled(isDisabled)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func textColor(isSelected: Bool) -> Color {
        if isDisabled {
            return Color(.tertiaryLabel)
        }
        return .primary
    }

    private func fillColor(isSelected: Bool) -> Color {
        if isDisabled {
            return style == .embedded
                ? Color(.tertiarySystemFill).opacity(0.35)
                : AppTheme.ColorToken.groupedSurface.opacity(0.45)
        }
        if isSelected {
            return Color.primary.opacity(0.10)
        }
        return style == .embedded
            ? Color(.tertiarySystemFill).opacity(0.68)
            : AppTheme.ColorToken.groupedSurface
    }

    private func borderColor(isSelected: Bool) -> Color {
        if isDisabled {
            return Color(.separator).opacity(0.10)
        }
        if isSelected {
            return Color.primary.opacity(0.38)
        }
        return style == .embedded
            ? Color.clear
            : Color(.separator).opacity(0.22)
    }
}

struct TradeSimpleQuickFillItem: Identifiable {
    let title: String
    let percent: Decimal

    var id: String {
        "\(title)-\(percent)"
    }
}

struct TradeFlatPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - High-Performance Custom Keypad

enum TradeNumberPadKey: Identifiable, Equatable {
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

@MainActor
enum TradeKeypadHaptics {
    private static let keyTapGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()

    private static let clearGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        return generator
    }()

    private static let selectionGenerator: UISelectionFeedbackGenerator = {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        return generator
    }()

    static func keyTap() {
        keyTapGenerator.impactOccurred(intensity: 0.65)
    }

    static func clear() {
        clearGenerator.impactOccurred(intensity: 0.85)
    }

    static func selection() {
        selectionGenerator.selectionChanged()
    }
}

struct TradeNumberPad: View {
    let action: (TradeNumberPadKey) -> Void

    @Environment(\.locale) private var locale

    private static let rows: [[TradeNumberPadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.decimal, .digit("0"), .backspace]
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<Self.rows.count, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(Self.rows[rowIndex]) { key in
                        keyButton(for: key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(for key: TradeNumberPadKey) -> some View {
        let baseButton = Button {
            TradeKeypadHaptics.keyTap()
            action(key)
        } label: {
            TradeNumberPadKeyLabel(key: key)
                .frame(maxWidth: .infinity)
                .frame(height: 55)
                .contentShape(Rectangle())
        }
        .buttonStyle(TradeNumberPadButtonStyle())
        .accessibilityLabel(accessibilityLabel(for: key))

        if key == .backspace {
            baseButton.simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        TradeKeypadHaptics.clear()
                        action(.clear)
                    }
            )
        } else {
            baseButton
        }
    }

    private func accessibilityLabel(for key: TradeNumberPadKey) -> String {
        switch key {
        case .digit(let value):
            return value
        case .decimal:
            return L10n.Trade.simpleDecimalPoint(locale: locale)
        case .backspace, .clear:
            return L10n.Trade.simpleDelete(locale: locale)
        }
    }
}

private struct TradeNumberPadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color(.tertiarySystemFill) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

private struct TradeNumberPadKeyLabel: View {
    let key: TradeNumberPadKey

    var body: some View {
        Group {
            switch key {
            case .digit(let value):
                Text(value)
                    .font(.system(size: 28, weight: .medium, design: .rounded).monospacedDigit())
            case .decimal:
                Text(".")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            case .backspace, .clear:
                Image(systemName: "delete.left")
                    .font(.system(size: 22, weight: .medium))
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Formatting & Zero-Regex Input Sanitization

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
        var copy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, 6, .down)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        let normalized = NumberText.trimTrailingZeros(text)
        return normalized.isEmpty ? "0" : normalized
    }
}

enum TradeInputLimit {
    /// Up to $99,999,999.99 (10 total digits) — covers all realistic equity orders without layout overflow.
    static let notionalMaxIntegerDigits = 8
    static let notionalMaxTotalDigits = 10

    /// Up to 9,999,999 shares or fractional quantities up to 10 total significant digits.
    static let sharesMaxIntegerDigits = 7
    static let sharesMaxTotalDigits = 10

    /// Up to $999,999.99 (covers even BRK.A) with 2 decimals above $1 or 4 decimals below $1.
    static let priceMaxIntegerDigits = 6
    static let priceMaxTotalDigits = 8
}

enum TradeInputFormat {
    private static let defaultMaxIntegerDigits = 8

    static func applyKey(
        _ key: TradeNumberPadKey,
        to current: String,
        maxIntegerDigits: Int = defaultMaxIntegerDigits,
        maxFractionDigits: Int,
        maxTotalDigits: Int? = nil
    ) -> String {
        switch key {
        case .digit(let digit):
            if current.isEmpty || current == "0" {
                return digit == "0" ? "0" : digit
            }

            if let maxTotalDigits {
                let currentDigitCount = current.reduce(into: 0) { count, ch in
                    if ch >= "0" && ch <= "9" { count += 1 }
                }
                guard currentDigitCount < maxTotalDigits else { return current }
            }

            if let dotIndex = current.firstIndex(of: ".") {
                let fractionCount = current.distance(from: current.index(after: dotIndex), to: current.endIndex)
                guard fractionCount < maxFractionDigits else { return current }
                return current + digit
            } else {
                guard current.count < maxIntegerDigits else { return current }
                return current + digit
            }
        case .decimal:
            guard maxFractionDigits > 0, !current.contains(".") else { return current }
            if let maxTotalDigits {
                let currentDigitCount = current.reduce(into: 0) { count, ch in
                    if ch >= "0" && ch <= "9" { count += 1 }
                }
                guard currentDigitCount < maxTotalDigits else { return current }
            }
            return current.isEmpty ? "0." : (current + ".")
        case .backspace:
            guard !current.isEmpty else { return "" }
            var next = current
            next.removeLast()
            return next
        case .clear:
            return ""
        }
    }

    static func sanitize(
        _ value: String,
        maxIntegerDigits: Int = defaultMaxIntegerDigits,
        maxFractionDigits: Int
    ) -> String {
        var integerChars: [Character] = []
        var fractionChars: [Character] = []
        var seenDecimal = false

        for ch in value {
            if ch >= "0" && ch <= "9" {
                if seenDecimal {
                    if fractionChars.count < maxFractionDigits {
                        fractionChars.append(ch)
                    }
                } else if integerChars.count < maxIntegerDigits {
                    integerChars.append(ch)
                }
            } else if ch == ".", !seenDecimal, maxFractionDigits > 0 {
                seenDecimal = true
            }
        }

        if integerChars.isEmpty && !seenDecimal {
            return ""
        }

        let trimmedInteger = integerChars.drop { $0 == "0" }
        let integerPart = trimmedInteger.isEmpty ? "0" : String(trimmedInteger)

        if seenDecimal {
            return "\(integerPart).\(String(fractionChars))"
        }
        return integerPart
    }

    static func formattedDisplay(_ rawText: String) -> String {
        guard !rawText.isEmpty else {
            return "0"
        }

        if let dotIndex = rawText.firstIndex(of: ".") {
            let integerSlice = rawText[..<dotIndex]
            let fractionSlice = rawText[dotIndex...]
            return groupIntegerDigits(integerSlice) + fractionSlice
        }

        return groupIntegerDigits(rawText[...])
    }

    static func hasPositiveValue(_ value: String) -> Bool {
        guard !value.isEmpty,
              let decimal = NumberParser.decimal(from: NumberText.trimTrailingZeros(value)) else {
            return false
        }

        return decimal > 0
    }

    private static func groupIntegerDigits(_ digits: Substring) -> String {
        let count = digits.count
        guard count > 3 else {
            return digits.isEmpty ? "0" : String(digits)
        }

        var result = ""
        result.reserveCapacity(count + (count - 1) / 3)
        var remaining = count
        for ch in digits {
            result.append(ch)
            remaining -= 1
            if remaining > 0, remaining % 3 == 0 {
                result.append(",")
            }
        }
        return result
    }
}

#Preview {
    NavigationStack {
        TradeView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
