import Observation
import SwiftUI

struct OptionTradeView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var store: OptionTradeStore
    @State private var confirmation: OptionTradeConfirmationSnapshot?
    @FocusState private var focusedField: OptionTradeFocusedField?

    init(
        contractSymbol: String,
        initialIntent: OrderPositionIntent = .buyToOpen,
        initialSnapshotModel: OptionDetailSnapshotModel? = nil
    ) {
        _store = State(initialValue: OptionTradeStore(
            contractSymbol: contractSymbol,
            initialIntent: initialIntent,
            initialSnapshotModel: initialSnapshotModel
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            OptionTradeTopBar(
                store: store,
                close: {
                    focusedField = nil
                    dismiss()
                }
            )
            .padding(.top, 18)
            .padding(.bottom, 6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    OptionTradeContractBanner(store: store)
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                    OptionTradePriceCard(store: store, focusedField: $focusedField)

                    OptionTradeContractsCard(store: store, focusedField: $focusedField)

                    OptionTradeErrorSection(store: store, canUseAPI: app.canUseAlpacaAPI)

                    if let payoffSpec = store.payoffSpec {
                        OptionPayoffChartCard(
                            spec: payoffSpec,
                            underlyingSymbol: store.descriptor.underlyingSymbol
                        )
                    }

                    OptionTradeMetaRow(store: store)
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField == nil {
                OptionTradeActionSection(
                    store: store,
                    canUseAPI: app.canUseAlpacaAPI,
                    review: reviewOrder
                )
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(
                    AppTheme.ColorToken.pageBackground
                        .ignoresSafeArea(edges: .bottom)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                OptionTradeKeyboardAccessoryBar(
                    focusedField: $focusedField
                )
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.20), value: focusedField == nil)
        .task {
            store.updateLocale(app.appLanguage.locale)
            await store.load(app: app, force: true)
        }
        .onChange(of: app.appLanguage) { _, language in
            store.updateLocale(language.locale)
        }
        .onChange(of: store.errorMessage) { _, message in
            showErrorMessage(message)
        }
        .sheet(item: $confirmation) { snapshot in
            OptionTradeConfirmationSheet(snapshot: snapshot) {
                await store.submit(app: app, snapshot: snapshot)
            } onSubmitted: { _ in
                dismiss()
            }
        }
    }

    private func reviewOrder() {
        focusedField = nil
        store.updateLocale(locale)

        guard app.canUseAlpacaAPI else {
            store.message = L10n.Trade.addCredentialsBeforeOrder(locale: locale)
            return
        }

        let validation = store.validation
        guard validation.canSubmit else {
            store.message = validation.errors.first
            return
        }

        store.message = nil
        confirmation = OptionTradeConfirmationSnapshot(store: store, environment: app.environment)
    }

    private func showErrorMessage(_ message: String?) {
        guard let message else {
            return
        }

        toastCenter.showErrorMessage(message)
    }
}

// MARK: - Option Trade Store

@MainActor
@Observable
final class OptionTradeStore {
    static let supportedIntents: [OrderPositionIntent] = [.buyToOpen, .sellToOpen, .buyToClose, .sellToClose]
    static let contractMultiplier = Decimal(100)

    let contractSymbol: String
    let descriptor: OptionContractDescriptor
    var intent: OrderPositionIntent {
        didSet {
            guard intent != oldValue else { return }
            applyIntentToDraft()
            activeQuickFillPercent = nil
            message = nil
        }
    }
    var draft: OrderDraft {
        didSet {
            message = nil
            refreshDerivedState()
        }
    }
    var activeQuickFillPercent: Decimal?
    private(set) var account: AlpacaAccount? {
        didSet { refreshDerivedState() }
    }
    private(set) var position: AlpacaPosition? {
        didSet { refreshDerivedState() }
    }
    private(set) var underlyingPosition: AlpacaPosition? {
        didSet { refreshDerivedState() }
    }
    private(set) var underlyingSpotPrice: Double?
    private(set) var snapshot: AlpacaOptionSnapshot? {
        didSet { refreshDerivedState() }
    }
    private(set) var isLoading = false {
        didSet { refreshDerivedState() }
    }
    var isSubmitting = false
    var message: String?
    private(set) var errorMessage: String?
    private var initialSnapshotModel: OptionDetailSnapshotModel?
    private var locale = AppLocale.current
    private var estimatedNotionalSnapshot: Decimal?
    private var validationSnapshot: TradeValidationResult = .empty

    init(
        contractSymbol: String,
        initialIntent: OrderPositionIntent,
        initialSnapshotModel: OptionDetailSnapshotModel?
    ) {
        let normalizedSymbol = contractSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let resolvedIntent = Self.supportedIntents.contains(initialIntent) ? initialIntent : .buyToOpen
        self.contractSymbol = normalizedSymbol
        descriptor = OptionContractDescriptor(symbol: normalizedSymbol)
        intent = resolvedIntent
        self.initialSnapshotModel = initialSnapshotModel

        var draft = OrderDraft()
        draft.symbol = normalizedSymbol
        draft.orderType = .limit
        draft.timeInForce = .day
        draft.side = resolvedIntent.side
        draft.positionIntent = resolvedIntent
        self.draft = draft
        refreshDerivedState()
        fillDefaultLimitPriceIfNeeded()
    }

    func updateLocale(_ locale: Locale) {
        let resolvedLocale = AppLocale.resolvedLocale(for: locale)
        guard self.locale.identifier != resolvedLocale.identifier else {
            return
        }

        self.locale = resolvedLocale
        refreshDerivedState()
    }

    var snapshotModel: OptionDetailSnapshotModel {
        if let snapshot {
            return OptionDetailSnapshotModel(descriptor: descriptor, snapshot: snapshot)
        }

        if let initialSnapshotModel {
            return initialSnapshotModel
        }

        return OptionDetailSnapshotModel(descriptor: descriptor, snapshot: nil)
    }

    var bidPrice: Decimal? {
        Self.positivePriceDecimal(snapshot?.latestQuote?.bidPrice)
            ?? Self.positivePriceDecimal(initialSnapshotModel?.bidPrice)
    }

    var askPrice: Decimal? {
        Self.positivePriceDecimal(snapshot?.latestQuote?.askPrice)
            ?? Self.positivePriceDecimal(initialSnapshotModel?.askPrice)
    }

    var midPrice: Decimal? {
        if let bidPrice, let askPrice, bidPrice > 0, askPrice > 0, bidPrice <= askPrice {
            return (bidPrice + askPrice) / 2
        }
        return Self.positivePriceDecimal(snapshot?.latestQuote?.midpoint)
            ?? Self.positivePriceDecimal(initialSnapshotModel?.midPrice)
    }

    var lastPrice: Decimal? {
        Self.positivePriceDecimal(snapshot?.latestTrade?.price)
            ?? Self.positivePriceDecimal(initialSnapshotModel?.lastPrice)
    }

    var marketReferencePrice: Decimal? {
        midPrice ?? lastPrice ?? askPrice ?? bidPrice
    }

    var limitPriceDeltaFraction: Double? {
        guard let limitPrice, limitPrice > 0,
              let reference = marketReferencePrice, reference > 0 else {
            return nil
        }

        let delta = (limitPrice - reference) / reference
        return NSDecimalNumber(decimal: delta).doubleValue
    }

    var payoffSpec: OptionPayoffSpec? {
        guard intent == .buyToOpen || intent == .sellToOpen,
              let contractType = descriptor.type,
              let strike = descriptor.strike, strike > 0,
              let premiumDecimal = limitPrice ?? defaultLimitReferencePrice,
              premiumDecimal > 0 else {
            return nil
        }

        let premium = NSDecimalNumber(decimal: premiumDecimal).doubleValue
        let contracts = requestedContracts ?? 1
        let isPreview = requestedContracts == nil
        let side: OptionPayoffSide = intent.side == .buy ? .long : .short

        return OptionPayoffSpec(
            contractType: contractType,
            side: side,
            strike: strike,
            premium: premium,
            contracts: contracts,
            multiplier: 100,
            underlyingPrice: underlyingSpotPrice,
            currencyCode: currencyCode,
            isSimulatedPreview: isPreview
        )
    }

    var currencyCode: String {
        account?.currency ?? "USD"
    }

    var optionsTradingLevel: Int {
        account?.optionsTradingLevel ?? 0
    }

    var optionsApprovedLevel: Int {
        account?.optionsApprovedLevel ?? 0
    }

    /// Cash-backed options buying power for opening orders (never borrows on margin).
    var cashOptionsBuyingPower: Decimal? {
        guard let account else {
            return nil
        }

        let optionsBP = NumberParser.decimal(from: account.optionsBuyingPower)
        let nonMarginable = NumberParser.decimal(from: account.nonMarginableBuyingPower)
        let accountCash = NumberParser.decimal(from: account.cash)
        let totalBP = NumberParser.decimal(from: account.buyingPower)

        let cashBounds = [optionsBP, nonMarginable, accountCash].compactMap { $0 }
        if let minBound = cashBounds.min() {
            if let totalBP {
                return max(min(minBound, totalBP), 0)
            }
            return max(minBound, 0)
        }

        return totalBP.map { max($0, 0) }
    }

    /// Closing buying power for `buyToClose` (never blocks risk-reducing short cover due to negative stock margin cash).
    var closingOptionsBuyingPower: Decimal? {
        if let optionsBP = NumberParser.decimal(from: account?.optionsBuyingPower) {
            return max(optionsBP, 0)
        }
        return cashOptionsBuyingPower
    }

    var optionsBuyingPower: Decimal? {
        intent == .buyToClose ? closingOptionsBuyingPower : cashOptionsBuyingPower
    }

    var positionQuantity: Decimal {
        NumberParser.decimal(from: position?.quantity) ?? 0
    }

    var availableOptionQuantity: Decimal {
        NumberParser.decimal(from: position?.quantityAvailable) ?? positionQuantity
    }

    var longContractsAvailable: Decimal {
        max(availableOptionQuantity, 0)
    }

    var shortContractsAvailable: Decimal {
        max(-availableOptionQuantity, 0)
    }

    var underlyingSharesAvailable: Decimal {
        let quantity = NumberParser.decimal(from: underlyingPosition?.quantityAvailable)
            ?? NumberParser.decimal(from: underlyingPosition?.quantity)
            ?? 0
        return max(quantity, 0)
    }

    var maxContractsAvailable: Int {
        switch intent {
        case .buyToOpen:
            guard let buyingPower = optionsBuyingPower,
                  let price = limitPrice ?? defaultLimitReferencePrice,
                  price > 0 else {
                return 0
            }
            let costPerContract = price * Self.contractMultiplier
            guard costPerContract > 0 else { return 0 }
            return Self.flooredWholeInt(buyingPower / costPerContract)
        case .sellToClose:
            return Self.flooredWholeInt(longContractsAvailable)
        case .buyToClose:
            let shortMax = Self.flooredWholeInt(shortContractsAvailable)
            guard shortMax > 0 else { return 0 }
            if let buyingPower = optionsBuyingPower,
               let price = limitPrice ?? defaultLimitReferencePrice,
               price > 0 {
                let bpMax = Self.flooredWholeInt(buyingPower / (price * Self.contractMultiplier))
                return min(shortMax, bpMax)
            }
            return shortMax
        case .sellToOpen:
            switch descriptor.type {
            case .put:
                guard let buyingPower = optionsBuyingPower,
                      let strike = Self.positivePriceDecimal(descriptor.strike),
                      strike > 0 else {
                    return 0
                }
                return Self.flooredWholeInt(buyingPower / (strike * Self.contractMultiplier))
            case .call:
                return Self.flooredWholeInt(underlyingSharesAvailable / Self.contractMultiplier)
            case nil:
                return 0
            }
        }
    }

    var quickFillAvailable: Bool {
        maxContractsAvailable > 0
    }

    var requestedContracts: Int? {
        let quantity = OrderDraft.normalizedSizeText(draft.quantityText)
        guard !quantity.isEmpty,
              quantity.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              let value = Int(quantity),
              value > 0 else {
            return nil
        }
        return value
    }

    var limitPrice: Decimal? {
        guard let value = NumberParser.decimal(from: NumberText.trimTrailingZeros(draft.limitPriceText)),
              value > 0 else {
            return nil
        }
        return value
    }

    var estimatedExecutionPrice: Decimal? {
        limitPrice
    }

    var estimatedNotional: Decimal? {
        estimatedNotionalSnapshot
    }

    var validation: TradeValidationResult {
        validationSnapshot
    }

    var hasPermissionIssue: Bool {
        guard account != nil else {
            return !isLoading
        }
        return permissionIssue != nil
    }

    func load(app: AppModel, force: Bool = false) async {
        updateLocale(app.appLanguage.locale)
        guard !contractSymbol.isEmpty else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        async let underlyingSnapshotTask: AlpacaResolvedStockSnapshot? = try? app.fetchTradeSnapshot(
            symbol: descriptor.underlyingSymbol
        )

        var firstError: Error?

        do {
            account = try await app.fetchAccountDetails()
        } catch {
            firstError = firstError ?? error
        }

        do {
            position = try await app.fetchOpenPosition(symbol: contractSymbol)
        } catch {
            firstError = firstError ?? error
        }

        if descriptor.type == .call {
            do {
                underlyingPosition = try await app.fetchOpenPosition(symbol: descriptor.underlyingSymbol)
            } catch {
                firstError = firstError ?? error
            }
        } else {
            underlyingPosition = nil
        }

        do {
            if let loadedSnapshot = try await app.fetchOptionSnapshot(symbol: contractSymbol, forceReload: force) {
                snapshot = loadedSnapshot
                initialSnapshotModel = nil
                fillDefaultLimitPriceIfNeeded()
            }
        } catch {
            firstError = firstError ?? error
        }

        if let resolvedStock = await underlyingSnapshotTask {
            let stockSnapshot = resolvedStock.snapshot
            let candidates = [
                stockSnapshot?.latestTrade?.price,
                stockSnapshot?.minuteBar?.close,
                stockSnapshot?.dailyBar?.close,
                stockSnapshot?.previousDailyBar?.close,
                NumberParser.double(from: underlyingPosition?.currentPrice)
            ]
            underlyingSpotPrice = candidates.compactMap { $0 }.first { $0.isFinite && $0 > 0 }
        } else if let positionPrice = NumberParser.double(from: underlyingPosition?.currentPrice), positionPrice > 0 {
            underlyingSpotPrice = positionPrice
        }

        if let firstError {
            errorMessage = APIErrorDisplayMessage.message(for: firstError, locale: locale)
        } else {
            errorMessage = nil
            message = nil
        }
    }

    func setContractsText(_ rawText: String) {
        guard rawText.count <= OptionTradeInputLimit.contractsMaxDigits,
              rawText.utf8.allSatisfy({ (48...57).contains($0) }) else { return }
        let sanitized = TradeInputFormat.sanitize(
            rawText,
            maxIntegerDigits: OptionTradeInputLimit.contractsMaxDigits,
            maxFractionDigits: 0
        )
        message = nil
        activeQuickFillPercent = nil
        if draft.quantityText != sanitized || !draft.notionalText.isEmpty {
            var nextDraft = draft
            nextDraft.quantityText = sanitized
            nextDraft.notionalText = ""
            draft = nextDraft
        }
    }

    func setLimitPriceText(_ rawText: String) {
        let maxFractionDigits: Int = {
            if let value = NumberParser.decimal(from: rawText) {
                return value >= 1 ? 2 : 4
            }
            return 4
        }()
        let sanitized = TradeInputFormat.sanitize(
            rawText,
            maxIntegerDigits: OptionTradeInputLimit.priceMaxIntegerDigits,
            maxFractionDigits: maxFractionDigits
        )
        message = nil
        if intent.side == .buy {
            activeQuickFillPercent = nil
        }
        if draft.limitPriceText != sanitized {
            draft.limitPriceText = sanitized
        }
    }

    func stepLimitPrice(steps: Int) {
        guard steps != 0 else { return }
        message = nil
        let base = limitPrice ?? defaultLimitReferencePrice ?? marketReferencePrice
        guard let base, base > 0 else { return }

        let tick = Decimal(string: "0.01")!
        let next = max(tick, base + tick * Decimal(steps))
        let formatted = Self.apiPriceNumber(next)

        if intent.side == .buy {
            activeQuickFillPercent = nil
        }
        if draft.limitPriceText != formatted {
            draft.limitPriceText = formatted
        }
    }

    func fillContracts(percent: Decimal) {
        message = nil
        if limitPrice == nil {
            fillDefaultLimitPriceIfNeeded()
        }
        let maxContracts = maxContractsAvailable
        guard maxContracts > 0 else {
            activeQuickFillPercent = nil
            return
        }

        let clampedPercent = min(max(percent, 0), 1)
        let target: Int
        if clampedPercent >= 1 {
            target = maxContracts
        } else {
            target = max(1, Self.flooredWholeInt(Decimal(maxContracts) * clampedPercent))
        }

        let resolvedTarget = min(target, maxContracts)
        let nextText = String(resolvedTarget)
        var nextDraft = draft
        nextDraft.notionalText = ""
        nextDraft.quantityText = nextText
        if draft != nextDraft {
            draft = nextDraft
        }
        activeQuickFillPercent = resolvedTarget == maxContracts ? Decimal(1) : percent
    }

    func selectPrice(_ source: OptionTradePriceFillSource) {
        guard let price = price(for: source) else {
            return
        }

        if intent.side == .buy {
            activeQuickFillPercent = nil
        }
        let formatted = Self.apiPriceNumber(price)
        if draft.limitPriceText != formatted {
            draft.limitPriceText = formatted
        }
        message = nil
    }

    func submit(app: AppModel, snapshot: OptionTradeConfirmationSnapshot) async -> TradeSubmitResult {
        updateLocale(app.appLanguage.locale)

        guard !isSubmitting else {
            return .failure(L10n.Trade.simpleSubmitting(locale: locale))
        }

        if draft != snapshot.order {
            draft = snapshot.order
        }

        guard validation.canSubmit else {
            let errorMessage = validation.errors.first ?? L10n.Trade.simpleOrderUnavailable(locale: locale)
            message = errorMessage
            return .failure(errorMessage)
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let result = await app.submit(snapshot.order, clientOrderID: snapshot.clientOrderID, confirmedEnvironment: snapshot.environment)
        switch result {
        case .success(let order):
            await load(app: app, force: true)
            message = L10n.Trade.orderSubmitted(locale: locale)
            return .success(order)
        case .failure(let errorMessage):
            message = errorMessage
            return .failure(errorMessage)
        }
    }

    #if DEBUG
    func configureForTesting(
        account: AlpacaAccount?,
        position: AlpacaPosition? = nil,
        underlyingPosition: AlpacaPosition? = nil,
        underlyingSpotPrice: Double? = nil
    ) {
        self.account = account
        self.position = position
        self.underlyingPosition = underlyingPosition
        self.underlyingSpotPrice = underlyingSpotPrice
    }
    #endif

    private var permissionIssue: String? {
        if account?.tradingBlocked == true || account?.accountBlocked == true || account?.tradeSuspendedByUser == true {
            return L10n.Trade.accountTradingBlocked(locale: locale)
        }

        guard optionsTradingLevel > 0 else {
            return L10n.Trade.optionErrorDisabled(locale: locale)
        }

        switch intent {
        case .buyToOpen:
            return optionsTradingLevel >= 2 ? nil : L10n.Trade.optionErrorLevel2Required(locale: locale)
        case .sellToOpen:
            guard optionsTradingLevel >= 1 else {
                return L10n.Trade.optionErrorLevel1Required(locale: locale)
            }
            return descriptor.type == nil ? L10n.Trade.simpleOrderUnavailable(locale: locale) : nil
        case .buyToClose, .sellToClose:
            return optionsTradingLevel >= 1 ? nil : L10n.Trade.optionErrorCloseRequiresAccess(locale: locale)
        }
    }

    private func refreshDerivedState() {
        let nextNotional = calculateEstimatedNotional()
        if estimatedNotionalSnapshot != nextNotional {
            estimatedNotionalSnapshot = nextNotional
        }

        let nextValidation = makeValidation()
        if validationSnapshot != nextValidation {
            validationSnapshot = nextValidation
        }
    }

    private func calculateEstimatedNotional() -> Decimal? {
        guard let requestedContracts, let limitPrice else {
            return nil
        }

        return Decimal(requestedContracts) * limitPrice * Self.contractMultiplier
    }

    private func makeValidation() -> TradeValidationResult {
        var issues: [TradeValidationIssue] = []

        do {
            _ = try draft.requestPayload()
        } catch let error as OrderDraftError {
            issues.append(TradeValidationIssue(
                kind: Self.issueKind(for: error),
                message: error.errorDescription(locale: locale)
            ))
        } catch {
            issues.append(.generic(error.localizedDescription))
        }

        if requestedContracts == nil {
            let normalizedQuantity = OrderDraft.normalizedSizeText(draft.quantityText)
            if normalizedQuantity.isEmpty {
                issues.append(TradeValidationIssue(
                    kind: .missingInput,
                    message: L10n.Order.missingSize(locale: locale)
                ))
            } else {
                issues.append(.generic(L10n.Order.invalidQuantity(locale: locale)))
            }
        }

        if account == nil, !isLoading {
            issues.append(.generic(L10n.Trade.contextNotLoaded(locale: locale)))
        }

        if let permissionIssue {
            issues.append(.generic(permissionIssue))
        }

        if let requestedContracts {
            issues.append(contentsOf: optionIntentIssues(requestedContracts: requestedContracts))
        }

        return TradeValidationResult(issues: Self.unique(issues), warnings: [])
    }

    private func optionIntentIssues(requestedContracts: Int) -> [TradeValidationIssue] {
        let requested = Decimal(requestedContracts)

        switch intent {
        case .buyToOpen:
            guard let estimatedNotional else {
                return []
            }

            return buyingPowerIssues(
                requiredBuyingPower: estimatedNotional,
                kind: .buyExceedsBuyingPower,
                exceededMessage: L10n.Trade.buyExceedsBuyingPower(locale: locale)
            )
        case .sellToOpen:
            return sellToOpenIssues(requestedContracts: requested)
        case .buyToClose:
            guard requested <= shortContractsAvailable else {
                return [
                    TradeValidationIssue(
                        kind: .sellExceedsPosition,
                        message: L10n.Trade.optionErrorBuyToCloseExceedsShort(locale: locale)
                    )
                ]
            }

            guard let estimatedNotional else {
                return []
            }

            return buyingPowerIssues(
                requiredBuyingPower: estimatedNotional,
                kind: .buyExceedsBuyingPower,
                exceededMessage: L10n.Trade.buyExceedsBuyingPower(locale: locale)
            )
        case .sellToClose:
            guard requested <= longContractsAvailable else {
                return [
                    TradeValidationIssue(
                        kind: .sellExceedsPosition,
                        message: L10n.Trade.optionErrorSellToCloseExceedsLong(locale: locale)
                    )
                ]
            }

            return []
        }
    }

    private func sellToOpenIssues(requestedContracts: Decimal) -> [TradeValidationIssue] {
        switch descriptor.type {
        case .put:
            guard let requirement = cashSecuredPutRequirement(requestedContracts: requestedContracts) else {
                return [.generic(L10n.Trade.simpleOrderUnavailable(locale: locale))]
            }

            return buyingPowerIssues(
                requiredBuyingPower: requirement,
                kind: .shortExceedsBuyingPower,
                exceededMessage: L10n.Trade.optionErrorCspExceedsBuyingPower(locale: locale)
            )
        case .call:
            let requiredShares = requestedContracts * Self.contractMultiplier
            guard underlyingSharesAvailable >= requiredShares else {
                return [
                    TradeValidationIssue(
                        kind: .sellExceedsPosition,
                        message: L10n.Trade.optionErrorCoveredCallShares(
                            shares: Self.displayWholeNumber(requiredShares),
                            symbol: descriptor.underlyingSymbol,
                            locale: locale
                        )
                    )
                ]
            }

            return []
        case nil:
            return [.generic(L10n.Trade.simpleOrderUnavailable(locale: locale))]
        }
    }

    private func buyingPowerIssues(
        requiredBuyingPower: Decimal,
        kind: TradeValidationIssueKind,
        exceededMessage: String
    ) -> [TradeValidationIssue] {
        guard account != nil else {
            return []
        }

        guard let optionsBuyingPower else {
            return [.generic(L10n.Trade.contextNotLoaded(locale: locale))]
        }

        guard requiredBuyingPower <= optionsBuyingPower else {
            return [
                TradeValidationIssue(
                    kind: kind,
                    message: exceededMessage
                )
            ]
        }

        return []
    }

    private func cashSecuredPutRequirement(requestedContracts: Decimal) -> Decimal? {
        guard descriptor.type == .put,
              let strike = Self.positivePriceDecimal(descriptor.strike) else {
            return nil
        }

        return strike * Self.contractMultiplier * requestedContracts
    }

    private func applyIntentToDraft() {
        var nextDraft = draft
        nextDraft.side = intent.side
        nextDraft.positionIntent = intent
        nextDraft.orderType = .limit
        nextDraft.timeInForce = .day
        nextDraft.notionalText = ""
        nextDraft.extendedHours = false
        if draft != nextDraft {
            draft = nextDraft
        }
        fillDefaultLimitPriceIfNeeded()
    }

    private func fillDefaultLimitPriceIfNeeded() {
        guard NumberText.trimTrailingZeros(draft.limitPriceText).isEmpty,
              let price = defaultLimitReferencePrice else {
            return
        }

        let formatted = Self.apiPriceNumber(price)
        if draft.limitPriceText != formatted {
            draft.limitPriceText = formatted
        }
    }

    var defaultLimitReferencePrice: Decimal? {
        if let midPrice, midPrice > 0 {
            return midPrice
        }

        switch intent.side {
        case .buy:
            return askPrice ?? lastPrice ?? bidPrice
        case .sell:
            return bidPrice ?? lastPrice ?? askPrice
        }
    }

    private func price(for source: OptionTradePriceFillSource) -> Decimal? {
        switch source {
        case .bid:
            bidPrice
        case .mid:
            midPrice ?? defaultLimitReferencePrice
        case .ask:
            askPrice
        case .last:
            lastPrice
        }
    }

    private static func positivePriceDecimal(_ value: Double?) -> Decimal? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        return Decimal(string: String(value), locale: NumberParser.apiLocale)
    }

    private static func flooredWholeInt(_ value: Decimal) -> Int {
        guard value > 0 else { return 0 }
        var copy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, 0, .down)
        return max(0, NSDecimalNumber(decimal: rounded).intValue)
    }

    private static func apiPriceNumber(_ value: Decimal) -> String {
        apiNumber(value, scale: value >= 1 ? 2 : 4)
    }

    private static func apiNumber(_ value: Decimal, scale: Int) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, scale, .plain)
        return NumberText.trimTrailingZeros(NSDecimalNumber(decimal: rounded).stringValue)
    }

    private static func displayWholeNumber(_ value: Decimal) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private static func unique(_ issues: [TradeValidationIssue]) -> [TradeValidationIssue] {
        var seen = Set<String>()
        return issues.filter { issue in
            seen.insert("\(issue.kind)-\(issue.message)").inserted
        }
    }

    private static func issueKind(for error: OrderDraftError) -> TradeValidationIssueKind {
        switch error {
        case .missingSize:
            .missingInput
        default:
            .generic
        }
    }
}

enum OptionTradePriceFillSource: String, Identifiable {
    case bid
    case mid
    case ask
    case last

    var id: String { rawValue }
}

struct OptionTradeConfirmationSnapshot: Identifiable {
    let id = UUID()
    let clientOrderID: String
    let order: OrderDraft
    let descriptor: OptionContractDescriptor
    let intent: OrderPositionIntent
    let estimatedNotional: Decimal?
    let estimatedExecutionPrice: Decimal?
    let currencyCode: String
    let environment: TradeEnvironment

    @MainActor
    init(store: OptionTradeStore, environment: TradeEnvironment) {
        clientOrderID = "vicu-\(UUID().uuidString.lowercased())"
        order = store.draft
        descriptor = store.descriptor
        intent = store.intent
        estimatedNotional = store.estimatedNotional
        estimatedExecutionPrice = store.estimatedExecutionPrice
        currencyCode = store.currencyCode
        self.environment = environment
    }
}

// MARK: - Option Trade Top Bar & Input Cards

private enum OptionTradeFocusedField: Hashable {
    case contracts
    case limitPrice
}

private enum OptionTradeInputLimit {
    static let contractsMaxDigits = 5
    static let priceMaxIntegerDigits = 4
}

private struct OptionTradeKeyboardAccessoryBar: View {
    let focusedField: FocusState<OptionTradeFocusedField?>.Binding

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                fieldSwitchButton(
                    title: L10n.Trade.limitPrice(locale: locale),
                    field: .limitPrice
                )

                fieldSwitchButton(
                    title: L10n.Trade.optionContracts(locale: locale),
                    field: .contracts
                )
            }
            .padding(4)
            .background(
                AppTheme.ColorToken.groupedSurface,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(Color(.separator).opacity(0.20), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)

            Spacer(minLength: 8)

            Button {
                TradeKeypadHaptics.selection()
                focusedField.wrappedValue = nil
            } label: {
                Text(L10n.Trade.optionDone(locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(
                        AppTheme.ColorToken.groupedSurface,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(Color(.separator).opacity(0.20), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                    .contentShape(Capsule())
            }
            .buttonStyle(TradeFlatPressButtonStyle())
        }
    }

    private func fieldSwitchButton(title: String, field: OptionTradeFocusedField) -> some View {
        let isSelected = focusedField.wrappedValue == field
        return Button {
            TradeKeypadHaptics.selection()
            focusedField.wrappedValue = field
        } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    isSelected ? Color(.tertiarySystemFill) : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct OptionTradeTopBar: View {
    let store: OptionTradeStore
    let close: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AppGlassIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: L10n.Common.back,
                action: close
            )

            Spacer(minLength: 12)

            Menu {
                ForEach(OptionTradeStore.supportedIntents) { intentOption in
                    Button {
                        TradeKeypadHaptics.selection()
                        store.intent = intentOption
                    } label: {
                        let label = L10n.Trade.optionIntentTitle(intentOption, locale: locale)
                        if store.intent == intentOption {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.Trade.optionIntentTitle(store.intent, locale: locale))
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
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .frame(height: 44)
    }
}

private struct OptionTradeContractBanner: View {
    let store: OptionTradeStore

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.descriptor.underlyingSymbol)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(store.descriptor.strikeText)
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)

                    Text(store.descriptor.typeText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(store.snapshotModel.typeTint)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(store.snapshotModel.typeTint.opacity(0.13), in: Capsule())
                }
                .lineLimit(1)

                Text(subtitleText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(capacityPrimaryValue)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(capacityLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var subtitleText: String {
        let priceText = L10n.Trade.limitMarketPrice(
            OptionTradeFormat.optionPrice(store.marketReferencePrice),
            locale: locale
        )
        return "\(store.descriptor.expirationText) · \(priceText)"
    }

    private var capacityLabel: String {
        switch store.intent {
        case .buyToOpen:
            return L10n.Trade.optionBuyingPower(locale: locale)
        case .sellToClose:
            return L10n.Trade.optionLongAvailable(locale: locale)
        case .buyToClose:
            return L10n.Trade.optionShortAvailable(locale: locale)
        case .sellToOpen:
            switch store.descriptor.type {
            case .call:
                return L10n.Trade.optionSharesAvailable(locale: locale)
            case .put, .none:
                return L10n.Trade.optionBuyingPower(locale: locale)
            }
        }
    }

    private var capacityPrimaryValue: String {
        let unit = L10n.Trade.optionContractUnit(locale: locale)
        switch store.intent {
        case .buyToOpen:
            return AppFormatter.money(store.optionsBuyingPower, currencyCode: store.currencyCode)
        case .sellToClose:
            return "\(OptionTradeFormat.wholeNumber(store.longContractsAvailable)) \(unit)"
        case .buyToClose:
            return "\(OptionTradeFormat.wholeNumber(store.shortContractsAvailable)) \(unit)"
        case .sellToOpen:
            switch store.descriptor.type {
            case .call:
                return "\(OptionTradeFormat.wholeNumber(store.underlyingSharesAvailable)) \(store.descriptor.underlyingSymbol)"
            case .put, .none:
                return AppFormatter.money(store.optionsBuyingPower, currencyCode: store.currencyCode)
            }
        }
    }
}

private struct OptionTradePriceCard: View {
    let store: OptionTradeStore
    let focusedField: FocusState<OptionTradeFocusedField?>.Binding

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
                    store.stepLimitPrice(steps: -1)
                }
                .disabled(!canStepPrice)

                HStack(alignment: .center, spacing: 2) {
                    Text("$")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(hasPrice ? .secondary : Color(.tertiaryLabel))
                        .fixedSize(horizontal: true, vertical: false)

                    TextField("0.00", text: limitPriceBinding)
                        .keyboardType(.decimalPad)
                        .focused(focusedField, equals: .limitPrice)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .tint(store.intent.side.tradeActionTint)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField.wrappedValue = .limitPrice
                }

                TradeLimitStepperButton(
                    systemImage: "plus",
                    accessibilityLabel: L10n.Trade.limitIncreasePrice(locale: locale)
                ) {
                    TradeKeypadHaptics.keyTap()
                    store.stepLimitPrice(steps: 1)
                }
                .disabled(!canStepPrice)
            }

            HStack(spacing: 8) {
                TradeLimitBookChip(
                    title: L10n.Trade.limitBid(locale: locale),
                    price: store.bidPrice,
                    currencyCode: store.currencyCode,
                    priceFormatter: OptionTradeFormat.optionPrice
                ) {
                    TradeKeypadHaptics.selection()
                    store.selectPrice(.bid)
                }

                TradeLimitBookChip(
                    title: L10n.Trade.limitMid(locale: locale),
                    price: store.midPrice ?? store.defaultLimitReferencePrice,
                    currencyCode: store.currencyCode,
                    priceFormatter: OptionTradeFormat.optionPrice
                ) {
                    TradeKeypadHaptics.selection()
                    store.selectPrice(.mid)
                }

                TradeLimitBookChip(
                    title: L10n.Trade.limitAsk(locale: locale),
                    price: store.askPrice,
                    currencyCode: store.currencyCode,
                    priceFormatter: OptionTradeFormat.optionPrice
                ) {
                    TradeKeypadHaptics.selection()
                    store.selectPrice(.ask)
                }
            }
        }
        .padding(16)
        .background(
            AppTheme.ColorToken.groupedSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isFocused ? store.intent.side.tradeActionTint.opacity(0.55) : Color(.separator).opacity(0.16),
                    lineWidth: isFocused ? 1.5 : 0.75
                )
        }
    }

    private var limitPriceBinding: Binding<String> {
        Binding(
            get: { store.draft.limitPriceText },
            set: { store.setLimitPriceText($0) }
        )
    }

    private var isFocused: Bool {
        focusedField.wrappedValue == .limitPrice
    }

    private var hasPrice: Bool {
        !store.draft.limitPriceText.isEmpty
    }

    private var canStepPrice: Bool {
        hasPrice || store.defaultLimitReferencePrice != nil || store.marketReferencePrice != nil
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

private struct OptionTradeContractsCard: View {
    let store: OptionTradeStore
    let focusedField: FocusState<OptionTradeFocusedField?>.Binding

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(L10n.Trade.optionContracts(locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFocused ? .primary : .secondary)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Text(
                        store.intent.side == .buy
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0", text: contractsBinding)
                        .keyboardType(.numberPad)
                        .focused(focusedField, equals: .contracts)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .tint(store.intent.side.tradeActionTint)
                        .frame(maxWidth: 160)

                    Text(L10n.Trade.optionContractUnit(locale: locale))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 34)
                .frame(maxWidth: .infinity)
                .frame(height: 50, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField.wrappedValue = .contracts
                }

                if !store.draft.quantityText.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            TradeKeypadHaptics.keyTap()
                            store.setContractsText("")
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
            .frame(height: 50)

            TradeSimpleQuickFillRow(
                items: quickFillItems,
                selectedPercent: store.activeQuickFillPercent,
                style: .embedded,
                isDisabled: !store.quickFillAvailable
            ) { percent in
                TradeKeypadHaptics.selection()
                focusedField.wrappedValue = nil
                store.fillContracts(percent: percent)
            }
        }
        .padding(16)
        .background(
            AppTheme.ColorToken.groupedSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isFocused ? store.intent.side.tradeActionTint.opacity(0.55) : Color(.separator).opacity(0.16),
                    lineWidth: isFocused ? 1.5 : 0.75
                )
        }
    }

    private var contractsBinding: Binding<String> {
        Binding(
            get: { store.draft.quantityText },
            set: { store.setContractsText($0) }
        )
    }

    private var isFocused: Bool {
        focusedField.wrappedValue == .contracts
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

private struct OptionTradeErrorSection: View {
    let store: OptionTradeStore
    let canUseAPI: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        if let alert = activeAlert {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: alert.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(alert.tint)
                    .padding(.top, 1)

                Text(alert.text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(alert.tint == AppTheme.ColorToken.negative ? AppTheme.ColorToken.negative : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                alert.tint.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(alert.tint.opacity(0.24), lineWidth: 0.75)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }

    private var hasRequiredInputs: Bool {
        store.requestedContracts != nil && store.limitPrice != nil
    }

    private var activeAlert: TradeSimpleStatus? {
        if store.isLoading && store.account == nil {
            return nil
        }

        if !canUseAPI {
            return TradeSimpleStatus(
                systemImage: "key.fill",
                text: L10n.Trade.addCredentialsBeforeOrder(locale: locale),
                tint: AppTheme.ColorToken.warning
            )
        }

        if store.hasPermissionIssue, let error = store.validation.errors.first {
            return TradeSimpleStatus(
                systemImage: "exclamationmark.triangle.fill",
                text: error,
                tint: AppTheme.ColorToken.warning
            )
        }

        if hasRequiredInputs, let error = store.validation.errors.first {
            return TradeSimpleStatus(
                systemImage: "exclamationmark.circle.fill",
                text: error,
                tint: AppTheme.ColorToken.negative
            )
        }

        if let message = store.message, !message.isEmpty {
            return TradeSimpleStatus(
                systemImage: "info.circle.fill",
                text: message,
                tint: AppTheme.ColorToken.warning
            )
        }

        return nil
    }
}

private struct OptionTradeMetaRow: View {
    let store: OptionTradeStore

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            Text(store.draft.timeInForce.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    AppTheme.ColorToken.groupedSurface,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.16), lineWidth: 0.75)
                }

            Spacer(minLength: 8)

            Text(L10n.Trade.optionMultiplierValue(locale: locale))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct OptionTradeActionSection: View {
    let store: OptionTradeStore
    let canUseAPI: Bool
    let review: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        TradeSimpleActionButton(state: buttonState, action: review)
    }

    private var hasRequiredInputs: Bool {
        store.requestedContracts != nil && store.limitPrice != nil
    }

    private var buttonState: TradeSimpleActionButtonState {
        let tint = store.intent.side.tradeActionTint

        if store.isLoading && store.account == nil {
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

// MARK: - Option Trade Confirmation Sheet (Apple-Pay Style)

private struct OptionTradeConfirmationSheet: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let snapshot: OptionTradeConfirmationSnapshot
    let onSubmit: () async -> TradeSubmitResult
    let onSubmitted: (AlpacaOrder) -> Void

    @State private var isSubmitting = false

    var body: some View {
        AppActionSheetContainer(
            title: L10n.Trade.simpleReviewOrder(locale: locale),
            isSubmitting: isSubmitting,
            minHeight: 440,
            maxHeight: 720,
            fallbackHeight: 310 + CGFloat(detailItems.count) * 46
        ) {
            VStack(spacing: 0) {
                OptionTradeConfirmationHeroHeader(snapshot: snapshot)
                    .padding(.top, 6)
                    .padding(.bottom, 22)

                AppSheetInfoCard(items: detailItems)

                AppSheetActionButton(
                    title: actionButtonTitle,
                    accessibilityTitle: actionButtonTitle,
                    submittingTitle: L10n.Trade.simpleSubmitting(locale: locale),
                    tint: snapshot.intent.side.tradeActionTint,
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
        L10n.Trade.optionIntentTitle(snapshot.intent, locale: locale)
    }

    private var detailItems: [AppSheetInfoItem] {
        [
            AppSheetInfoItem(
                title: L10n.Trade.confirmEnvironment(locale: locale),
                value: snapshot.environment.titleText(locale: locale)
            ),
            AppSheetInfoItem(
                title: L10n.Trade.optionContractSymbol(locale: locale),
                value: snapshot.descriptor.symbol,
                isMonospaced: true
            ),
            AppSheetInfoItem(
                title: L10n.Trade.confirmLimitPrice(locale: locale),
                value: OptionTradeFormat.optionPrice(snapshot.estimatedExecutionPrice)
            ),
            AppSheetInfoItem(
                title: L10n.Trade.confirmTimeInForce(locale: locale),
                value: snapshot.order.timeInForce.title
            ),
            AppSheetInfoItem(
                title: L10n.Trade.optionMultiplier(locale: locale),
                value: L10n.Trade.optionMultiplierValue(locale: locale)
            )
        ]
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

    private func showToastAfterSheetDismissal(_ feedback: OptionTradeConfirmationFeedback) {
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

private struct OptionTradeConfirmationHeroHeader: View {
    @Environment(\.locale) private var locale

    let snapshot: OptionTradeConfirmationSnapshot

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            AppSheetBadgePill(title: badgeText, tint: sideTint)

            Text(AppFormatter.money(snapshot.estimatedNotional, currencyCode: snapshot.currencyCode))
                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.top, 14)

            Text(contractSummaryText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.top, 6)

            Text(L10n.Trade.optionExpiration(snapshot.descriptor.expirationText, locale: locale))
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var sideTint: Color {
        snapshot.intent.side.tradeActionTint
    }

    private var badgeText: String {
        let intentLabel = L10n.Trade.optionIntentTitle(snapshot.intent, locale: locale)
        let orderTypeLabel = L10n.Trade.simpleOrderTypeTitle(
            orderType: OrderType.limit.titleText(locale: locale),
            locale: locale
        )
        return "\(intentLabel) · \(orderTypeLabel)"
    }

    private var contractSummaryText: String {
        let qty = OrderDraft.normalizedSizeText(snapshot.order.quantityText)
        let unit = L10n.Trade.optionContractUnit(locale: locale)
        return "\(qty) \(unit) · \(snapshot.descriptor.underlyingSymbol) \(snapshot.descriptor.strikeText) \(snapshot.descriptor.typeText)"
    }
}

private enum OptionTradeConfirmationFeedback {
    case success(String)
    case error(String)
}

// MARK: - Formatting

private enum OptionTradeFormat {
    static func optionPrice(_ value: Decimal?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return AppFormatter.money(value, fractionLength: optionPriceFractionLength(value))
    }

    static func wholeNumber(_ value: Decimal) -> String {
        var copy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private static func optionPriceFractionLength(_ value: Decimal) -> Int {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        return OptionValueText.moneyFractionLength(for: doubleValue)
    }
}
