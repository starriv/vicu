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

enum TradeExecutionPriceSource: Equatable {
    case limit
    case ask
    case bid
    case last
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
    var activeQuickFillPercent: Decimal?
    private(set) var contextErrorMessage: String?
    var submittedOrder: AlpacaOrder?
    private var locale = AppLocale.current
    private var optimisticAccount: AlpacaAccount?
    private var optimisticAsset: AlpacaAsset?
    private var optimisticPosition: AlpacaPosition?
    private var estimatedNotionalSnapshot: Decimal?
    private var estimatedQuantitySnapshot: Decimal?
    private var estimatedExecutionPriceSnapshot: Decimal?
    private var estimatedExecutionPriceSourceSnapshot: TradeExecutionPriceSource?
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
        Self.positivePriceDecimal(realtimeQuote?.bidPrice)
            ?? Self.positivePriceDecimal(context?.snapshot?.latestQuote?.bidPrice)
    }

    var askPrice: Decimal? {
        Self.positivePriceDecimal(realtimeQuote?.askPrice)
            ?? Self.positivePriceDecimal(context?.snapshot?.latestQuote?.askPrice)
    }

    var lastPrice: Decimal? {
        Self.positivePriceDecimal(realtimeTrade?.price)
            ?? Self.positivePriceDecimal(context?.snapshot?.latestTrade?.price)
            ?? Self.positivePriceDecimal(context?.snapshot?.minuteBar?.close)
            ?? Self.positivePriceDecimal(context?.snapshot?.dailyBar?.close)
            ?? Self.positivePriceDecimal(context?.snapshot?.previousDailyBar?.close)
            ?? positionCurrentPrice
    }

    private var positionCurrentPrice: Decimal? {
        guard let price = NumberParser.decimal(from: currentPosition?.currentPrice), price > 0 else {
            return nil
        }
        return price
    }

    var defaultLimitReferencePrice: Decimal? {
        if let bidPrice, let askPrice, bidPrice > 0, askPrice > 0, bidPrice <= askPrice {
            let mid = (bidPrice + askPrice) / 2
            if isReasonableQuote(mid, relativeTo: lastPrice) {
                return mid
            }
        }
        return lastPrice ?? askPrice ?? bidPrice
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
        if currentAsset?.marginable == false,
           let nonMarginable = NumberParser.decimal(from: currentAccount?.nonMarginableBuyingPower) {
            return max(nonMarginable, 0)
        }
        guard let raw = NumberParser.decimal(from: currentAccount?.buyingPower) else {
            return nil
        }
        return max(raw, 0)
    }

    var cash: Decimal? {
        NumberParser.decimal(from: currentAccount?.cash)
    }

    var positionQuantity: Decimal {
        NumberParser.decimal(from: currentPosition?.quantity) ?? 0
    }

    var availableSellQuantity: Decimal {
        guard positionQuantity > 0 else {
            return 0
        }
        if let available = NumberParser.decimal(from: currentPosition?.quantityAvailable) {
            return max(min(available, positionQuantity), 0)
        }
        return positionQuantity
    }

    var positionMarketValue: Decimal {
        NumberParser.decimal(from: currentPosition?.marketValue) ?? 0
    }

    var availableSellMarketValue: Decimal {
        guard availableSellQuantity > 0 else {
            return 0
        }
        if let price = estimatedExecutionPrice, price > 0 {
            return availableSellQuantity * price
        }
        if positionQuantity > 0, positionMarketValue > 0 {
            return positionMarketValue * (availableSellQuantity / positionQuantity)
        }
        return 0
    }

    var supportsFractionalShares: Bool {
        currentAsset?.fractionable ?? true
    }

    var maxShareInputScale: Int {
        guard supportsFractionalShares else { return 0 }
        if draft.timeInForce != .day {
            return 0
        }
        return 6
    }

    var marketReferencePrice: Decimal? {
        lastPrice ?? defaultLimitReferencePrice
    }

    var limitPriceDeltaFraction: Double? {
        guard draft.orderType.requiresLimitPrice,
              let limitPrice = NumberParser.decimal(from: draft.limitPriceText),
              limitPrice > 0,
              let reference = marketReferencePrice,
              reference > 0 else {
            return nil
        }

        let delta = (limitPrice - reference) / reference
        return NSDecimalNumber(decimal: delta).doubleValue
    }

    var canUseNotionalSizing: Bool {
        supportsNotionalOrder && supportsFractionalShares
    }

    var canOpenShortPosition: Bool {
        currentAccount?.shortingEnabled == true && currentAsset?.shortable == true
    }

    var sellQuickFillQuantityBase: Decimal? {
        if availableSellQuantity > 0 {
            return availableSellQuantity
        }

        guard positionQuantity <= 0,
              canOpenShortPosition,
              let buyingPower,
              let price = shortOrderReferencePrice,
              price > 0 else {
            return nil
        }

        return buyingPower / price
    }

    var sellQuickFillNotionalBase: Decimal? {
        if availableSellQuantity > 0 {
            let value = availableSellMarketValue
            return value > 0 ? value : nil
        }

        return nil
    }

    var quickFillAvailable: Bool {
        switch sizingMode {
        case .notional:
            guard canUseNotionalSizing else { return false }
            switch draft.side {
            case .buy:
                guard let buyingPower else { return false }
                return Self.rounded(buyingPower, scale: 2, mode: .down) > 0
            case .sell:
                guard let base = sellQuickFillNotionalBase else { return false }
                return Self.rounded(base, scale: 2, mode: .down) > 0
            }
        case .shares:
            switch draft.side {
            case .buy:
                guard let buyingPower, let price = estimatedExecutionPrice, price > 0 else { return false }
                return Self.rounded(buyingPower / price, scale: maxShareInputScale, mode: .down) > 0
            case .sell:
                guard let base = sellQuickFillQuantityBase else { return false }
                let scale = availableSellQuantity > 0 ? maxShareInputScale : 0
                return Self.rounded(base, scale: scale, mode: .down) > 0
            }
        }
    }

    var activeInputText: String {
        switch sizingMode {
        case .shares:
            draft.quantityText
        case .notional:
            draft.notionalText
        }
    }

    var estimatedNotional: Decimal? {
        estimatedNotionalSnapshot
    }

    var estimatedQuantity: Decimal? {
        estimatedQuantitySnapshot
    }

    var estimatedExecutionPrice: Decimal? {
        estimatedExecutionPriceSnapshot
    }

    var estimatedExecutionPriceSource: TradeExecutionPriceSource? {
        estimatedExecutionPriceSourceSnapshot
    }

    var validation: TradeValidationResult {
        validationSnapshot
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
        let resolvedExecution = calculateEstimatedExecutionPrice()
        let executionPrice = resolvedExecution.price
        let notional = calculateEstimatedNotional(executionPrice: executionPrice)
        let quantity = calculateEstimatedQuantity(executionPrice: executionPrice)

        if estimatedExecutionPriceSnapshot != executionPrice {
            estimatedExecutionPriceSnapshot = executionPrice
        }
        if estimatedExecutionPriceSourceSnapshot != resolvedExecution.source {
            estimatedExecutionPriceSourceSnapshot = resolvedExecution.source
        }
        if estimatedNotionalSnapshot != notional {
            estimatedNotionalSnapshot = notional
        }
        if estimatedQuantitySnapshot != quantity {
            estimatedQuantitySnapshot = quantity
        }

        let nextValidation = makeValidation(
            estimatedNotional: notional,
            estimatedQuantity: quantity,
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
              let executionPrice,
              executionPrice > 0 else {
            return nil
        }

        return quantity * executionPrice
    }

    private func calculateEstimatedQuantity(executionPrice: Decimal?) -> Decimal? {
        if let quantity = Self.positiveSizeDecimal(from: draft.quantityText) {
            return quantity
        }

        guard let notional = Self.positiveSizeDecimal(from: draft.notionalText),
              let executionPrice,
              executionPrice > 0 else {
            return nil
        }

        return Self.rounded(notional / executionPrice, scale: 6, mode: .down)
    }

    private func calculateEstimatedExecutionPrice() -> (price: Decimal?, source: TradeExecutionPriceSource?) {
        if draft.orderType.requiresLimitPrice,
           let limitPrice = NumberParser.decimal(from: draft.limitPriceText),
           limitPrice > 0 {
            return (limitPrice, .limit)
        }

        let referenceLast = lastPrice
        switch draft.side {
        case .buy:
            if let ask = askPrice, isReasonableQuote(ask, relativeTo: referenceLast) {
                return (ask, .ask)
            }
            if let referenceLast {
                return (referenceLast, .last)
            }
            if let bid = bidPrice {
                return (bid, .bid)
            }
            if let ask = askPrice {
                return (ask, .ask)
            }
            return (nil, nil)
        case .sell:
            if let bid = bidPrice, isReasonableQuote(bid, relativeTo: referenceLast) {
                return (bid, .bid)
            }
            if let referenceLast {
                return (referenceLast, .last)
            }
            if let ask = askPrice {
                return (ask, .ask)
            }
            if let bid = bidPrice {
                return (bid, .bid)
            }
            return (nil, nil)
        }
    }

    private func makeValidation(
        estimatedNotional: Decimal?,
        estimatedQuantity: Decimal?,
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

        let requestedQuantity = estimatedQuantity
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
        } else if let requestedQuantity, requestedQuantity > availableSellQuantity {
            if positionQuantity > availableSellQuantity {
                issues.append(TradeValidationIssue(
                    kind: .sellExceedsPosition,
                    message: L10n.Trade.sellExceedsPosition(locale: locale)
                ))
            } else {
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
        }

        if draft.orderType == .market, draft.extendedHours {
            issues.append(.generic(L10n.Trade.marketExtendedHoursUnsupported(locale: locale)))
        }

        if estimatedExecutionPrice == nil {
            warnings.append(L10n.Trade.executionPriceUnavailable(locale: locale))
        }

        return TradeValidationResult(issues: Self.unique(issues), warnings: Self.unique(warnings))
    }

    private var shortOrderReferencePrice: Decimal? {
        let validAsk = askPrice.flatMap { isReasonableQuote($0, relativeTo: lastPrice) ? $0 : nil }
        let askWithBuffer = (validAsk ?? lastPrice).map { $0 * Decimal(103) / Decimal(100) }

        if draft.orderType.requiresLimitPrice {
            let limitPrice = NumberParser.decimal(from: draft.limitPriceText)
            if let limitPrice, let askWithBuffer {
                return max(limitPrice, askWithBuffer)
            }
            return limitPrice ?? askWithBuffer ?? estimatedExecutionPrice
        }

        return askWithBuffer ?? estimatedExecutionPrice
    }

    private func estimatedShortOrderValue(shortQuantity: Decimal) -> Decimal? {
        guard shortQuantity > 0,
              let referencePrice = shortOrderReferencePrice,
              referencePrice > 0 else {
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
            if draft.orderType == .market,
               sizingMode == .notional,
               draft.notionalText.isEmpty,
               draft.quantityText.isEmpty,
               (context.asset.fractionable == false || (draft.side == .sell && availableSellQuantity <= 0)) {
                sizingMode = .shares
            }
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

    func setSizingMode(_ mode: TradeSizingMode, preserveValue: Bool = false) {
        if sizingMode == mode {
            return
        }

        message = nil
        let previousNotional = estimatedNotional
        let previousQuantity = estimatedQuantity
        let hadInput = !activeInputText.isEmpty

        sizingMode = mode
        switch mode {
        case .shares:
            var nextDraft = draft
            nextDraft.notionalText = ""
            if preserveValue {
                if hadInput, let previousQuantity, previousQuantity > 0 {
                    let scale = (draft.side == .sell && availableSellQuantity <= 0) ? 0 : maxShareInputScale
                    let roundedQty = Self.rounded(previousQuantity, scale: scale, mode: .down)
                    nextDraft.quantityText = roundedQty > 0 ? Self.apiNumber(roundedQty, scale: scale, mode: .down) : ""
                } else {
                    nextDraft.quantityText = ""
                }
            }
            if draft != nextDraft {
                draft = nextDraft
            }
        case .notional:
            var nextDraft = draft
            nextDraft.quantityText = ""
            if preserveValue {
                if hadInput, let previousNotional, previousNotional > 0 {
                    let roundedNotional = Self.rounded(previousNotional, scale: 2, mode: .down)
                    nextDraft.notionalText = roundedNotional > 0 ? Self.apiNumber(roundedNotional, scale: 2, mode: .down) : ""
                } else {
                    nextDraft.notionalText = ""
                }
            }
            if draft != nextDraft {
                draft = nextDraft
            }
        }
    }

    func toggleSizingMode() {
        let nextMode: TradeSizingMode = sizingMode == .notional ? .shares : .notional
        if nextMode == .notional, !canUseNotionalSizing {
            return
        }
        setSizingMode(nextMode, preserveValue: true)
    }

    func setSimpleInputText(_ sanitizedText: String) {
        message = nil
        activeQuickFillPercent = nil

        switch sizingMode {
        case .shares:
            if draft.quantityText != sanitizedText || !draft.notionalText.isEmpty {
                var nextDraft = draft
                nextDraft.quantityText = sanitizedText
                nextDraft.notionalText = ""
                draft = nextDraft
            }
        case .notional:
            if draft.notionalText != sanitizedText || !draft.quantityText.isEmpty {
                var nextDraft = draft
                nextDraft.notionalText = sanitizedText
                nextDraft.quantityText = ""
                draft = nextDraft
            }
        }
    }

    func prepareMarketOrder() {
        message = nil
        activeQuickFillPercent = nil
        var nextDraft = draft
        nextDraft.orderType = .market
        nextDraft.timeInForce = .day
        nextDraft.extendedHours = false
        nextDraft.limitPriceText = ""
        if draft != nextDraft {
            draft = nextDraft
        }
    }

    func prepareLimitOrder() {
        message = nil
        activeQuickFillPercent = nil
        var nextDraft = draft
        nextDraft.orderType = .limit
        if sizingMode == .notional {
            if let estimatedQuantity, estimatedQuantity > 0 {
                let scale = (draft.side == .sell && availableSellQuantity <= 0) ? 0 : maxShareInputScale
                let roundedQty = Self.rounded(estimatedQuantity, scale: scale, mode: .down)
                nextDraft.quantityText = roundedQty > 0 ? Self.apiNumber(roundedQty, scale: scale, mode: .down) : ""
            } else {
                nextDraft.quantityText = ""
            }
            nextDraft.notionalText = ""
            sizingMode = .shares
        }
        if draft != nextDraft {
            draft = nextDraft
        }
        fillDefaultLimitPriceIfNeeded()
    }

    func setLimitPriceText(_ sanitizedText: String) {
        message = nil
        if draft.side == .buy {
            activeQuickFillPercent = nil
        }
        if draft.limitPriceText != sanitizedText {
            draft.limitPriceText = sanitizedText
        }
    }

    func setLimitQuantityText(_ sanitizedText: String) {
        message = nil
        activeQuickFillPercent = nil
        if draft.quantityText != sanitizedText || !draft.notionalText.isEmpty {
            var nextDraft = draft
            nextDraft.quantityText = sanitizedText
            nextDraft.notionalText = ""
            draft = nextDraft
        }
    }

    func stepLimitPrice(steps: Int) {
        guard steps != 0 else { return }
        message = nil
        let current = NumberParser.decimal(from: draft.limitPriceText).flatMap { $0 > 0 ? $0 : nil }
            ?? defaultLimitReferencePrice
            ?? marketReferencePrice
        guard let base = current, base > 0 else { return }

        let tick: Decimal
        if base > 1 || (base == 1 && steps > 0) {
            tick = Decimal(string: "0.01")!
        } else if base == 1 && steps < 0 {
            tick = Decimal(string: "0.01")!
        } else {
            tick = Decimal(string: "0.0001")!
        }

        let minimumPrice = Decimal(string: "0.0001")!
        let next = max(minimumPrice, base + tick * Decimal(steps))
        let formatted = Self.apiPriceNumber(next)

        var nextDraft = draft
        nextDraft.orderType = .limit
        nextDraft.limitPriceText = formatted
        if draft.side == .buy {
            activeQuickFillPercent = nil
        }
        if draft != nextDraft {
            draft = nextDraft
        }
    }

    func setTimeInForce(_ timeInForce: TimeInForce) {
        message = nil
        var nextDraft = draft
        nextDraft.timeInForce = timeInForce
        if !(timeInForce == .day || timeInForce == .gtc) {
            nextDraft.extendedHours = false
        }
        if timeInForce != .day,
           let qty = Self.positiveSizeDecimal(from: nextDraft.quantityText),
           qty.isFractional {
            let floored = Self.rounded(qty, scale: 0, mode: .down)
            nextDraft.quantityText = floored > 0 ? Self.apiNumber(floored, scale: 0, mode: .down) : ""
            activeQuickFillPercent = nil
        }
        if draft != nextDraft {
            draft = nextDraft
        }
    }

    func setExtendedHours(_ enabled: Bool) {
        guard draft.orderType == .limit else { return }
        message = nil
        var nextDraft = draft
        nextDraft.extendedHours = enabled
        if enabled, !(nextDraft.timeInForce == .day || nextDraft.timeInForce == .gtc) {
            nextDraft.timeInForce = .day
        }
        if draft != nextDraft {
            draft = nextDraft
        }
    }

    func normalizeForOrderType(_ orderType: OrderType) {
        var nextDraft = draft
        if orderType != .limit {
            nextDraft.extendedHours = false
        }

        if !orderType.requiresLimitPrice {
            nextDraft.limitPriceText = ""
        }
        if draft != nextDraft {
            draft = nextDraft
        }
        if orderType.requiresLimitPrice {
            fillDefaultLimitPriceIfNeeded()
        }
    }

    func normalizeForTimeInForce(_ timeInForce: TimeInForce) {
        if !(timeInForce == .day || timeInForce == .gtc), draft.extendedHours {
            draft.extendedHours = false
        }
    }

    func fillLimitFromBid() {
        guard let bidPrice else { return }
        if draft.side == .buy {
            activeQuickFillPercent = nil
        }
        var nextDraft = draft
        nextDraft.orderType = .limit
        nextDraft.limitPriceText = Self.apiPriceNumber(bidPrice)
        if draft != nextDraft {
            draft = nextDraft
        }
    }

    func fillLimitFromAsk() {
        guard let askPrice else { return }
        if draft.side == .buy {
            activeQuickFillPercent = nil
        }
        var nextDraft = draft
        nextDraft.orderType = .limit
        nextDraft.limitPriceText = Self.apiPriceNumber(askPrice)
        if draft != nextDraft {
            draft = nextDraft
        }
    }

    func fillLimitFromMid() {
        guard let referencePrice = defaultLimitReferencePrice else { return }
        if draft.side == .buy {
            activeQuickFillPercent = nil
        }
        var nextDraft = draft
        nextDraft.orderType = .limit
        nextDraft.limitPriceText = Self.apiPriceNumber(referencePrice)
        if draft != nextDraft {
            draft = nextDraft
        }
    }

    func fillDefaultLimitPriceIfNeeded() {
        guard draft.orderType.requiresLimitPrice,
              NumberText.trimTrailingZeros(draft.limitPriceText).isEmpty,
              let price = defaultLimitReferencePrice else {
            return
        }

        let priceText = Self.apiPriceNumber(price)
        if draft.limitPriceText != priceText {
            draft.limitPriceText = priceText
        }
    }

    func fillQuickAmount(percent: Decimal) {
        message = nil
        switch sizingMode {
        case .shares:
            fillQuantity(percent: percent)
        case .notional:
            fillNotional(percent: percent)
        }
        activeQuickFillPercent = percent
    }

    func fillQuantity(percent: Decimal) {
        let clampedPercent = min(max(percent, 0), 1)
        let rawQuantity: Decimal
        let scale: Int

        switch draft.side {
        case .buy:
            guard let buyingPower, let price = estimatedExecutionPrice, price > 0 else { return }
            scale = maxShareInputScale
            rawQuantity = (buyingPower * clampedPercent) / price
        case .sell:
            guard let base = sellQuickFillQuantityBase else { return }
            let isLongSell = availableSellQuantity > 0
            scale = isLongSell ? maxShareInputScale : 0
            rawQuantity = (isLongSell && clampedPercent >= 1) ? availableSellQuantity : (base * clampedPercent)
        }

        var floored = Self.rounded(rawQuantity, scale: scale, mode: .down)
        if draft.side == .buy,
           let buyingPower,
           let price = estimatedExecutionPrice,
           price > 0,
           floored * price > buyingPower {
            let step = Self.decimalStep(scale: scale)
            floored = max(floored - step, 0)
        } else if draft.side == .sell, availableSellQuantity > 0, floored > availableSellQuantity {
            floored = Self.rounded(availableSellQuantity, scale: scale, mode: .down)
        }

        sizingMode = .shares
        var nextDraft = draft
        nextDraft.notionalText = ""
        nextDraft.quantityText = floored > 0 ? Self.apiNumber(floored, scale: scale, mode: .down) : ""
        if draft != nextDraft {
            draft = nextDraft
        }
    }

    func fillNotional(percent: Decimal) {
        guard canUseNotionalSizing else {
            fillQuantity(percent: percent)
            return
        }

        let clampedPercent = min(max(percent, 0), 1)
        let base: Decimal?
        switch draft.side {
        case .buy:
            base = buyingPower
        case .sell:
            base = sellQuickFillNotionalBase
        }

        guard let base, base > 0 else { return }
        var floored = Self.rounded(base * clampedPercent, scale: 2, mode: .down)
        if draft.side == .buy, let buyingPower, floored > buyingPower {
            floored = Self.rounded(buyingPower, scale: 2, mode: .down)
        } else if draft.side == .sell,
                  availableSellQuantity > 0,
                  let price = estimatedExecutionPrice,
                  price > 0 {
            let maxNotional = Self.rounded(availableSellQuantity * price, scale: 2, mode: .down)
            if floored > maxNotional {
                floored = maxNotional
            }
        }

        sizingMode = .notional
        var nextDraft = draft
        nextDraft.quantityText = ""
        nextDraft.notionalText = floored > 0 ? Self.apiNumber(floored, scale: 2, mode: .down) : ""
        if draft != nextDraft {
            draft = nextDraft
        }
    }

    func submit(_ orderDraft: OrderDraft, clientOrderID: String?, confirmedEnvironment: TradeEnvironment, app: AppModel) async -> TradeSubmitResult {
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

        let result = await app.submit(orderDraft, clientOrderID: clientOrderID, confirmedEnvironment: confirmedEnvironment)
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

    private static func positivePriceDecimal(_ value: Double?) -> Decimal? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Decimal(string: String(value), locale: NumberParser.apiLocale)
    }

    private func isReasonableQuote(_ quotePrice: Decimal, relativeTo reference: Decimal?) -> Bool {
        guard quotePrice > 0 else { return false }
        guard let reference, reference > 0 else { return true }
        // A coherent two-sided book can move well beyond the last print after a gap.
        let quoteTime = AlpacaDateParser.date(realtimeQuote?.timestamp ?? context?.snapshot?.latestQuote?.timestamp)
        let tradeTime = AlpacaDateParser.date(realtimeTrade?.timestamp ?? context?.snapshot?.latestTrade?.timestamp)
        let quotePredatesTrade = quoteTime.flatMap { quote in tradeTime.map { quote < $0 } } ?? false
        if !quotePredatesTrade, let bid = bidPrice, let ask = askPrice,
           bid <= ask, ask - bid <= bid * Decimal(5) / 100 {
            return true
        }
        let lowerBound = reference * Decimal(85) / Decimal(100)
        let upperBound = reference * Decimal(115) / Decimal(100)
        return quotePrice >= lowerBound && quotePrice <= upperBound
    }

    private static func rounded(
        _ value: Decimal,
        scale: Int,
        mode: NSDecimalNumber.RoundingMode
    ) -> Decimal {
        var mutable = value
        var result = Decimal()
        NSDecimalRound(&result, &mutable, scale, mode)
        return result
    }

    private static func decimalStep(scale: Int) -> Decimal {
        guard scale > 0 else { return 1 }
        return Decimal(sign: .plus, exponent: -scale, significand: 1)
    }

    private static func apiNumber(
        _ value: Decimal,
        scale: Int,
        mode: NSDecimalNumber.RoundingMode = .plain
    ) -> String {
        let result = rounded(value, scale: scale, mode: mode)
        return NumberText.trimTrailingZeros(NSDecimalNumber(decimal: result).stringValue)
    }

    private static func apiPriceNumber(_ value: Decimal) -> String {
        apiNumber(value, scale: value >= 1 ? 2 : 4, mode: .plain)
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
        var magnitude = self < 0 ? -self : self
        var truncated = Decimal()
        NSDecimalRound(&truncated, &magnitude, 0, .down)
        return truncated != magnitude
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
