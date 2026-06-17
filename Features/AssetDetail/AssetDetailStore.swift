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

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var streamDisposeBag = DisposeBag()
    @ObservationIgnored private var snapshotDisposeBag = DisposeBag()
    @ObservationIgnored private var supplementalSnapshotDisposeBag = DisposeBag()
    @ObservationIgnored private let snapshotRequests = PublishSubject<AssetDetailSnapshotRequest>()
    @ObservationIgnored private let supplementalSnapshotRequests = PublishSubject<AssetDetailSupplementalSnapshotRequest>()
    @ObservationIgnored private var chartRenderTask: Task<Void, Never>?
    @ObservationIgnored private var latestBarRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var positionLoadTask: Task<Void, Never>?
    @ObservationIgnored private var chartRenderRevision = 0
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
        latestTrade?.price ?? dailyBar?.close ?? bars.last?.close
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

    var extendedSession: AssetExtendedTradingSession? {
        guard let eventDate = lastEventDate else {
            return nil
        }

        return Self.extendedTradingSession(for: eventDate)
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

    var isTradable: Bool {
        asset?.tradable == true && asset?.status?.lowercased() == "active"
    }

    var canShowTradeActions: Bool {
        asset != nil && isTradable
    }

    func start(app: AppModel) {
        self.app = app
        bindSnapshotPipeline(app: app)
        bindSupplementalSnapshotPipeline(app: app)
        startLatestBarRefreshLoop(app: app)
        reload(app: app)
    }

    func stop() {
        streamDisposeBag = DisposeBag()
        snapshotDisposeBag = DisposeBag()
        supplementalSnapshotDisposeBag = DisposeBag()
        latestBarRefreshTask?.cancel()
        latestBarRefreshTask = nil
        positionLoadTask?.cancel()
        positionLoadTask = nil
        chartRenderTask?.cancel()
        chartRenderTask = nil
        chartRenderRevision += 1
        boundStreamFeed = nil
        connectionStatus = .disconnected
    }

    func reload(app: AppModel? = nil) {
        let app = app ?? self.app
        guard let app else {
            return
        }

        self.app = app
        snapshotRequests.onNext(
            AssetDetailSnapshotRequest(
                symbol: symbol,
                range: selectedRange,
                feed: feed,
                showsBlockingLoading: asset == nil
            )
        )
        loadOpenPosition(app: app)
    }

    private func loadOpenPosition(app: AppModel) {
        positionLoadTask?.cancel()
        let requestedSymbol = symbol
        positionLoadTask = Task { @MainActor [weak self, weak app] in
            guard let self, let app else {
                return
            }

            do {
                let loadedPosition = try await app.fetchOpenPosition(symbol: requestedSymbol)
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

    func selectRange(_ range: AssetChartRange) {
        guard selectedRange != range else {
            return
        }

        selectedRange = range
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

    private func bindSnapshotPipeline(app: AppModel) {
        snapshotDisposeBag = DisposeBag()

        snapshotRequests
            .observe(on: MainScheduler.instance)
            .do(onNext: { [weak self] request in
                self?.beginSnapshotLoad(request)
            })
            .flatMapLatest { [weak app] request -> Observable<AssetDetailSnapshotLoadResult> in
                guard let app else {
                    return .empty()
                }

                return assetDetailSnapshotLoad(app: app, request: request)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.apply(result)
            })
            .disposed(by: snapshotDisposeBag)
    }

    private func bindSupplementalSnapshotPipeline(app: AppModel) {
        supplementalSnapshotDisposeBag = DisposeBag()

        let scheduledRefreshes = Observable<Int>
            .interval(.seconds(Int(Self.supplementalSnapshotRefreshInterval / 1_000_000_000)), scheduler: MainScheduler.instance)
            .map { _ in AssetDetailSupplementalSnapshotRequest.scheduled }

        Observable
            .merge(scheduledRefreshes, supplementalSnapshotRequests.asObservable())
            .observe(on: MainScheduler.instance)
            .flatMapFirst { [weak self, weak app] request -> Observable<AssetDetailSupplementalSnapshotResult> in
                guard let self, let app else {
                    return .empty()
                }

                guard self.shouldFetchSupplementalSnapshot(for: request) else {
                    return .just(.skipped)
                }

                return assetDetailSupplementalSnapshotLoad(
                    app: app,
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

    private func bindStream(app: AppModel) {
        streamDisposeBag = DisposeBag()
        boundStreamFeed = nil
        let streamSymbol = symbol

        do {
            let channels = feed == .overnight ? AlpacaRealtimeChannel.tradeQuote : AlpacaRealtimeChannel.assetDetail
            let source = try app.streamAssetMarketData(symbol: symbol, feed: feed, channels: channels)
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
        if let app, previousFeed != feed || boundStreamFeed != feed {
            bindStream(app: app)
        }
        lastUpdatedAt = Date()
    }

    private func apply(_ result: AssetDetailSnapshotLoadResult) {
        switch result {
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
        feed == .overnight || sessionProgress != nil
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
            if didMergeLatestBar || resolvedSnapshot.feed == .overnight {
                updateChartRenderModels()
            }
            lastUpdatedAt = Date()
        }
        if let app, previousFeed != feed {
            bindStream(app: app)
        }
    }

    private func startLatestBarRefreshLoop(app: AppModel) {
        latestBarRefreshTask?.cancel()
        latestBarRefreshTask = Task { @MainActor [weak self, weak app] in
            while !Task.isCancelled {
                guard let self, let app else {
                    return
                }

                await self.refreshLatestBarIfNeeded(app: app)
                do {
                    try await Task.sleep(nanoseconds: Self.latestBarRefreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func refreshLatestBarIfNeeded(app: AppModel) async {
        guard shouldPollLatestBar else {
            return
        }

        let requestedFeed = feed
        do {
            let latestBar = try await app.fetchLatestStockBar(symbol: symbol, feed: requestedFeed)
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
        selectedRange == .oneDay && sessionProgress != nil
    }

    private func applyBlockingSnapshotFailure(_ error: Error) {
        guard asset == nil, !hasMarketData else {
            errorMessage = nil
            return
        }

        errorMessage = error.localizedDescription
    }

    private func applySupplementalSnapshotFailure(_ error: Error) {
        guard asset == nil, !hasMarketData else {
            errorMessage = nil
            return
        }

        errorMessage = error.localizedDescription
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
        !(range == .oneDay && sessionProgress != nil)
    }

    private func chartRenderInput(from sourceBars: [AlpacaMarketBar], for range: AssetChartRange) -> AssetChartRenderInput {
        let priceChangeBaseline = chartBaselines[range]
        let indexedSourceBars = Self.indexedChartInputBars(from: sourceBars)
        guard range == .oneDay else {
            return AssetChartRenderInput(
                bars: indexedSourceBars,
                xDomain: nil,
                priceChangeBaseline: priceChangeBaseline
            )
        }

        guard feed == .overnight else {
            if let preMarketFallbackInput = preMarketFallbackChartRenderInput(
                from: sourceBars,
                priceChangeBaseline: priceChangeBaseline
            ) {
                return preMarketFallbackInput
            }

            return activeSessionChartRenderInput(
                from: sourceBars,
                priceChangeBaseline: priceChangeBaseline
            ) ?? AssetChartRenderInput(
                bars: indexedSourceBars,
                xDomain: nil,
                priceChangeBaseline: priceChangeBaseline
            )
        }

        let overnightBars = overnightChartBars(referenceBar: sourceBars.last)
        guard !overnightBars.isEmpty,
              let latestOvernightDate = AlpacaDateParser.date(overnightBars.last?.timestamp) else {
            return AssetChartRenderInput(
                bars: indexedSourceBars,
                xDomain: nil,
                priceChangeBaseline: priceChangeBaseline
            )
        }

        let overnightKeys = Set(overnightBars.compactMap(Self.chartBarKey))
        let dedupedSourceBars = sourceBars.filter { bar in
            guard let barKey = Self.chartBarKey(for: bar) else {
                return true
            }

            return !overnightKeys.contains(barKey)
        }

        let sourceInputBars = Self.indexedChartInputBars(from: dedupedSourceBars)
        let sourceCount = sourceInputBars.count
        let overnightInputBars = overnightBars.compactMap { bar -> AssetChartInputBar? in
            guard let barDate = AlpacaDateParser.date(bar.timestamp) else {
                return nil
            }

            return AssetChartInputBar(
                bar: bar,
                xPosition: overnightLatestXPosition(for: barDate, sourceCount: sourceCount)
            )
        }
        guard let latestXPosition = overnightInputBars.last?.xPosition else {
            return AssetChartRenderInput(
                bars: indexedSourceBars,
                xDomain: nil,
                priceChangeBaseline: priceChangeBaseline
            )
        }

        let xDomain = overnightXDomain(
            for: latestOvernightDate,
            sourceCount: sourceCount,
            latestXPosition: latestXPosition
        )

        return AssetChartRenderInput(
            bars: sourceInputBars + overnightInputBars,
            xDomain: xDomain,
            priceChangeBaseline: priceChangeBaseline
        )
    }

    private func preMarketFallbackChartRenderInput(
        from sourceBars: [AlpacaMarketBar],
        priceChangeBaseline: Double?
    ) -> AssetChartRenderInput? {
        guard let interval = activeReferenceInterval(),
              interval.session == .preMarket else {
            return nil
        }

        let baseBars = sourceBars.filter { bar in
            guard let barDate = AlpacaDateParser.date(bar.timestamp) else {
                return false
            }

            return barDate < interval.start
        }
        guard baseBars.count >= 2 else {
            return nil
        }

        let baseInputBars = Self.indexedChartInputBars(from: baseBars)
        let baseCount = baseInputBars.count
        var overlayInputBars = sourceBars.compactMap { bar -> AssetChartInputBar? in
            guard let barDate = AlpacaDateParser.date(bar.timestamp),
                  barDate >= interval.start,
                  barDate <= interval.end else {
                return nil
            }

            return AssetChartInputBar(
                bar: bar,
                xPosition: Double(baseCount) + oneDayXPosition(for: barDate, in: interval)
            )
        }

        if let realtimeInputBar = realtimeActiveSessionInputBar(in: interval) {
            upsertNewerChartInputBar(
                AssetChartInputBar(
                    bar: realtimeInputBar.bar,
                    xPosition: Double(baseCount) + realtimeInputBar.xPosition
                ),
                in: &overlayInputBars
            )
        }

        overlayInputBars.sort { lhs, rhs in
            if lhs.xPosition == rhs.xPosition {
                let lhsDate = AlpacaDateParser.date(lhs.bar.timestamp) ?? .distantPast
                let rhsDate = AlpacaDateParser.date(rhs.bar.timestamp) ?? .distantPast
                return lhsDate < rhsDate
            }

            return lhs.xPosition < rhs.xPosition
        }

        return AssetChartRenderInput(
            bars: baseInputBars + overlayInputBars,
            xDomain: preMarketFallbackXDomain(
                baseCount: baseCount,
                latestXPosition: overlayInputBars.last?.xPosition,
                interval: interval
            ),
            priceChangeBaseline: priceChangeBaseline
        )
    }

    private func preMarketFallbackXDomain(
        baseCount: Int,
        latestXPosition: Double?,
        interval: MarketSessionInterval
    ) -> ClosedRange<Double> {
        let totalUnits = oneDaySlotMetrics(for: interval.end, in: interval).totalUnits
        let upperBound = max(
            Double(baseCount) + totalUnits,
            (latestXPosition ?? 0) + 1,
            Double(baseCount),
            1
        )
        return 0...upperBound
    }

    private func activeSessionChartRenderInput(
        from sourceBars: [AlpacaMarketBar],
        priceChangeBaseline: Double?
    ) -> AssetChartRenderInput? {
        let latestBarDate = sourceBars
            .compactMap { AlpacaDateParser.date($0.timestamp) }
            .last
        guard let interval = activeNonOvernightInterval(for: latestBarDate) else {
            return nil
        }

        let sessionInputBars = sourceBars.compactMap { bar -> AssetChartInputBar? in
            guard let barDate = AlpacaDateParser.date(bar.timestamp),
                  barDate >= interval.start,
                  barDate <= interval.end else {
                return nil
            }

            return AssetChartInputBar(
                bar: bar,
                xPosition: oneDayXPosition(for: barDate, in: interval)
            )
        }
        let inputBars = activeSessionInputBars(
            from: sessionInputBars,
            in: interval,
            priceChangeBaseline: priceChangeBaseline
        )

        guard inputBars.count >= 2 else {
            return nil
        }

        return AssetChartRenderInput(
            bars: inputBars,
            xDomain: oneDayXDomain(for: interval, latestXPosition: inputBars.last?.xPosition),
            priceChangeBaseline: priceChangeBaseline
        )
    }

    private func activeSessionInputBars(
        from inputBars: [AssetChartInputBar],
        in interval: MarketSessionInterval,
        priceChangeBaseline: Double?
    ) -> [AssetChartInputBar] {
        var resolvedInputBars = inputBars
        if let realtimeInputBar = realtimeActiveSessionInputBar(in: interval) {
            upsertNewerChartInputBar(realtimeInputBar, in: &resolvedInputBars)
        }

        if resolvedInputBars.count < 2,
           let openingInputBar = openingActiveSessionInputBar(
            in: interval,
            inputBars: resolvedInputBars,
            priceChangeBaseline: priceChangeBaseline
           ) {
            appendUniqueChartInputBar(openingInputBar, to: &resolvedInputBars)
        }

        return resolvedInputBars.sorted { lhs, rhs in
            if lhs.xPosition == rhs.xPosition {
                let lhsDate = AlpacaDateParser.date(lhs.bar.timestamp) ?? .distantPast
                let rhsDate = AlpacaDateParser.date(rhs.bar.timestamp) ?? .distantPast
                return lhsDate < rhsDate
            }

            return lhs.xPosition < rhs.xPosition
        }
    }

    private func realtimeActiveSessionInputBar(in interval: MarketSessionInterval) -> AssetChartInputBar? {
        guard let realtimePrice = latestRealtimeChartPrice(),
              let realtimeDate = AlpacaDateParser.date(realtimePrice.timestamp),
              realtimeDate >= interval.start,
              realtimeDate <= interval.end else {
            return nil
        }

        let chartDate = Self.minuteTimestamp(for: realtimeDate)
        return AssetChartInputBar(
            bar: AlpacaMarketBar(
                symbol: symbol,
                open: realtimePrice.price,
                high: realtimePrice.price,
                low: realtimePrice.price,
                close: realtimePrice.price,
                volume: 0,
                vwap: nil,
                tradeCount: nil,
                timestamp: Self.chartTimestampFormatter.string(from: chartDate)
            ),
            xPosition: oneDayXPosition(for: chartDate, in: interval)
        )
    }

    private func openingActiveSessionInputBar(
        in interval: MarketSessionInterval,
        inputBars: [AssetChartInputBar],
        priceChangeBaseline: Double?
    ) -> AssetChartInputBar? {
        let price = priceChangeBaseline
            ?? previousClose
            ?? inputBars.first?.bar.open
            ?? inputBars.first?.bar.close
            ?? dayOpen
            ?? latestCoreSessionClose
            ?? currentPrice
        guard Self.hasValidMarketPrice(price) else {
            return nil
        }

        return AssetChartInputBar(
            bar: AlpacaMarketBar(
                symbol: symbol,
                open: price,
                high: price,
                low: price,
                close: price,
                volume: 0,
                vwap: nil,
                tradeCount: nil,
                timestamp: Self.chartTimestampFormatter.string(from: interval.start)
            ),
            xPosition: oneDayXPosition(for: interval.start, in: interval)
        )
    }

    private func upsertNewerChartInputBar(
        _ inputBar: AssetChartInputBar,
        in inputBars: inout [AssetChartInputBar]
    ) {
        guard let inputKey = Self.chartBarKey(for: inputBar.bar) else {
            inputBars.append(inputBar)
            return
        }

        guard let index = inputBars.firstIndex(where: { Self.chartBarKey(for: $0.bar) == inputKey }) else {
            inputBars.append(inputBar)
            return
        }

        let existingDate = AlpacaDateParser.date(inputBars[index].bar.timestamp) ?? .distantPast
        let inputDate = AlpacaDateParser.date(inputBar.bar.timestamp) ?? .distantPast
        if inputDate >= existingDate {
            inputBars[index] = inputBar
        }
    }

    private func appendUniqueChartInputBar(
        _ inputBar: AssetChartInputBar,
        to inputBars: inout [AssetChartInputBar]
    ) {
        guard let inputKey = Self.chartBarKey(for: inputBar.bar) else {
            inputBars.append(inputBar)
            return
        }

        guard !inputBars.contains(where: { Self.chartBarKey(for: $0.bar) == inputKey }) else {
            return
        }

        inputBars.append(inputBar)
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

    private func overnightLatestXPosition(for date: Date, sourceCount: Int) -> Double {
        guard let slotMetrics = overnightSlotMetrics(for: date) else {
            return Double(sourceCount)
        }

        return Double(sourceCount) + slotMetrics.elapsedUnits
    }

    private func overnightXDomain(
        for date: Date,
        sourceCount: Int,
        latestXPosition: Double
    ) -> ClosedRange<Double> {
        let upperBound: Double
        if let slotMetrics = overnightSlotMetrics(for: date) {
            upperBound = Double(sourceCount) + slotMetrics.totalUnits
        } else {
            upperBound = latestXPosition + 1
        }

        return 0...max(upperBound, latestXPosition + 1, 1)
    }

    private func overnightSlotMetrics(for date: Date) -> (elapsedUnits: Double, totalUnits: Double)? {
        guard let interval = activeOvernightInterval(for: date) else {
            return nil
        }

        return oneDaySlotMetrics(for: date, in: interval)
    }

    private func oneDayXPosition(for date: Date, in interval: MarketSessionInterval) -> Double {
        oneDaySlotMetrics(for: date, in: interval).elapsedUnits
    }

    private func oneDayXDomain(
        for interval: MarketSessionInterval,
        latestXPosition: Double?
    ) -> ClosedRange<Double> {
        let totalUnits = oneDaySlotMetrics(for: interval.end, in: interval).totalUnits
        return 0...max(totalUnits, (latestXPosition ?? 0) + 1, 1)
    }

    private func oneDaySlotMetrics(
        for date: Date,
        in interval: MarketSessionInterval
    ) -> (elapsedUnits: Double, totalUnits: Double) {
        let totalSlots = max(
            1.0,
            interval.end.timeIntervalSince(interval.start) / Self.oneDayChartSlotDuration
        )
        let elapsedSlots = date.timeIntervalSince(interval.start) / Self.oneDayChartSlotDuration
        return (min(max(elapsedSlots, 0), totalSlots), totalSlots)
    }

    private func activeOvernightInterval(for date: Date) -> MarketSessionInterval? {
        if let containingDate = sessionProgress?.intervals.first(where: { interval in
            interval.session == .overnight && interval.contains(date)
        }) {
            return containingDate
        }

        if let referenceDate = sessionProgress?.referenceDate,
           let containingReference = sessionProgress?.intervals.first(where: { interval in
               interval.session == .overnight && interval.contains(referenceDate)
           }) {
            return containingReference
        }

        return sessionProgress?.intervals.first { interval in
            interval.session == .overnight
        }
    }

    private func activeReferenceInterval() -> MarketSessionInterval? {
        guard let sessionProgress else {
            return nil
        }

        return sessionProgress.intervals
            .filter { $0.contains(sessionProgress.referenceDate) }
            .min { lhs, rhs in
                if lhs.session.activePriority == rhs.session.activePriority {
                    return lhs.start < rhs.start
                }

                return lhs.session.activePriority < rhs.session.activePriority
            }
    }

    private func activeNonOvernightInterval(for date: Date?) -> MarketSessionInterval? {
        let intervals = sessionProgress?.intervals.filter { $0.session != .overnight } ?? []
        if let date,
           let containingDate = intervals.first(where: { $0.contains(date) }) {
            return containingDate
        }

        if let referenceDate = sessionProgress?.referenceDate,
           let containingReference = intervals.first(where: { $0.contains(referenceDate) }) {
            return containingReference
        }

        return nil
    }

    private func overnightChartBars(referenceBar: AlpacaMarketBar?) -> [AlpacaMarketBar] {
        var barsByKey: [Int: AlpacaMarketBar] = [:]

        for bar in overnightSupplementBars {
            storeOvernightChartBar(bar, in: &barsByKey)
        }

        if let latestBar = latestOvernightChartBar(referenceBar: referenceBar) {
            storeOvernightChartBar(latestBar, in: &barsByKey)
        }

        let referenceDate = AlpacaDateParser.date(referenceBar?.timestamp)
        return barsByKey.values
            .filter { bar in
                guard let barDate = AlpacaDateParser.date(bar.timestamp) else {
                    return false
                }

                if let referenceDate {
                    return barDate > referenceDate
                }

                return true
            }
            .sorted { lhs, rhs in
                let lhsDate = AlpacaDateParser.date(lhs.timestamp) ?? .distantPast
                let rhsDate = AlpacaDateParser.date(rhs.timestamp) ?? .distantPast
                return lhsDate < rhsDate
            }
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

        mergeOvernightSupplementBar(latestOvernightChartBar(referenceBar: bars.last))
    }

    private func mergeOvernightSupplementBar(_ bar: AlpacaMarketBar?) {
        guard let bar,
              feed == .overnight,
              selectedRange == .oneDay,
              let barKey = Self.chartBarKey(for: bar) else {
            return
        }

        if let index = overnightSupplementBars.firstIndex(where: { Self.chartBarKey(for: $0) == barKey }) {
            overnightSupplementBars[index] = newerOvernightBar(
                current: overnightSupplementBars[index],
                candidate: bar
            )
        } else {
            overnightSupplementBars.append(bar)
        }

        overnightSupplementBars = Self.normalizedBars(overnightSupplementBars)
        if overnightSupplementBars.count > 300 {
            overnightSupplementBars.removeFirst(overnightSupplementBars.count - 300)
        }
    }

    private func storeOvernightChartBar(_ bar: AlpacaMarketBar, in barsByKey: inout [Int: AlpacaMarketBar]) {
        guard let barKey = Self.chartBarKey(for: bar) else {
            return
        }

        barsByKey[barKey] = newerOvernightBar(current: barsByKey[barKey], candidate: bar)
    }

    private func newerOvernightBar(current: AlpacaMarketBar?, candidate: AlpacaMarketBar) -> AlpacaMarketBar {
        guard let current,
              let currentDate = AlpacaDateParser.date(current.timestamp),
              let candidateDate = AlpacaDateParser.date(candidate.timestamp) else {
            return candidate
        }

        return candidateDate >= currentDate ? candidate : current
    }

    private func latestOvernightChartBar(referenceBar: AlpacaMarketBar?) -> AlpacaMarketBar? {
        let baseBar = latestOvernightBar ?? makeSyntheticChartBar(
            price: referenceBar?.close ?? latestCoreSessionClose ?? 0,
            timestamp: nil,
            referenceBar: referenceBar
        )

        guard let baseBar else {
            return nil
        }

        return applyingLatestRealtimePrice(to: baseBar)
    }

    private func applyingLatestRealtimePrice(to baseBar: AlpacaMarketBar) -> AlpacaMarketBar {
        guard let realtimePrice = latestRealtimeChartPrice(),
              let realtimeDate = AlpacaDateParser.date(realtimePrice.timestamp),
              let baseDate = AlpacaDateParser.date(baseBar.timestamp),
              realtimeDate >= baseDate else {
            return baseBar
        }

        let realtimeMinute = Self.minuteTimestamp(for: realtimeDate)
        if realtimeMinute == baseDate {
            return AlpacaMarketBar(
                symbol: symbol,
                open: baseBar.open,
                high: max(baseBar.high ?? realtimePrice.price, realtimePrice.price),
                low: min(baseBar.low ?? realtimePrice.price, realtimePrice.price),
                close: realtimePrice.price,
                volume: baseBar.volume,
                vwap: baseBar.vwap,
                tradeCount: baseBar.tradeCount,
                timestamp: baseBar.timestamp
            )
        }

        let open = baseBar.close ?? realtimePrice.price
        return AlpacaMarketBar(
            symbol: symbol,
            open: open,
            high: max(open, realtimePrice.price),
            low: min(open, realtimePrice.price),
            close: realtimePrice.price,
            volume: 0,
            vwap: nil,
            tradeCount: nil,
            timestamp: Self.chartTimestampFormatter.string(from: realtimeMinute)
        )
    }

    private func latestRealtimeChartPrice() -> (price: Double, timestamp: String)? {
        let tradePrice: (price: Double, timestamp: String)?
        if let price = latestTrade?.price,
           Self.hasValidMarketPrice(price),
           let timestamp = latestTrade?.timestamp {
            tradePrice = (price, timestamp)
        } else {
            tradePrice = nil
        }

        let quotePrice: (price: Double, timestamp: String)?
        if let price = Self.chartQuotePrice(quote),
           let timestamp = quote?.timestamp {
            quotePrice = (price, timestamp)
        } else {
            quotePrice = nil
        }

        return Self.newerChartPrice(preferred: tradePrice, fallback: quotePrice)
    }

    private static func newerChartPrice(
        preferred: (price: Double, timestamp: String)?,
        fallback: (price: Double, timestamp: String)?
    ) -> (price: Double, timestamp: String)? {
        guard let preferred else {
            return fallback
        }

        guard let fallback else {
            return preferred
        }

        guard let preferredDate = AlpacaDateParser.date(preferred.timestamp) else {
            return AlpacaDateParser.date(fallback.timestamp) == nil ? preferred : fallback
        }

        guard let fallbackDate = AlpacaDateParser.date(fallback.timestamp) else {
            return preferred
        }

        return preferredDate >= fallbackDate ? preferred : fallback
    }

    private static func chartQuotePrice(_ quote: AlpacaRealtimeQuote?) -> Double? {
        guard let quote else {
            return nil
        }

        switch (hasValidMarketPrice(quote.bidPrice), hasValidMarketPrice(quote.askPrice)) {
        case (true, true):
            return ((quote.bidPrice ?? 0) + (quote.askPrice ?? 0)) / 2
        case (true, false):
            return quote.bidPrice
        case (false, true):
            return quote.askPrice
        case (false, false):
            return nil
        }
    }

    private func makeSyntheticChartBar(
        price: Double,
        timestamp: String?,
        referenceBar: AlpacaMarketBar?
    ) -> AlpacaMarketBar? {
        guard price > 0 else {
            return nil
        }

        let referenceClose = referenceBar?.close ?? latestCoreSessionClose ?? price
        let timestamp = timestamp ?? Self.chartTimestampFormatter.string(from: Date())
        let eventDate = AlpacaDateParser.date(timestamp)
        let referenceDate = AlpacaDateParser.date(referenceBar?.timestamp)
        if let eventDate, let referenceDate, eventDate <= referenceDate {
            return nil
        }

        return AlpacaMarketBar(
            symbol: symbol,
            open: referenceClose,
            high: max(referenceClose, price),
            low: min(referenceClose, price),
            close: price,
            volume: 0,
            vwap: nil,
            tradeCount: nil,
            timestamp: timestamp
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
        let sortedBars = bars.sorted { lhs, rhs in
            let lhsDate = AlpacaDateParser.date(lhs.timestamp) ?? .distantPast
            let rhsDate = AlpacaDateParser.date(rhs.timestamp) ?? .distantPast
            return lhsDate < rhsDate
        }

        guard sortedBars.count > 900 else {
            return sortedBars
        }

        return Array(sortedBars.suffix(900))
    }

    private static func hasValidMarketPrice(_ price: Double?) -> Bool {
        guard let price else {
            return false
        }

        return price.isFinite && price > 0
    }

    private static func hasValidQuotePrice(_ quote: AlpacaStockQuote) -> Bool {
        hasValidMarketPrice(quote.bidPrice) || hasValidMarketPrice(quote.askPrice)
    }

    private static func hasValidQuotePrice(_ quote: AlpacaRealtimeQuote) -> Bool {
        hasValidMarketPrice(quote.bidPrice) || hasValidMarketPrice(quote.askPrice)
    }

    private static func indexedChartInputBars(from bars: [AlpacaMarketBar]) -> [AssetChartInputBar] {
        bars.enumerated().map { offset, bar in
            AssetChartInputBar(bar: bar, xPosition: Double(offset))
        }
    }

    private static func chartBarKey(for bar: AlpacaMarketBar) -> Int? {
        guard let date = AlpacaDateParser.date(bar.timestamp) else {
            return nil
        }

        return Int(floor(date.timeIntervalSince1970 / 60))
    }

    private static func minuteTimestamp(for date: Date) -> Date {
        let interval = floor(date.timeIntervalSince1970 / 60) * 60
        return Date(timeIntervalSince1970: interval)
    }

    private static let chartTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withColonSeparatorInTimeZone
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

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

private struct AssetChartRenderInput: Sendable {
    let bars: [AssetChartInputBar]
    let xDomain: ClosedRange<Double>?
    let priceChangeBaseline: Double?
}

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

private func assetDetailSnapshotLoad(
    app: AppModel,
    request: AssetDetailSnapshotRequest
) -> Observable<AssetDetailSnapshotLoadResult> {
    Observable.create { observer in
        let observerBox = AssetDetailSnapshotLoadObserverBox(observer)
        let task = Task { @MainActor [app, request, observerBox] in
            do {
                let snapshot = try await app.fetchAssetDetailSnapshot(
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
            task.cancel()
        }
    }
}

private func assetDetailSupplementalSnapshotLoad(
    app: AppModel,
    symbol: String,
    feed: AlpacaMarketDataFeed
) -> Observable<AssetDetailSupplementalSnapshotResult> {
    Observable.create { observer in
        let observerBox = AssetDetailSupplementalSnapshotObserverBox(observer)
        let task = Task { @MainActor [app, symbol, feed, observerBox] in
            do {
                let snapshot = try await app.fetchResolvedAssetSnapshot(symbol: symbol, feed: feed)
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
