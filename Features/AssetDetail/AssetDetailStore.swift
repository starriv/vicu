import Foundation
import Observation
import RxSwift

@MainActor
@Observable
final class AssetDetailStore {
    let symbol: String
    private static let supplementalSnapshotRefreshInterval: UInt64 = 30_000_000_000
    private static let supplementalSnapshotQuietThreshold: TimeInterval = 20
    private static let latestBarRefreshInterval: UInt64 = 5_000_000_000
    private static let oneDayChartSlotDuration: TimeInterval = 5 * 60
    private static let optimisticConnectionFreshnessThreshold: TimeInterval = 5 * 60

    var selectedRange: AssetChartRange = .oneDay
    var chartMode: AssetChartMode = .line
    var feed: AlpacaMarketDataFeed = .iex
    var asset: AlpacaAsset?
    var quote: AlpacaRealtimeQuote?
    var latestTrade: AlpacaRealtimeTrade?
    var dailyBar: AlpacaMarketBar?
    var previousDailyBar: AlpacaMarketBar?
    var position: AlpacaPosition?
    var chartRenderModels: AssetChartRenderModels = .empty
    var tradingStatus: AlpacaRealtimeTradingStatus?
    var connectionStatus: AssetRealtimeConnectionStatus = .disconnected
    var latestCoreSessionClose: Double?
    var sessionProgress: MarketSessionProgress?
    var isLoading = false
    var isLoadingChart = false
    var errorMessage: String?
    var lastUpdatedAt: Date?

    @ObservationIgnored private weak var service: (any AssetDetailServicing)?
    @ObservationIgnored private var streamDisposeBag = DisposeBag()
    @ObservationIgnored private var snapshotDisposeBag = DisposeBag()
    @ObservationIgnored private var supplementalSnapshotDisposeBag = DisposeBag()
    @ObservationIgnored private let snapshotRequests = PublishSubject<AssetDetailSnapshotRequest>()
    @ObservationIgnored private let supplementalSnapshotRequests = PublishSubject<AssetDetailSupplementalSnapshotRequest>()
    @ObservationIgnored private var chartRenderTask: Task<Void, Never>?
    @ObservationIgnored private var cachedSnapshotTask: Task<Void, Never>?
    @ObservationIgnored private var latestBarRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var positionLoadTask: Task<Void, Never>?
    @ObservationIgnored private var chartRenderRevision = 0
    @ObservationIgnored private var snapshotContentRevision = 0
    @ObservationIgnored private var shouldResyncOnLive = false
    @ObservationIgnored private var bars: [AlpacaMarketBar] = []
    @ObservationIgnored private var latestOvernightBar: AlpacaMarketBar?
    @ObservationIgnored private var overnightSupplementBars: [AlpacaMarketBar] = []
    @ObservationIgnored private var chartBaselines: [AssetChartRange: Double] = [:]
    @ObservationIgnored private var chartCache: [AssetChartCacheKey: AssetChartCacheEntry] = [:]
    @ObservationIgnored private var boundStreamFeed: AlpacaMarketDataFeed?
    @ObservationIgnored private let realtimeScheduler = SerialDispatchQueueScheduler(qos: .userInitiated)

    init(symbol: String) {
        self.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var displayName: String {
        AppFormatter.displayText(asset?.name?.displayAssetName)
    }

    var exchangeText: String {
        AppFormatter.displayText(asset?.exchange)
    }

    var assetClassText: String {
        asset?.assetClass?
            .replacingOccurrences(of: "_", with: " ")
            .uppercased() ?? AppFormatter.placeholder
    }

    var currentPrice: Double? {
        if hasActiveSessionProgress || hasRecentMarketData,
           let latestTradePrice = latestTrade?.price {
            return latestTradePrice
        }

        if let completedExtendedTradingPrice {
            return completedExtendedTradingPrice.price
        }

        return dailyBar?.close ?? bars.last?.close ?? latestTrade?.price
    }

    var coreSessionPrice: Double? {
        latestCoreSessionClose ?? dailyBar?.close
    }

    var previousClose: Double? {
        previousDailyBar?.close
    }

    var priceChange: Double? {
        guard let currentPrice, let previousClose else {
            return nil
        }

        return currentPrice - previousClose
    }

    var percentChange: Double? {
        guard let priceChange, let previousClose, previousClose != 0 else {
            return nil
        }

        return priceChange / previousClose
    }

    var isPositive: Bool {
        (priceChange ?? 0) >= 0
    }

    var todayPriceChange: Double? {
        guard let coreSessionPrice, let previousClose else {
            return nil
        }

        return coreSessionPrice - previousClose
    }

    var todayPercentChange: Double? {
        guard let todayPriceChange, let previousClose, previousClose != 0 else {
            return nil
        }

        return todayPriceChange / previousClose
    }

    var isTodayPositive: Bool {
        (todayPriceChange ?? 0) >= 0
    }

    func selectedPriceChange(for selection: AssetChartSelection) -> AssetPeriodPriceChange {
        AssetPeriodPriceChange(
            current: selection.point.close,
            baseline: selectedPriceChangeBaseline(fallback: selection.baseline)
        )
    }

    var activeExtendedSession: AssetExtendedTradingSession? {
        guard let activeExtendedSession = activeReferenceInterval()?.session.extendedTradingSession,
              let eventDate = lastEventDate,
              Self.extendedTradingSession(for: eventDate) == activeExtendedSession else {
            return nil
        }

        return activeExtendedSession
    }

    var completedExtendedSession: AssetExtendedTradingSession? {
        completedExtendedTradingPrice?.session
    }

    var extendedSession: AssetExtendedTradingSession? {
        activeExtendedSession ?? completedExtendedSession
    }

    var extendedSessionTitle: String? {
        if let activeExtendedSession {
            return activeExtendedSession.title
        }

        return completedExtendedSession?.completedTitle
    }

    var extendedPriceChange: Double? {
        guard extendedSession != nil, let currentPrice, let coreSessionPrice else {
            return nil
        }

        let change = currentPrice - coreSessionPrice
        guard abs(change) >= 0.005 else {
            return nil
        }

        return change
    }

    var extendedPercentChange: Double? {
        guard let extendedPriceChange, let coreSessionPrice, coreSessionPrice != 0 else {
            return nil
        }

        return extendedPriceChange / coreSessionPrice
    }

    var isExtendedPositive: Bool {
        (extendedPriceChange ?? 0) >= 0
    }

    private var completedExtendedTradingPrice: (session: AssetExtendedTradingSession, price: Double)? {
        guard !hasActiveSessionProgress,
              let sessionProgress,
              let latestTradePrice = latestTrade?.price,
              Self.hasValidMarketPrice(latestTradePrice),
              let latestTradeDate = AlpacaDateParser.date(latestTrade?.timestamp),
              let interval = completedExtendedInterval(containing: latestTradeDate, in: sessionProgress),
              let session = interval.session.extendedTradingSession else {
            return nil
        }

        return (session, latestTradePrice)
    }

    var bidPrice: Double? {
        quote?.bidPrice
    }

    var askPrice: Double? {
        quote?.askPrice
    }

    var spread: Double? {
        quote?.spread
    }

    var dayOpen: Double? {
        dailyBar?.open
    }

    var dayHigh: Double? {
        dailyBar?.high
    }

    var dayLow: Double? {
        dailyBar?.low
    }

    var dayVolume: Double? {
        dailyBar?.volume
    }

    var lastEventDate: Date? {
        AlpacaDateParser.date(latestTrade?.timestamp)
            ?? AlpacaDateParser.date(quote?.timestamp)
            ?? AlpacaDateParser.date(dailyBar?.timestamp)
            ?? lastUpdatedAt
    }

    var hasMarketData: Bool {
        latestTrade != nil
            || quote != nil
            || dailyBar != nil
            || previousDailyBar != nil
            || !chartRenderModels.line.points.isEmpty
    }

    var hasRecentMarketData: Bool {
        guard let lastEventDate else {
            return false
        }

        return Date().timeIntervalSince(lastEventDate) < 90
    }

    private var hasRecentLocalMarketDataRefresh: Bool {
        guard hasMarketData, let lastUpdatedAt else {
            return false
        }

        return Date().timeIntervalSince(lastUpdatedAt) < Self.optimisticConnectionFreshnessThreshold
    }

    private var hasOptimisticMarketDataCoverage: Bool {
        hasRecentMarketData || hasRecentLocalMarketDataRefresh
    }

    var headerConnectionStatus: AssetRealtimeConnectionStatus? {
        guard !isLoading || hasMarketData else {
            return nil
        }

        switch connectionStatus {
        case .failed, .reconnecting:
            return hasOptimisticMarketDataCoverage ? nil : connectionStatus
        default:
            return nil
        }
    }

    var isTradable: Bool {
        asset?.tradable == true && asset?.status?.lowercased() == "active"
    }

    var canShowTradeActions: Bool {
        asset != nil && isTradable
    }

    var hasShareableChartData: Bool {
        shareChartRenderModel.points.count > 1 && !isLoadingChart
    }

    func start(service: any AssetDetailServicing) {
        self.service = service
        bindSnapshotPipeline(service: service)
        bindSupplementalSnapshotPipeline(service: service)
        startLatestBarRefreshLoop(service: service)
        reload(service: service)
    }

    func stop() {
        streamDisposeBag = DisposeBag()
        snapshotDisposeBag = DisposeBag()
        supplementalSnapshotDisposeBag = DisposeBag()
        latestBarRefreshTask?.cancel()
        latestBarRefreshTask = nil
        cachedSnapshotTask?.cancel()
        cachedSnapshotTask = nil
        positionLoadTask?.cancel()
        positionLoadTask = nil
        chartRenderTask?.cancel()
        chartRenderTask = nil
        chartRenderRevision += 1
        boundStreamFeed = nil
        connectionStatus = .disconnected
    }

    func reload(service: (any AssetDetailServicing)? = nil) {
        let service = service ?? self.service
        guard let service else {
            return
        }

        self.service = service
        loadCachedSnapshot(service: service, range: selectedRange, feed: feed)
        snapshotRequests.onNext(
            AssetDetailSnapshotRequest(
                symbol: symbol,
                range: selectedRange,
                feed: feed,
                showsBlockingLoading: asset == nil
            )
        )
        loadOpenPosition(service: service)
    }

    private func loadOpenPosition(service: any AssetDetailServicing) {
        positionLoadTask?.cancel()
        let requestedSymbol = symbol
        positionLoadTask = Task { @MainActor [weak self, weak service] in
            guard let self, let service else {
                return
            }

            do {
                let loadedPosition = try await service.fetchOpenPosition(symbol: requestedSymbol)
                guard !Task.isCancelled, self.symbol == requestedSymbol else {
                    return
                }

                self.position = loadedPosition
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled, self.symbol == requestedSymbol else {
                    return
                }

                self.position = nil
            }
        }
    }

    private func loadCachedSnapshot(
        service: any AssetDetailServicing,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed
    ) {
        // Cache lookup removed — Store now fetches directly via fetchAssetDetailSnapshot.
        // Preserved as no-op to avoid changing reload() and selectRange() call sites.
    }

    func waitForShareableChartData(maxAttempts: Int = 80) async -> Bool {
        if hasShareableChartData {
            return true
        }

        for _ in 0..<maxAttempts {
            if Task.isCancelled {
                return false
            }

            if let chartRenderTask {
                await chartRenderTask.value
            } else {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return false
                }
            }

            if hasShareableChartData {
                return true
            }

            if !isLoading, !isLoadingChart, errorMessage != nil {
                return false
            }
        }

        return hasShareableChartData
    }

    func selectRange(_ range: AssetChartRange) {
        guard selectedRange != range else {
            return
        }

        selectedRange = range
        if let service {
            loadCachedSnapshot(service: service, range: range, feed: feed)
        }
        if applyCachedChart(for: range) {
            isLoadingChart = false
            errorMessage = nil
            return
        }

        isLoadingChart = true
        snapshotRequests.onNext(
            AssetDetailSnapshotRequest(
                symbol: symbol,
                range: range,
                feed: feed,
                showsBlockingLoading: false
            )
        )
    }

    func selectChartMode(_ mode: AssetChartMode) {
        guard chartMode != mode else {
            return
        }

        chartMode = mode
        guard selectedRange != .oneDay else {
            return
        }

        if applyCachedChart(for: selectedRange) {
            isLoadingChart = false
            errorMessage = nil
            return
        }

        updateChartRenderModels(showsLoading: true)
    }

    var effectiveChartMode: AssetChartMode {
        selectedRange == .oneDay ? .line : chartMode
    }

    private var shareChartRenderModel: AssetChartRenderModel {
        let lineModel = chartRenderModels.line
        let fallbackModel = chartRenderModels.model(for: effectiveChartMode)
        return lineModel.points.isEmpty ? fallbackModel : lineModel
    }

    private func bindSnapshotPipeline(service: any AssetDetailServicing) {
        snapshotDisposeBag = DisposeBag()

        snapshotRequests
            .observe(on: MainScheduler.instance)
            .do(onNext: { [weak self] request in
                self?.beginSnapshotLoad(request)
            })
            .flatMapLatest { [weak service] request -> Observable<AssetDetailSnapshotLoadResult> in
                guard let service else {
                    return .empty()
                }

                return assetDetailSnapshotLoad(service: service, request: request)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.apply(result)
            })
            .disposed(by: snapshotDisposeBag)
    }

    private func bindSupplementalSnapshotPipeline(service: any AssetDetailServicing) {
        supplementalSnapshotDisposeBag = DisposeBag()

        let scheduledRefreshes = Observable<Int>
            .interval(.seconds(Int(Self.supplementalSnapshotRefreshInterval / 1_000_000_000)), scheduler: MainScheduler.instance)
            .map { _ in AssetDetailSupplementalSnapshotRequest.scheduled }

        Observable
            .merge(scheduledRefreshes, supplementalSnapshotRequests.asObservable())
            .observe(on: MainScheduler.instance)
            .flatMapFirst { [weak self, weak service] request -> Observable<AssetDetailSupplementalSnapshotResult> in
                guard let self, let service else {
                    return .empty()
                }

                guard self.shouldFetchSupplementalSnapshot(for: request) else {
                    return .just(.skipped)
                }

                return assetDetailSupplementalSnapshotLoad(
                    service: service,
                    symbol: self.symbol,
                    feed: self.feed
                )
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.apply(result)
            })
            .disposed(by: supplementalSnapshotDisposeBag)
    }

    private func beginSnapshotLoad(_ request: AssetDetailSnapshotRequest) {
        isLoading = request.showsBlockingLoading
        isLoadingChart = true
        errorMessage = nil
    }

    private func bindStream(service: any AssetDetailServicing) {
        streamDisposeBag = DisposeBag()
        boundStreamFeed = nil
        let streamSymbol = symbol

        do {
            let channels = feed == .overnight ? AlpacaRealtimeChannel.tradeQuote : AlpacaRealtimeChannel.assetDetail
            let source = try service.streamAssetMarketData(symbol: symbol, feed: feed, channels: channels)
            boundStreamFeed = feed
            assetRealtimeBatches(
                from: source,
                symbol: streamSymbol,
                scheduler: realtimeScheduler
            )
                .observe(on: MainScheduler.instance)
                .subscribe(
                    onNext: { [weak self] batch in
                        Task { @MainActor in
                            self?.apply(batch)
                        }
                    },
                    onError: { [weak self] error in
                        Task { @MainActor in
                            self?.connectionStatus = .failed(error.localizedDescription)
                        }
                    }
                )
                .disposed(by: streamDisposeBag)
        } catch {
            boundStreamFeed = nil
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func apply(_ snapshot: AssetDetailSnapshot) {
        snapshotContentRevision += 1
        let previousFeed = feed
        feed = snapshot.feed
        sessionProgress = snapshot.sessionProgress
        asset = snapshot.asset
        selectedRange = snapshot.range
        apply(snapshot.stockSnapshot)
        latestOvernightBar = snapshot.feed == .overnight ? snapshot.latestBar : nil
        resetOvernightSupplementBars(feed: snapshot.feed, latestBar: snapshot.latestBar)
        setChartBaseline(snapshot.chartBaseline, for: snapshot.range)
        setChartBars(Self.normalizedBars(snapshot.bars), for: snapshot.range)
        if snapshot.range == .oneDay {
            latestCoreSessionClose = bars.last?.close ?? latestCoreSessionClose ?? snapshot.stockSnapshot?.dailyBar?.close
            if snapshot.feed == .overnight {
                recordLatestOvernightChartBar()
            } else {
                mergeSupplementalLatestBar(snapshot.latestBar, updatesChart: true)
            }
        }
        if let service, previousFeed != feed || boundStreamFeed != feed {
            bindStream(service: service)
        }
        lastUpdatedAt = Date()
        refreshLatestBarSoon()
    }

    private func apply(_ result: AssetDetailSnapshotLoadResult) {
        switch result {
        case .marketData(let snapshot, let request):
            guard selectedRange == request.range, isLoading else {
                return
            }

            apply(snapshot)
            if hasMarketData {
                isLoading = false
                lastUpdatedAt = Date()
            }
        case .success(let snapshot):
            apply(snapshot)
            isLoading = false
            errorMessage = nil
        case .failure(let error, let request):
            guard selectedRange == request.range else {
                return
            }

            isLoading = false
            isLoadingChart = false
            applyBlockingSnapshotFailure(error)
        }
    }

    private func apply(_ result: AssetDetailSupplementalSnapshotResult) {
        switch result {
        case .success(let snapshot, let requestedFeed):
            guard feed == requestedFeed else {
                return
            }

            apply(snapshot)
        case .failure(let error, let requestedFeed):
            guard feed == requestedFeed else {
                return
            }

            applySupplementalSnapshotFailure(error)
        case .skipped:
            break
        }
    }

    private func apply(_ snapshot: AlpacaStockSnapshot?) {
        guard let snapshot else {
            return
        }

        if let latestTrade = snapshot.latestTrade,
           Self.hasValidMarketPrice(latestTrade.price) {
            self.latestTrade = AlpacaRealtimeTrade(
                symbol: symbol,
                price: latestTrade.price,
                size: latestTrade.size,
                exchange: latestTrade.exchange,
                timestamp: latestTrade.timestamp,
                conditions: latestTrade.conditions,
                tape: latestTrade.tape
            )
        }

        if let latestQuote = snapshot.latestQuote,
           Self.hasValidQuotePrice(latestQuote) {
            quote = AlpacaRealtimeQuote(
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
        }

        if Self.hasValidMarketPrice(snapshot.dailyBar?.close) {
            dailyBar = snapshot.dailyBar
        }
        if Self.hasValidMarketPrice(snapshot.previousDailyBar?.close) {
            previousDailyBar = snapshot.previousDailyBar
        }
    }

    private func apply(_ batch: AssetRealtimeBatch) {
        if let status = batch.connectionStatus {
            applyConnectionStatus(status)
        }

        if selectedRange == .oneDay {
            var didChangeChart = false
            if let trade = batch.latestTrade,
               Self.hasValidMarketPrice(trade.price),
               latestTrade != trade {
                latestTrade = trade
                didChangeChart = true
            }

            if let quote = batch.latestQuote,
               Self.hasValidQuotePrice(quote),
               self.quote != quote {
                self.quote = quote
                didChangeChart = true
            }

            for bar in batch.bars {
                didChangeChart = merge(bar, updatesChart: false) || didChangeChart
            }
            if didChangeChart {
                updateChartRenderModels()
                latestCoreSessionClose = bars.last?.close ?? latestCoreSessionClose
            }
        } else {
            if let trade = batch.latestTrade,
               Self.hasValidMarketPrice(trade.price),
               latestTrade != trade {
                latestTrade = trade
            }

            if let quote = batch.latestQuote,
               Self.hasValidQuotePrice(quote),
               self.quote != quote {
                self.quote = quote
            }
        }

        if let bar = batch.dailyBar, dailyBar != bar.marketBar {
            dailyBar = bar.marketBar
        }

        if let status = batch.tradingStatus, tradingStatus != status {
            tradingStatus = status
        }

        if batch.hasMarketData {
            snapshotContentRevision += 1
            lastUpdatedAt = Date()
        }
    }

    private func applyConnectionStatus(_ status: AssetRealtimeConnectionStatus) {
        if case .reconnecting = status {
            shouldResyncOnLive = true
        }

        connectionStatus = status
        if status == .live, shouldResyncOnLive {
            shouldResyncOnLive = false
            resyncSnapshot()
        }
    }

    private func resyncSnapshot() {
        supplementalSnapshotRequests.onNext(.forced)
    }

    private var shouldRunSupplementalSnapshotRefresh: Bool {
        feed == .overnight || hasActiveSessionProgress
    }

    private func shouldFetchSupplementalSnapshot(for request: AssetDetailSupplementalSnapshotRequest) -> Bool {
        if request == .forced {
            return true
        }

        guard shouldRunSupplementalSnapshotRefresh else {
            return false
        }

        guard let lastUpdatedAt else {
            return true
        }

        return Date().timeIntervalSince(lastUpdatedAt) >= Self.supplementalSnapshotQuietThreshold
    }

    private func apply(_ resolvedSnapshot: AlpacaResolvedStockSnapshot) {
        let previousFeed = feed
        feed = resolvedSnapshot.feed
        apply(resolvedSnapshot.snapshot)
        latestOvernightBar = resolvedSnapshot.feed == .overnight ? resolvedSnapshot.latestBar : nil
        var didMergeLatestBar = false
        if resolvedSnapshot.feed == .overnight {
            mergeOvernightSupplementBar(resolvedSnapshot.latestBar)
            recordLatestOvernightChartBar()
        } else {
            overnightSupplementBars = []
            didMergeLatestBar = mergeSupplementalLatestBar(
                resolvedSnapshot.latestBar,
                updatesChart: false
            )
        }
        if resolvedSnapshot.snapshot != nil || resolvedSnapshot.latestBar != nil {
            snapshotContentRevision += 1
            if didMergeLatestBar || resolvedSnapshot.feed == .overnight {
                updateChartRenderModels()
            }
            lastUpdatedAt = Date()
        }
        if let service, previousFeed != feed {
            bindStream(service: service)
        }
    }

    private func startLatestBarRefreshLoop(service: any AssetDetailServicing) {
        latestBarRefreshTask?.cancel()
        latestBarRefreshTask = Task { @MainActor [weak self, weak service] in
            while !Task.isCancelled {
                guard let self, let service else {
                    return
                }

                await self.refreshLatestBarIfNeeded(service: service)
                do {
                    try await Task.sleep(nanoseconds: Self.latestBarRefreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func refreshLatestBarIfNeeded(service: any AssetDetailServicing) async {
        guard shouldPollLatestBar else {
            return
        }

        let requestedFeed = feed
        do {
            let latestBar = try await service.fetchLatestStockBar(symbol: symbol, feed: requestedFeed)
            guard feed == requestedFeed, selectedRange == .oneDay else {
                return
            }

            applyLatestBar(latestBar, feed: requestedFeed)
        } catch where error.isRequestCancellation {
            return
        } catch {
            return
        }
    }

    private var shouldPollLatestBar: Bool {
        selectedRange == .oneDay && hasActiveSessionProgress
    }

    private func refreshLatestBarSoon() {
        guard selectedRange == .oneDay,
              hasActiveSessionProgress,
              let service else {
            return
        }

        Task { @MainActor [weak self, weak service] in
            guard let self, let service else {
                return
            }

            await self.refreshLatestBarIfNeeded(service: service)
        }
    }

    private func applyBlockingSnapshotFailure(_ error: Error) {
        guard asset == nil else {
            errorMessage = nil
            return
        }

        errorMessage = displayErrorMessage(for: error)
    }

    private func applySupplementalSnapshotFailure(_ error: Error) {
        guard asset == nil, !hasMarketData else {
            errorMessage = nil
            return
        }

        errorMessage = displayErrorMessage(for: error)
    }

    private func displayErrorMessage(for error: Error) -> String {
        APIErrorDisplayMessage.message(for: error, locale: service?.preferredLocale ?? AppLocale.current)
    }

    private func applyLatestBar(_ bar: AlpacaMarketBar?, feed requestedFeed: AlpacaMarketDataFeed) {
        guard selectedRange == .oneDay,
              feed == requestedFeed,
              let bar,
              Self.hasValidMarketPrice(bar.close) else {
            return
        }

        let didChangeChart: Bool
        if requestedFeed == .overnight {
            let previousLatestBar = latestOvernightBar
            latestOvernightBar = bar
            mergeOvernightSupplementBar(bar)
            didChangeChart = previousLatestBar != bar
        } else {
            didChangeChart = mergeSupplementalLatestBar(bar, updatesChart: false)
        }

        if didChangeChart {
            updateChartRenderModels()
            latestCoreSessionClose = bars.last?.close ?? latestCoreSessionClose
            lastUpdatedAt = Date()
        }
    }

    @discardableResult
    private func mergeSupplementalLatestBar(_ bar: AlpacaMarketBar?, updatesChart: Bool) -> Bool {
        guard selectedRange == .oneDay,
              let bar,
              Self.hasValidMarketPrice(bar.close) else {
            return false
        }

        return merge(bar, updatesChart: updatesChart)
    }

    @discardableResult
    private func merge(_ bar: AlpacaMarketBar, updatesChart: Bool = true) -> Bool {
        guard let timestamp = bar.timestamp,
              let date = AlpacaDateParser.date(timestamp) else {
            appendUnordered(bar)
            if updatesChart {
                updateChartRenderModels()
            }
            return true
        }

        if let last = bars.last, last.timestamp == timestamp {
            guard last != bar else {
                return false
            }
            bars[bars.count - 1] = bar
        } else if let lastDate = AlpacaDateParser.date(bars.last?.timestamp), date > lastDate {
            bars.append(bar)
        } else if let index = bars.firstIndex(where: { $0.timestamp == timestamp }) {
            guard bars[index] != bar else {
                return false
            }
            bars[index] = bar
        } else {
            let insertIndex = insertionIndex(for: date)
            bars.insert(bar, at: insertIndex)
        }

        trimBarsIfNeeded()
        latestCoreSessionClose = bars.last?.close ?? latestCoreSessionClose
        if updatesChart {
            updateChartRenderModels()
        }
        return true
    }

    private func appendUnordered(_ bar: AlpacaMarketBar) {
        bars.append(bar)
        bars = Self.normalizedBars(bars)
        trimBarsIfNeeded()
    }

    private func trimBarsIfNeeded() {
        if bars.count > 900 {
            bars.removeFirst(bars.count - 900)
        }
    }

    private func updateChartRenderModels(showsLoading: Bool = false) {
        scheduleChartRender(
            for: selectedRange,
            mode: effectiveChartMode,
            sourceBars: bars,
            renderInput: chartRenderInput(from: bars, for: selectedRange),
            showsLoading: showsLoading
        )
    }

    private func setChartBars(_ newBars: [AlpacaMarketBar], for range: AssetChartRange) {
        guard selectedRange == range else {
            scheduleChartRender(
                for: range,
                mode: .line,
                sourceBars: newBars,
                renderInput: chartRenderInput(from: newBars, for: range),
                showsLoading: false
            )
            return
        }

        bars = newBars
        scheduleChartRender(
            for: range,
            mode: effectiveChartMode,
            sourceBars: newBars,
            renderInput: chartRenderInput(from: newBars, for: range),
            showsLoading: true
        )
    }

    @discardableResult
    private func applyCachedChart(for range: AssetChartRange) -> Bool {
        guard shouldCacheChart(for: range) else {
            return false
        }

        let cacheKey = AssetChartCacheKey(range: range, mode: effectiveChartMode)
        guard let cached = chartCache[cacheKey] else {
            return false
        }

        chartRenderRevision += 1
        chartRenderTask?.cancel()
        bars = cached.bars
        chartRenderModels = cached.renderModels
        if range == .oneDay {
            latestCoreSessionClose = bars.last?.close ?? latestCoreSessionClose
        }
        return true
    }

    private func scheduleChartRender(
        for range: AssetChartRange,
        mode: AssetChartMode,
        sourceBars: [AlpacaMarketBar],
        renderInput: AssetChartRenderInput,
        showsLoading: Bool
    ) {
        chartRenderRevision += 1
        let revision = chartRenderRevision
        chartRenderTask?.cancel()
        if showsLoading {
            isLoadingChart = true
        }

        chartRenderTask = Task { [weak self, renderInput] in
            let result = await Task.detached(priority: .userInitiated) {
                AssetChartPreprocessor.makeRenderModels(
                    from: renderInput.bars,
                    xDomain: renderInput.xDomain,
                    priceChangeBaseline: renderInput.priceChangeBaseline,
                    mode: mode
                )
            }.value

            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard revision == self.chartRenderRevision else { return }

            let cacheKey = AssetChartCacheKey(range: range, mode: mode)
            if self.shouldCacheChart(for: range) {
                self.chartCache[cacheKey] = AssetChartCacheEntry(
                    bars: sourceBars,
                    renderModels: result
                )
            } else {
                self.chartCache.removeValue(forKey: cacheKey)
            }

            if self.selectedRange == range, self.effectiveChartMode == mode {
                self.chartRenderModels = result
                self.isLoadingChart = false
            }
        }
    }

    private func shouldCacheChart(for range: AssetChartRange) -> Bool {
        !(range == .oneDay && hasActiveSessionProgress)
    }

    private var hasActiveSessionProgress: Bool {
        guard let sessionProgress else {
            return false
        }

        return sessionProgress.intervals.contains { interval in
            interval.contains(sessionProgress.referenceDate)
        }
    }

    private func chartRenderInput(from sourceBars: [AlpacaMarketBar], for range: AssetChartRange) -> AssetChartRenderInput {
        AssetIntradaySessionMapper.makeRenderInput(
            from: sourceBars,
            range: range,
            priceChangeBaseline: chartBaselines[range],
            context: intradaySessionContext
        )
    }

    private var intradaySessionContext: AssetIntradaySessionContext {
        AssetIntradaySessionContext(
            symbol: symbol,
            feed: feed,
            sessionProgress: sessionProgress,
            latestTrade: latestTrade,
            quote: quote,
            latestOvernightBar: latestOvernightBar,
            overnightSupplementBars: overnightSupplementBars,
            previousClose: previousClose,
            dayOpen: dayOpen,
            latestCoreSessionClose: latestCoreSessionClose,
            currentPrice: currentPrice
        )
    }

    private func setChartBaseline(_ baseline: Double?, for range: AssetChartRange) {
        guard let baseline else {
            chartBaselines.removeValue(forKey: range)
            return
        }

        chartBaselines[range] = baseline
    }

    private func selectedPriceChangeBaseline(fallback: Double) -> Double {
        switch selectedRange {
        case .oneDay:
            previousClose ?? chartBaselines[selectedRange] ?? fallback
        default:
            chartBaselines[selectedRange] ?? chartRenderModels.line.priceChangeBaseline ?? fallback
        }
    }

    private func activeReferenceInterval() -> MarketSessionInterval? {
        AssetIntradaySessionMapper.activeReferenceInterval(in: sessionProgress)
    }

    private func completedExtendedInterval(
        containing date: Date,
        in progress: MarketSessionProgress
    ) -> MarketSessionInterval? {
        AssetIntradaySessionMapper.completedExtendedInterval(containing: date, in: progress)
    }

    private func resetOvernightSupplementBars(feed: AlpacaMarketDataFeed, latestBar: AlpacaMarketBar?) {
        overnightSupplementBars = []
        guard feed == .overnight else {
            return
        }

        mergeOvernightSupplementBar(latestBar)
    }

    private func recordLatestOvernightChartBar() {
        guard feed == .overnight, selectedRange == .oneDay else {
            return
        }

        mergeOvernightSupplementBar(
            AssetIntradaySessionMapper.latestOvernightChartBar(
                referenceBar: bars.last,
                context: intradaySessionContext
            )
        )
    }

    private func mergeOvernightSupplementBar(_ bar: AlpacaMarketBar?) {
        guard let bar,
              feed == .overnight,
              selectedRange == .oneDay,
              let barKey = AssetIntradaySessionMapper.minuteKey(for: bar) else {
            return
        }

        if let index = overnightSupplementBars.firstIndex(where: { AssetIntradaySessionMapper.minuteKey(for: $0) == barKey }) {
            let currentDate = AlpacaDateParser.date(overnightSupplementBars[index].timestamp)
            let candidateDate = AlpacaDateParser.date(bar.timestamp)
            if currentDate == nil || candidateDate == nil || candidateDate! >= currentDate! {
                overnightSupplementBars[index] = bar
            }
        } else {
            overnightSupplementBars.append(bar)
        }

        overnightSupplementBars = AssetIntradaySessionMapper.normalizedBars(
            overnightSupplementBars,
            maxCount: AssetIntradaySessionMapper.maxOvernightSupplementBars
        )
    }

    private func insertionIndex(for date: Date) -> Int {
        var lowerBound = 0
        var upperBound = bars.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            let midpointDate = AlpacaDateParser.date(bars[midpoint].timestamp) ?? .distantPast
            if midpointDate <= date {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        return lowerBound
    }

    private static func normalizedBars(_ bars: [AlpacaMarketBar]) -> [AlpacaMarketBar] {
        AssetIntradaySessionMapper.normalizedBars(bars)
    }

    private static func hasValidMarketPrice(_ price: Double?) -> Bool {
        AssetIntradaySessionMapper.hasValidMarketPrice(price)
    }

    private static func hasValidQuotePrice(_ quote: AlpacaStockQuote) -> Bool {
        hasValidMarketPrice(quote.bidPrice) || hasValidMarketPrice(quote.askPrice)
    }

    private static func hasValidQuotePrice(_ quote: AlpacaRealtimeQuote) -> Bool {
        hasValidMarketPrice(quote.bidPrice) || hasValidMarketPrice(quote.askPrice)
    }

    private static func extendedTradingSession(for date: Date) -> AssetExtendedTradingSession? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }

        let minutes = hour * 60 + minute
        switch minutes {
        case 4 * 60 ..< 9 * 60 + 30:
            return .preMarket
        case 16 * 60 ..< 20 * 60:
            return .afterHours
        case 20 * 60 ..< 24 * 60, 0 ..< 4 * 60:
            return .overnight
        default:
            return nil
        }
    }
}

private struct AssetChartCacheKey: Hashable {
    let range: AssetChartRange
    let mode: AssetChartMode
}

private struct AssetChartCacheEntry {
    let bars: [AlpacaMarketBar]
    let renderModels: AssetChartRenderModels
}

private struct AssetDetailSnapshotRequest: Sendable {
    let symbol: String
    let range: AssetChartRange
    let feed: AlpacaMarketDataFeed
    let showsBlockingLoading: Bool
}

private enum AssetDetailSnapshotLoadResult {
    case marketData(AlpacaStockSnapshot, request: AssetDetailSnapshotRequest)
    case success(AssetDetailSnapshot)
    case failure(Error, request: AssetDetailSnapshotRequest)
}

private enum AssetDetailSupplementalSnapshotRequest: Equatable {
    case scheduled
    case forced
}

private enum AssetDetailSupplementalSnapshotResult {
    case success(AlpacaResolvedStockSnapshot, requestedFeed: AlpacaMarketDataFeed)
    case failure(Error, requestedFeed: AlpacaMarketDataFeed)
    case skipped
}

// @unchecked Sendable: immutable observer; onNext only called on MainActor
private final class AssetDetailSnapshotLoadObserverBox: @unchecked Sendable {
    private let observer: AnyObserver<AssetDetailSnapshotLoadResult>

    init(_ observer: AnyObserver<AssetDetailSnapshotLoadResult>) {
        self.observer = observer
    }

    @MainActor
    func onNext(_ result: AssetDetailSnapshotLoadResult) {
        observer.onNext(result)
    }
}

// @unchecked Sendable: immutable observer; onNext only called on MainActor
private final class AssetDetailSupplementalSnapshotObserverBox: @unchecked Sendable {
    private let observer: AnyObserver<AssetDetailSupplementalSnapshotResult>

    init(_ observer: AnyObserver<AssetDetailSupplementalSnapshotResult>) {
        self.observer = observer
    }

    @MainActor
    func onNext(_ result: AssetDetailSupplementalSnapshotResult) {
        observer.onNext(result)
    }
}

@MainActor
private func assetDetailSnapshotLoad(
    service: any AssetDetailServicing,
    request: AssetDetailSnapshotRequest
) -> Observable<AssetDetailSnapshotLoadResult> {
    Observable.create { observer in
        let observerBox = AssetDetailSnapshotLoadObserverBox(observer)
        let earlySnapshotTask: Task<Void, Never>? = request.showsBlockingLoading
            ? Task { @MainActor in
                let service = service
                do {
                    guard let snapshot = try await service.fetchAssetSnapshot(
                        symbol: request.symbol,
                        feed: request.feed
                    ) else {
                        return
                    }

                    try Task.checkCancellation()
                    observerBox.onNext(.marketData(snapshot, request: request))
                } catch {
                    return
                }
            }
            : nil
        let task = Task { @MainActor in
            let service = service
            do {
                let snapshot = try await service.fetchAssetDetailSnapshot(
                    symbol: request.symbol,
                    range: request.range,
                    feed: request.feed
                )
                try Task.checkCancellation()
                observerBox.onNext(.success(snapshot))
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                observerBox.onNext(.failure(error, request: request))
            }
        }

        return Disposables.create {
            earlySnapshotTask?.cancel()
            task.cancel()
        }
    }
}

@MainActor
private func assetDetailSupplementalSnapshotLoad(
    service: any AssetDetailServicing,
    symbol: String,
    feed: AlpacaMarketDataFeed
) -> Observable<AssetDetailSupplementalSnapshotResult> {
    Observable.create { observer in
        let observerBox = AssetDetailSupplementalSnapshotObserverBox(observer)
        let task = Task { @MainActor in
            let service = service
            do {
                let snapshot = try await service.fetchResolvedAssetSnapshot(symbol: symbol, feed: feed)
                try Task.checkCancellation()
                observerBox.onNext(.success(snapshot, requestedFeed: feed))
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                observerBox.onNext(.failure(error, requestedFeed: feed))
            }
        }

        return Disposables.create {
            task.cancel()
        }
    }
}

private struct AssetRealtimeBatch {
    var connectionStatus: AssetRealtimeConnectionStatus?
    var latestTrade: AlpacaRealtimeTrade?
    var latestQuote: AlpacaRealtimeQuote?
    var dailyBar: AlpacaRealtimeBar?
    var tradingStatus: AlpacaRealtimeTradingStatus?
    var bars: [AlpacaMarketBar] = []

    var hasMarketData: Bool {
        latestTrade != nil
            || latestQuote != nil
            || dailyBar != nil
            || tradingStatus != nil
            || !bars.isEmpty
    }

    init?(events: [AssetRealtimeEvent], symbol: String) {
        guard !events.isEmpty else {
            return nil
        }

        let symbol = symbol.uppercased()
        var barsByTimestamp: [String: AlpacaMarketBar] = [:]
        var untimedBars: [AlpacaMarketBar] = []

        for event in events {
            switch event {
            case .connection(let status):
                connectionStatus = status
            case .trade(let trade):
                guard trade.symbol == symbol else { continue }
                latestTrade = trade
            case .quote(let quote):
                guard quote.symbol == symbol else { continue }
                latestQuote = quote
            case .minuteBar(let bar), .updatedBar(let bar):
                guard bar.symbol == symbol else { continue }
                if let timestamp = bar.marketBar.timestamp {
                    barsByTimestamp[timestamp] = bar.marketBar
                } else {
                    untimedBars.append(bar.marketBar)
                }
            case .dailyBar(let bar):
                guard bar.symbol == symbol else { continue }
                dailyBar = bar
            case .status(let status):
                guard status.symbol == symbol else { continue }
                tradingStatus = status
            }
        }

        bars = Array(barsByTimestamp.values) + untimedBars
        if connectionStatus == nil, !hasMarketData {
            return nil
        }
    }
}

private func assetRealtimeBatches(
    from source: Observable<AssetRealtimeEvent>,
    symbol: String,
    scheduler: SerialDispatchQueueScheduler
) -> Observable<AssetRealtimeBatch> {
    source
        .observe(on: scheduler)
        .buffer(timeSpan: .milliseconds(250), count: 128, scheduler: scheduler)
        .compactMap { events in
            AssetRealtimeBatch(events: events, symbol: symbol)
        }
}

enum AssetExtendedTradingSession: Equatable, Sendable {
    case preMarket
    case afterHours
    case overnight

    var title: String {
        switch self {
        case .preMarket:
            "Pre-market"
        case .afterHours:
            "After-hours"
        case .overnight:
            "Overnight"
        }
    }

    var completedTitle: String {
        switch self {
        case .preMarket:
            "Last pre-market"
        case .afterHours:
            "Last after-hours"
        case .overnight:
            "Last overnight"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var displayAssetName: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = " Common Stock"

        guard value.range(of: suffix, options: [.caseInsensitive, .anchored, .backwards]) != nil else {
            return value
        }

        return String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
