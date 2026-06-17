import Foundation
import Observation
import RxSwift

struct TradeContext: Sendable {
    let account: AlpacaAccount
    let asset: AlpacaAsset
    let position: AlpacaPosition?
    let snapshot: AlpacaStockSnapshot?
    let feed: AlpacaMarketDataFeed
    let activeSession: MarketSessionKind?
}

struct TradeSeedContext: Sendable {
    let account: AlpacaAccount?
    let asset: AlpacaAsset?
    let position: AlpacaPosition?
    let latestQuote: AlpacaRealtimeQuote?
    let latestTrade: AlpacaRealtimeTrade?
    let feed: AlpacaMarketDataFeed

    init(
        account: AlpacaAccount? = nil,
        asset: AlpacaAsset? = nil,
        position: AlpacaPosition? = nil,
        latestQuote: AlpacaRealtimeQuote? = nil,
        latestTrade: AlpacaRealtimeTrade? = nil,
        feed: AlpacaMarketDataFeed = .iex
    ) {
        self.account = account
        self.asset = asset
        self.position = position
        self.latestQuote = latestQuote
        self.latestTrade = latestTrade
        self.feed = feed
    }
}

enum TradeSizingMode: String, CaseIterable, Identifiable {
    case shares
    case notional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shares:
            "Shares"
        case .notional:
            "Amount"
        }
    }
}

enum TradeValidationIssueKind: Equatable {
    case generic
    case missingInput
    case buyExceedsBuyingPower
    case sellExceedsPosition
    case shortExceedsBuyingPower
    case fractionalShortSaleUnsupported
}

struct TradeValidationIssue: Equatable {
    let kind: TradeValidationIssueKind
    let message: String

    static func generic(_ message: String) -> TradeValidationIssue {
        TradeValidationIssue(kind: .generic, message: message)
    }
}

struct TradeValidationResult: Equatable {
    let issues: [TradeValidationIssue]
    let warnings: [String]

    static let empty = TradeValidationResult(issues: [], warnings: [])

    var errors: [String] {
        issues.map(\.message)
    }

    var firstIssue: TradeValidationIssue? {
        issues.first
    }

    var canSubmit: Bool {
        issues.isEmpty
    }
}

private enum TradeQuoteStreamUpdate {
    case connection(AssetRealtimeConnectionStatus)
    case trade(AlpacaRealtimeTrade)
    case quote(AlpacaRealtimeQuote)
}

private struct TradeContextRequest: Equatable {
    let symbol: String
    let feed: AlpacaMarketDataFeed
    let force: Bool
}

private enum TradeContextLoadEvent {
    case success(symbol: String, context: TradeContext)
    case snapshot(symbol: String, snapshot: AlpacaResolvedStockSnapshot)
    case failure(symbol: String, error: Error)
}

@MainActor
@Observable
final class TradeStore {
    var draft: OrderDraft {
        didSet { refreshDerivedState() }
    }
    var sizingMode: TradeSizingMode
    var context: TradeContext? {
        didSet { refreshDerivedState() }
    }
    var realtimeQuote: AlpacaRealtimeQuote? {
        didSet { refreshDerivedState() }
    }
    var realtimeTrade: AlpacaRealtimeTrade? {
        didSet { refreshDerivedState() }
    }
    var feed: AlpacaMarketDataFeed = .iex
    var quoteConnectionStatus: AssetRealtimeConnectionStatus = .disconnected
    var isLoadingContext = false {
        didSet { refreshDerivedState() }
    }
    var isSubmitting = false
    var message: String?
    private(set) var contextErrorMessage: String?
    var submittedOrder: AlpacaOrder?
    private var locale = AppLocale.current
    private var optimisticAccount: AlpacaAccount?
    private var optimisticAsset: AlpacaAsset?
    private var optimisticPosition: AlpacaPosition?
    private var estimatedNotionalSnapshot: Decimal?
    private var estimatedExecutionPriceSnapshot: Decimal?
    private var validationSnapshot: TradeValidationResult = .empty

    @ObservationIgnored private var contextSymbol: String?
    @ObservationIgnored private var contextDisposeBag = DisposeBag()
    @ObservationIgnored private let contextRequestSubject = PublishSubject<TradeContextRequest>()
    @ObservationIgnored private var isContextPipelineBound = false
    @ObservationIgnored private var quoteDisposeBag = DisposeBag()
    @ObservationIgnored private var quoteSymbol: String?
    @ObservationIgnored private var quoteFeed: AlpacaMarketDataFeed?
    @ObservationIgnored private let quoteScheduler = SerialDispatchQueueScheduler(qos: .userInitiated)

    init(
        symbol: String? = nil,
        side: OrderSide = .buy,
        orderType: OrderType = .market,
        sizingMode: TradeSizingMode? = nil,
        seed: TradeSeedContext? = nil
    ) {
        var draft = OrderDraft()
        if let symbol {
            draft.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        draft.side = side
        draft.orderType = orderType
        feed = seed?.feed ?? .iex
        optimisticAccount = seed?.account
        optimisticAsset = seed?.asset
        optimisticPosition = seed?.position
        realtimeQuote = seed?.latestQuote
        realtimeTrade = seed?.latestTrade
        if let account = seed?.account, let asset = seed?.asset {
            context = TradeContext(
                account: account,
                asset: asset,
                position: seed?.position,
                snapshot: nil,
                feed: seed?.feed ?? .iex,
                activeSession: nil
            )
        }
        self.draft = draft
        self.sizingMode = sizingMode ?? (draft.notionalText.isEmpty ? .shares : .notional)
        refreshDerivedState()
    }

    func updateLocale(_ locale: Locale) {
        let resolvedLocale = AppLocale.resolvedLocale(for: locale)
        guard self.locale.identifier != resolvedLocale.identifier else {
            return
        }

        self.locale = resolvedLocale
        refreshDerivedState()
    }

    var normalizedSymbol: String {
        draft.normalizedSymbol
    }

    var assetDisplayName: String {
        currentAsset?.name?.displayAssetName ?? AppFormatter.placeholder
    }

    var bidPrice: Decimal? {
        decimal(realtimeQuote?.bidPrice)
            ?? decimal(context?.snapshot?.latestQuote?.bidPrice)
    }

    var askPrice: Decimal? {
        decimal(realtimeQuote?.askPrice)
            ?? decimal(context?.snapshot?.latestQuote?.askPrice)
    }

    var lastPrice: Decimal? {
        decimal(realtimeTrade?.price)
            ?? decimal(context?.snapshot?.latestTrade?.price)
            ?? decimal(context?.snapshot?.dailyBar?.close)
            ?? decimal(context?.snapshot?.minuteBar?.close)
    }

    var defaultLimitReferencePrice: Decimal? {
        if let bidPrice, let askPrice, bidPrice > 0, askPrice > 0 {
            return (bidPrice + askPrice) / 2
        }
        return lastPrice
    }

    var bidSize: Double? {
        realtimeQuote?.bidSize
            ?? context?.snapshot?.latestQuote?.bidSize
    }

    var askSize: Double? {
        realtimeQuote?.askSize
            ?? context?.snapshot?.latestQuote?.askSize
    }

    var quoteTimestamp: String? {
        realtimeTrade?.timestamp
            ?? context?.snapshot?.latestTrade?.timestamp
            ?? realtimeQuote?.timestamp
            ?? context?.snapshot?.latestQuote?.timestamp
    }

    var currencyCode: String {
        currentAccount?.currency ?? "USD"
    }

    var buyingPower: Decimal? {
        NumberParser.decimal(from: currentAccount?.buyingPower)
    }

    var cash: Decimal? {
        NumberParser.decimal(from: currentAccount?.cash)
    }

    var positionQuantity: Decimal {
        NumberParser.decimal(from: currentPosition?.quantity) ?? 0
    }

    var positionMarketValue: Decimal {
        NumberParser.decimal(from: currentPosition?.marketValue) ?? 0
    }

    var canOpenShortPosition: Bool {
        currentAccount?.shortingEnabled == true && currentAsset?.shortable == true
    }

    var sellQuickFillQuantityBase: Decimal? {
        if positionQuantity > 0 {
            return positionQuantity
        }

        guard canOpenShortPosition,
              let buyingPower,
              let estimatedExecutionPrice,
              estimatedExecutionPrice > 0 else {
            return nil
        }

        return buyingPower / estimatedExecutionPrice
    }

    var sellQuickFillNotionalBase: Decimal? {
        if positionQuantity > 0 {
            if let estimatedExecutionPrice, estimatedExecutionPrice > 0 {
                return positionQuantity * estimatedExecutionPrice
            }

            if positionMarketValue > 0 {
                return positionMarketValue
            }
        }

        return canOpenShortPosition ? buyingPower : nil
    }

    var estimatedNotional: Decimal? {
        estimatedNotionalSnapshot
    }

    var estimatedExecutionPrice: Decimal? {
        estimatedExecutionPriceSnapshot
    }

    var validation: TradeValidationResult {
        validationSnapshot
    }

    var isExtendedHoursSession: Bool {
        guard let activeSession = context?.activeSession else {
            return false
        }

        return activeSession != .regular
    }

    var supportsNotionalOrder: Bool {
        draft.orderType == .market && draft.timeInForce == .day && !draft.extendedHours
    }

    private var currentAccount: AlpacaAccount? {
        context?.account ?? optimisticAccount
    }

    private var currentAsset: AlpacaAsset? {
        context?.asset ?? optimisticAsset
    }

    private var currentPosition: AlpacaPosition? {
        context?.position ?? optimisticPosition
    }

    private func refreshDerivedState() {
        let executionPrice = calculateEstimatedExecutionPrice()
        let notional = calculateEstimatedNotional(executionPrice: executionPrice)

        if estimatedExecutionPriceSnapshot != executionPrice {
            estimatedExecutionPriceSnapshot = executionPrice
        }
        if estimatedNotionalSnapshot != notional {
            estimatedNotionalSnapshot = notional
        }

        let nextValidation = makeValidation(
            estimatedNotional: notional,
            estimatedExecutionPrice: executionPrice
        )
        if validationSnapshot != nextValidation {
            validationSnapshot = nextValidation
        }
    }

    private func calculateEstimatedNotional(executionPrice: Decimal?) -> Decimal? {
        if let notional = Self.positiveSizeDecimal(from: draft.notionalText) {
            return notional
        }

        guard let quantity = Self.positiveSizeDecimal(from: draft.quantityText),
              let executionPrice else {
            return nil
        }

        return quantity * executionPrice
    }

    private func calculateEstimatedExecutionPrice() -> Decimal? {
        if draft.orderType.requiresLimitPrice,
           let limitPrice = NumberParser.decimal(from: draft.limitPriceText) {
            return limitPrice
        }

        switch draft.side {
        case .buy:
            return askPrice ?? lastPrice
        case .sell:
            return bidPrice ?? lastPrice
        }
    }

    private func makeValidation(
        estimatedNotional: Decimal?,
        estimatedExecutionPrice: Decimal?
    ) -> TradeValidationResult {
        var issues: [TradeValidationIssue] = []
        var warnings: [String] = []

        do {
            _ = try draft.requestPayload()
        } catch let error as OrderDraftError {
            issues.append(TradeValidationIssue(
                kind: error.tradeValidationIssueKind,
                message: error.errorDescription(locale: locale)
            ))
        } catch {
            issues.append(.generic(error.localizedDescription))
        }

        guard let context else {
            if !isLoadingContext {
                issues.append(.generic(L10n.Trade.contextNotLoaded(locale: locale)))
            }
            return TradeValidationResult(issues: Self.unique(issues), warnings: Self.unique(warnings))
        }

        if context.account.tradingBlocked == true || context.account.accountBlocked == true || context.account.tradeSuspendedByUser == true {
            issues.append(.generic(L10n.Trade.accountTradingBlocked(locale: locale)))
        }

        if context.asset.tradable != true || context.asset.status?.lowercased() != "active" {
            issues.append(.generic(L10n.Trade.assetNotTradable(locale: locale)))
        }

        let requestedQuantity = requestedQuantity(estimatedExecutionPrice: estimatedExecutionPrice)
        let usesFractionalQuantity = (requestedQuantity ?? Self.positiveSizeDecimal(from: draft.quantityText) ?? 0).isFractional
        let usesNotional = Self.positiveSizeDecimal(from: draft.notionalText) != nil
        if (usesFractionalQuantity || usesNotional), context.asset.fractionable != true {
            issues.append(.generic(L10n.Trade.assetNotFractionable(locale: locale)))
        }

        if usesFractionalQuantity, draft.timeInForce != .day {
            issues.append(.generic(L10n.Trade.fractionalRequiresDay(locale: locale)))
        }

        if usesNotional, draft.timeInForce != .day {
            issues.append(.generic(L10n.Trade.notionalRequiresDay(locale: locale)))
        }

        if draft.side == .buy {
            if let estimatedNotional, let buyingPower, estimatedNotional > buyingPower {
                issues.append(TradeValidationIssue(
                    kind: .buyExceedsBuyingPower,
                    message: L10n.Trade.buyExceedsBuyingPower(locale: locale)
                ))
            }
        } else if let requestedQuantity, requestedQuantity > positionQuantity {
            let shortQuantity = requestedQuantity - max(positionQuantity, 0)

            if context.account.shortingEnabled != true || context.asset.shortable != true {
                issues.append(TradeValidationIssue(
                    kind: .sellExceedsPosition,
                    message: L10n.Trade.sellExceedsPosition(locale: locale)
                ))
            } else if usesFractionalQuantity || usesNotional || shortQuantity.isFractional {
                issues.append(TradeValidationIssue(
                    kind: .fractionalShortSaleUnsupported,
                    message: L10n.Trade.fractionalShortUnsupported(locale: locale)
                ))
            } else if let shortOrderValue = estimatedShortOrderValue(shortQuantity: shortQuantity),
                      let buyingPower,
                      shortOrderValue > buyingPower {
                issues.append(TradeValidationIssue(
                    kind: .shortExceedsBuyingPower,
                    message: L10n.Trade.shortExceedsBuyingPower(locale: locale)
                ))
            }
        }

        if draft.orderType == .market, draft.extendedHours {
            issues.append(.generic(L10n.Trade.marketExtendedHoursUnsupported(locale: locale)))
        }

        if estimatedExecutionPrice == nil {
            warnings.append(L10n.Trade.executionPriceUnavailable(locale: locale))
        }

        return TradeValidationResult(issues: Self.unique(issues), warnings: Self.unique(warnings))
    }

    private func requestedQuantity(estimatedExecutionPrice: Decimal?) -> Decimal? {
        if let quantity = Self.positiveSizeDecimal(from: draft.quantityText) {
            return quantity
        }

        guard let notional = Self.positiveSizeDecimal(from: draft.notionalText),
              let estimatedExecutionPrice,
              estimatedExecutionPrice > 0 else {
            return nil
        }

        return notional / estimatedExecutionPrice
    }

    private func estimatedShortOrderValue(shortQuantity: Decimal) -> Decimal? {
        guard shortQuantity > 0 else {
            return nil
        }

        let askWithBuffer = askPrice.map { $0 * Decimal(103) / Decimal(100) }
        let referencePrice: Decimal?

        if draft.orderType.requiresLimitPrice {
            let limitPrice = NumberParser.decimal(from: draft.limitPriceText)
            if let limitPrice, let askWithBuffer {
                referencePrice = max(limitPrice, askWithBuffer)
            } else {
                referencePrice = limitPrice ?? askWithBuffer ?? estimatedExecutionPrice
            }
        } else {
            referencePrice = askWithBuffer ?? estimatedExecutionPrice
        }

        guard let referencePrice, referencePrice > 0 else {
            return nil
        }

        return shortQuantity * referencePrice
    }

    func loadContext(app: AppModel, force: Bool = false) {
        updateLocale(app.appLanguage.locale)

        guard !normalizedSymbol.isEmpty else {
            context = nil
            stopPolling()
            return
        }

        bindContextPipeline(app: app)
        startQuoteStream(app: app)

        if contextSymbol == normalizedSymbol, !force, context != nil {
            return
        }

        message = nil
        contextErrorMessage = nil

        let symbol = normalizedSymbol
        contextSymbol = symbol
        let currentAssetSymbol = (context?.asset.symbol ?? optimisticAsset?.symbol)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if currentAssetSymbol != symbol {
            context = nil
            optimisticAccount = nil
            optimisticAsset = nil
            optimisticPosition = nil
            realtimeQuote = nil
            realtimeTrade = nil
            if draft.orderType.requiresLimitPrice {
                draft.limitPriceText = ""
            }
        }

        isLoadingContext = true
        contextRequestSubject.onNext(TradeContextRequest(symbol: symbol, feed: feed, force: force))
    }

    func stopPolling() {
        contextDisposeBag = DisposeBag()
        isContextPipelineBound = false
        contextSymbol = nil
        quoteDisposeBag = DisposeBag()
        quoteSymbol = nil
        quoteFeed = nil
        realtimeQuote = nil
        realtimeTrade = nil
        quoteConnectionStatus = .disconnected
        isLoadingContext = false
    }

    private func bindContextPipeline(app: AppModel) {
        guard !isContextPipelineBound else {
            return
        }

        isContextPipelineBound = true
        contextRequestSubject
            .filter { !$0.symbol.isEmpty }
            .distinctUntilChanged { lhs, rhs in
                lhs.symbol == rhs.symbol
                    && lhs.feed == rhs.feed
                    && !lhs.force
                    && !rhs.force
            }
            .flatMapLatest { request in
                tradeContextLoadEvents(for: request, app: app)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self, weak app] event in
                guard let self, let app else { return }
                self.applyContextLoadEvent(event, app: app)
            })
            .disposed(by: contextDisposeBag)
    }

    private func applyContextLoadEvent(_ event: TradeContextLoadEvent, app: AppModel) {
        switch event {
        case .success(let symbol, let context):
            guard normalizedSymbol == symbol else {
                return
            }

            let previousFeed = feed
            feed = context.feed
            optimisticAccount = context.account
            optimisticAsset = context.asset
            optimisticPosition = context.position
            self.context = context
            if previousFeed != feed {
                startQuoteStream(app: app)
            }
            applySnapshotQuote(context.snapshot, symbol: symbol)
            applySessionDefaults()
            fillDefaultLimitPriceIfNeeded()
            isLoadingContext = false
            message = nil
            contextErrorMessage = nil
        case .snapshot(let symbol, let snapshot):
            guard normalizedSymbol == symbol else {
                return
            }

            let previousFeed = feed
            feed = snapshot.feed
            if let context {
                self.context = TradeContext(
                    account: context.account,
                    asset: context.asset,
                    position: context.position,
                    snapshot: snapshot.snapshot,
                    feed: snapshot.feed,
                    activeSession: snapshot.activeSession
                )
            }
            if previousFeed != feed {
                startQuoteStream(app: app)
            }
            applySnapshotQuote(snapshot.snapshot, symbol: symbol)
            applySessionDefaults()
            fillDefaultLimitPriceIfNeeded()
        case .failure(let symbol, let error):
            guard normalizedSymbol == symbol else {
                return
            }

            self.message = nil
            contextErrorMessage = APIErrorDisplayMessage.message(for: error, locale: app.appLanguage.locale)
            isLoadingContext = false
        }
    }

    private func startQuoteStream(app: AppModel) {
        let symbol = normalizedSymbol
        let streamFeed = feed
        guard quoteSymbol != symbol || quoteFeed != streamFeed else {
            return
        }

        quoteDisposeBag = DisposeBag()
        realtimeQuote = nil
        realtimeTrade = nil
        quoteConnectionStatus = .connecting
        quoteSymbol = symbol
        quoteFeed = streamFeed

        do {
            let source = try app.streamTradeQuoteEvents(symbol: symbol, feed: streamFeed)
            tradeQuoteStreamUpdates(from: source, scheduler: quoteScheduler)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] update in
                    guard let self, self.normalizedSymbol == symbol else { return }
                    self.applyQuoteStreamUpdate(update)
                }, onError: { [weak self] error in
                    guard let self, self.normalizedSymbol == symbol else { return }
                    self.quoteConnectionStatus = .failed(error.localizedDescription)
                })
                .disposed(by: quoteDisposeBag)
        } catch {
            quoteConnectionStatus = .failed(error.localizedDescription)
        }
    }

    private func applySessionDefaults() {
        if !isExtendedHoursSession {
            draft.extendedHours = false
        }
    }

    private func applySnapshotQuote(_ snapshot: AlpacaStockSnapshot?, symbol: String) {
        guard realtimeQuote == nil,
              let latestQuote = snapshot?.latestQuote else {
            return
        }

        realtimeQuote = AlpacaRealtimeQuote(
            symbol: symbol,
            askExchange: latestQuote.askExchange,
            askPrice: latestQuote.askPrice,
            askSize: latestQuote.askSize,
            bidExchange: latestQuote.bidExchange,
            bidPrice: latestQuote.bidPrice,
            bidSize: latestQuote.bidSize,
            conditions: latestQuote.conditions,
            timestamp: latestQuote.timestamp,
            tape: latestQuote.tape
        )
        fillDefaultLimitPriceIfNeeded()
    }

    private func applyQuoteStreamUpdate(_ update: TradeQuoteStreamUpdate) {
        switch update {
        case .connection(let status):
            if quoteConnectionStatus != status {
                quoteConnectionStatus = status
            }
        case .trade(let trade):
            if realtimeTrade != trade {
                realtimeTrade = trade
                fillDefaultLimitPriceIfNeeded()
            }
            if quoteConnectionStatus != .live {
                quoteConnectionStatus = .live
            }
        case .quote(let quote):
            if realtimeQuote != quote {
                realtimeQuote = quote
                fillDefaultLimitPriceIfNeeded()
            }
            if quoteConnectionStatus != .live {
                quoteConnectionStatus = .live
            }
        }
    }

    func setSizingMode(_ mode: TradeSizingMode) {
        sizingMode = mode
        switch mode {
        case .shares:
            draft.notionalText = ""
        case .notional:
            draft.quantityText = ""
        }
    }

    func prepareMarketOrder() {
        draft.orderType = .market
        draft.timeInForce = .day
        normalizeForOrderType(.market)
    }

    func prepareLimitOrder() {
        message = nil
        draft.orderType = .limit
        setSizingMode(.shares)
        fillDefaultLimitPriceIfNeeded()
    }

    func normalizeForOrderType(_ orderType: OrderType) {
        if orderType != .limit {
            draft.extendedHours = false
        }

        if !orderType.requiresLimitPrice {
            draft.limitPriceText = ""
        } else {
            fillDefaultLimitPriceIfNeeded()
        }
    }

    func normalizeForTimeInForce(_ timeInForce: TimeInForce) {
        if !(timeInForce == .day || timeInForce == .gtc) {
            draft.extendedHours = false
        }
    }

    func fillLimitFromBid() {
        guard let bidPrice else { return }
        draft.orderType = .limit
        draft.limitPriceText = Self.apiPriceNumber(bidPrice)
    }

    func fillLimitFromAsk() {
        guard let askPrice else { return }
        draft.orderType = .limit
        draft.limitPriceText = Self.apiPriceNumber(askPrice)
    }

    func fillLimitFromMid() {
        guard let lastPrice else { return }
        draft.orderType = .limit
        draft.limitPriceText = Self.apiPriceNumber(lastPrice)
    }

    func fillDefaultLimitPriceIfNeeded() {
        guard draft.orderType.requiresLimitPrice,
              NumberText.trimTrailingZeros(draft.limitPriceText).isEmpty,
              let price = defaultLimitReferencePrice else {
            return
        }

        draft.limitPriceText = Self.apiPriceNumber(price)
    }

    func fillQuantity(percent: Decimal) {
        switch draft.side {
        case .buy:
            guard let buyingPower, let price = estimatedExecutionPrice, price > 0 else { return }
            let quantity = (buyingPower * percent) / price
            setSizingMode(.shares)
            draft.quantityText = Self.apiNumber(quantity, scale: 6)
        case .sell:
            guard let base = sellQuickFillQuantityBase else { return }
            setSizingMode(.shares)
            draft.quantityText = Self.apiNumber(base * percent, scale: 6)
        }
    }

    func fillNotional(percent: Decimal) {
        let base: Decimal?
        switch draft.side {
        case .buy:
            base = buyingPower
        case .sell:
            base = sellQuickFillNotionalBase
        }

        guard let base else { return }
        setSizingMode(.notional)
        draft.notionalText = Self.apiNumber(base * percent, scale: 2)
    }

    func submit(app: AppModel, clientOrderID: String?) async -> TradeSubmitResult {
        await submit(draft, clientOrderID: clientOrderID, app: app)
    }

    func submit(_ orderDraft: OrderDraft, clientOrderID: String?, app: AppModel) async -> TradeSubmitResult {
        updateLocale(app.appLanguage.locale)

        guard !isSubmitting else {
            return .failure(L10n.Trade.simpleSubmitting(locale: locale))
        }

        if draft != orderDraft {
            draft = orderDraft
        }

        let currentValidation = validation
        guard currentValidation.canSubmit else {
            let errorMessage = currentValidation.errors.first ?? L10n.Trade.simpleOrderUnavailable(locale: locale)
            message = errorMessage
            return .failure(errorMessage)
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let result = await app.submit(orderDraft, clientOrderID: clientOrderID)
        switch result {
        case .success(let order):
            submittedOrder = order
            message = L10n.Trade.orderSubmitted(locale: locale)
            loadContext(app: app, force: true)
            return .success(order)
        case .failure(let errorMessage):
            return .failure(errorMessage)
        }
    }

    private func decimal(_ value: Double?) -> Decimal? {
        guard let value else { return nil }
        return Decimal(value)
    }

    private static func apiNumber(_ value: Decimal, scale: Int) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, scale, .plain)
        return NumberText.trimTrailingZeros(NSDecimalNumber(decimal: rounded).stringValue)
    }

    private static func apiPriceNumber(_ value: Decimal) -> String {
        apiNumber(value, scale: value >= 1 ? 2 : 4)
    }

    private static func positiveSizeDecimal(from text: String) -> Decimal? {
        NumberParser.decimal(from: OrderDraft.normalizedSizeText(text))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func unique(_ values: [TradeValidationIssue]) -> [TradeValidationIssue] {
        var seen = Set<String>()
        return values.filter { seen.insert("\($0.kind)-\($0.message)").inserted }
    }
}

private final class TradeContextLoadObserverBox: @unchecked Sendable {
    private let observer: AnyObserver<TradeContextLoadEvent>

    init(_ observer: AnyObserver<TradeContextLoadEvent>) {
        self.observer = observer
    }

    @MainActor
    func onNext(_ event: TradeContextLoadEvent) {
        observer.onNext(event)
    }
}

private func tradeContextLoadEvents(
    for request: TradeContextRequest,
    app: AppModel
) -> Observable<TradeContextLoadEvent> {
    Observable.create { observer in
        let observerBox = TradeContextLoadObserverBox(observer)
        let task = Task { @MainActor [app, request, observerBox] in
            do {
                async let snapshotRequest: AlpacaResolvedStockSnapshot? = try? app.fetchTradeSnapshot(
                    symbol: request.symbol,
                    feed: request.feed
                )
                let context = try await app.fetchTradeCoreContext(symbol: request.symbol, feed: request.feed)
                try Task.checkCancellation()
                observerBox.onNext(.success(symbol: request.symbol, context: context))

                if let snapshot = await snapshotRequest {
                    try Task.checkCancellation()
                    observerBox.onNext(.snapshot(symbol: request.symbol, snapshot: snapshot))
                }
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                observerBox.onNext(.failure(symbol: request.symbol, error: error))
            }
        }

        return Disposables.create {
            task.cancel()
        }
    }
}

private func tradeQuoteStreamUpdates(
    from source: Observable<AssetRealtimeEvent>,
    scheduler: SerialDispatchQueueScheduler
) -> Observable<TradeQuoteStreamUpdate> {
    let shared = source
        .observe(on: scheduler)
        .share(replay: 0, scope: .whileConnected)

    let connectionUpdates = shared
        .compactMap { event -> AssetRealtimeConnectionStatus? in
            if case .connection(let status) = event {
                return status
            }
            return nil
        }
        .distinctUntilChanged()
        .map(TradeQuoteStreamUpdate.connection)

    let quoteUpdates = shared
        .compactMap { event -> TradeQuoteStreamUpdate? in
            if case .quote(let quote) = event {
                return .quote(quote)
            }
            return nil
        }
        .throttle(.milliseconds(120), latest: true, scheduler: scheduler)

    let tradeUpdates = shared
        .compactMap { event -> TradeQuoteStreamUpdate? in
            if case .trade(let trade) = event {
                return .trade(trade)
            }
            return nil
        }
        .throttle(.milliseconds(120), latest: true, scheduler: scheduler)

    return Observable.merge(connectionUpdates, quoteUpdates, tradeUpdates)
}

private extension Decimal {
    var isFractional: Bool {
        let number = NSDecimalNumber(decimal: self)
        return number.doubleValue.truncatingRemainder(dividingBy: 1) != 0
    }
}

private extension OrderDraftError {
    var tradeValidationIssueKind: TradeValidationIssueKind {
        switch self {
        case .missingSize:
            .missingInput
        default:
            .generic
        }
    }
}

private extension String {
    var displayAssetName: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = " Common Stock"

        guard value.range(of: suffix, options: [.caseInsensitive, .anchored, .backwards]) != nil else {
            return value
        }

        return String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
