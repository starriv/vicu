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
    /// Returning to a 1D chart after this long refetches bars so the time away isn't a gap.
    private static let oneDayResumeReloadThreshold: TimeInterval = 60
    private static let optimisticConnectionFreshnessThreshold: TimeInterval = 5 * 60
    private static let easternCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    var selectedRange: AssetChartRange = .oneDay
    var chartMode: AssetChartMode = .line
    var showsTradeMarkers = true
    var feed: AlpacaMarketDataFeed = .iex
    var asset: AlpacaAsset? {
        didSet { updateCachedAssetMetadata() }
    }
    var quote: AlpacaRealtimeQuote? {
        didSet { parsedQuoteDate = AlpacaDateParser.date(quote?.timestamp) }
    }
    var latestTrade: AlpacaRealtimeTrade? {
        didSet { parsedLatestTradeDate = AlpacaDateParser.date(latestTrade?.timestamp) }
    }
    var dailyBar: AlpacaMarketBar? {
        didSet { parsedDailyBarDate = AlpacaDateParser.date(dailyBar?.timestamp) }
    }
    var previousDailyBar: AlpacaMarketBar?
    var position: AlpacaPosition?
    var chartRenderModels: AssetChartRenderModels = .empty
    private(set) var chartTradeMarkers: AssetChartTradeMarkerSet = .empty
    var tradingStatus: AlpacaRealtimeTradingStatus?
    var connectionStatus: AssetRealtimeConnectionStatus = .disconnected
    var latestCoreSessionClose: Double?
    var sessionProgress: MarketSessionProgress? {
        didSet { updateCachedSessionMetadata() }
    }
    var isLoading = false
    var isLoadingChart = false
    var errorMessage: String?
    var lastUpdatedAt: Date?

    // Cached derived properties to avoid repeated parsing/allocations during SwiftUI body passes & 120Hz scrubbing
    private(set) var displayName: String = AppFormatter.placeholder
    private(set) var exchangeText: String = AppFormatter.placeholder
    private(set) var assetClassText: String = AppFormatter.placeholder
    private(set) var supportsOptions = false
    private(set) var sessionTimeline: MarketSessionTimeline?

    @ObservationIgnored private var parsedLatestTradeDate: Date?
    @ObservationIgnored private var parsedQuoteDate: Date?
    @ObservationIgnored private var parsedDailyBarDate: Date?
    @ObservationIgnored private var cachedHasActiveSessionProgress = false
    @ObservationIgnored private var cachedActiveReferenceInterval: MarketSessionInterval?

    @ObservationIgnored private weak var service: (any AssetDetailServicing)?
    @ObservationIgnored private var streamDisposeBag = DisposeBag()
    @ObservationIgnored private var snapshotLoadTask: Task<Void, Never>?
    @ObservationIgnored private var supplementalRefreshLoopTask: Task<Void, Never>?
    @ObservationIgnored private var supplementalFetchTask: Task<Void, Never>?
    @ObservationIgnored private var latestBarRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var immediateLatestBarTask: Task<Void, Never>?
    @ObservationIgnored private var positionLoadTask: Task<Void, Never>?
    @ObservationIgnored private var tradeExecutionsLoadTask: Task<Void, Never>?
    @ObservationIgnored private var tradeExecutions: [AssetTradeExecution] = []
    @ObservationIgnored private var hasLoadedTradeExecutions = false
    @ObservationIgnored private var chartRenderTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotRequestID = 0
    @ObservationIgnored private var chartRenderRevision = 0
    @ObservationIgnored private var snapshotContentRevision = 0
    @ObservationIgnored private var shouldResyncOnLive = false
    /// Range whose freshly fetched snapshot bars are still being rendered off-main.
    /// Realtime updates during that window are deferred instead of cancelling the render,
    /// otherwise the downloaded bars would be dropped.
    @ObservationIgnored private var pendingSnapshotRenderRange: AssetChartRange?
    @ObservationIgnored private var deferredRealtimeBars: [AlpacaMarketBar] = []
    @ObservationIgnored private var hasDeferredRealtimeChartUpdate = false
    /// Set by `stop()` when a range load or render was cut off, so `start()` redoes it.
    @ObservationIgnored private var needsSnapshotReloadOnResume = false
    @ObservationIgnored private var stoppedAt: Date?
    @ObservationIgnored private var barSeries = AssetDetailBarSeries()
    @ObservationIgnored private var latestOvernightBar: AlpacaMarketBar?
    @ObservationIgnored private var chartBaselines: [AssetChartRange: Double] = [:]
    @ObservationIgnored private var chartCache: [AssetChartRange: AssetChartCacheEntry] = [:]
    @ObservationIgnored private var boundStreamFeed: AlpacaMarketDataFeed?
    @ObservationIgnored private let realtimeScheduler = SerialDispatchQueueScheduler(qos: .userInitiated)

    init(symbol: String) {
        self.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // MARK: - Derived Price & Session State

    var currentPrice: Double? {
        if cachedHasActiveSessionProgress || hasRecentMarketData,
           let latestTradePrice = latestTrade?.price {
            return latestTradePrice
        }

        if let completedExtendedTradingPrice {
            return completedExtendedTradingPrice.price
        }

        return dailyBar?.close ?? barSeries.latestClose ?? latestTrade?.price
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
        guard let activeSession = cachedActiveReferenceInterval?.session.extendedTradingSession,
              let eventDate = lastEventDate,
              Self.extendedTradingSession(for: eventDate) == activeSession else {
            return nil
        }

        return activeSession
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
        guard !cachedHasActiveSessionProgress,
              let sessionProgress,
              let latestTradePrice = latestTrade?.price,
              Self.hasValidMarketPrice(latestTradePrice),
              let latestTradeDate = parsedLatestTradeDate,
              let interval = AssetIntradaySessionMapper.completedExtendedInterval(containing: latestTradeDate, in: sessionProgress),
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
        parsedLatestTradeDate ?? parsedQuoteDate ?? parsedDailyBarDate ?? lastUpdatedAt
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

    var effectiveChartMode: AssetChartMode {
        selectedRange == .oneDay ? .line : chartMode
    }

    // MARK: - Lifecycle

    func start(service: any AssetDetailServicing) {
        self.service = service
        startSupplementalRefreshLoop(service: service)
        startLatestBarRefreshLoop(service: service)

        if asset != nil {
            // Re-appearing after push navigation (e.g. returning from TradeView):
            // resume live stream and refresh position + supplemental quote without resetting UI.
            if boundStreamFeed != feed {
                bindStream(service: service)
            }
            loadOpenPosition(service: service)
            let isOneDayStale = selectedRange == .oneDay
                && (stoppedAt.map { Date().timeIntervalSince($0) > Self.oneDayResumeReloadThreshold } ?? false)
            if needsSnapshotReloadOnResume || isOneDayStale {
                needsSnapshotReloadOnResume = false
                startSnapshotLoad(
                    service: service,
                    range: selectedRange,
                    feed: feed,
                    showsBlockingLoading: false
                )
            } else {
                triggerSupplementalSnapshotRefresh(forced: true)
            }
            stoppedAt = nil
        } else {
            reload(service: service)
        }
    }

    func stop() {
        if isLoadingChart || pendingSnapshotRenderRange != nil {
            needsSnapshotReloadOnResume = true
        }
        stoppedAt = Date()
        clearPendingSnapshotRender()
        streamDisposeBag = DisposeBag()
        snapshotLoadTask?.cancel()
        snapshotLoadTask = nil
        supplementalRefreshLoopTask?.cancel()
        supplementalRefreshLoopTask = nil
        supplementalFetchTask?.cancel()
        supplementalFetchTask = nil
        latestBarRefreshTask?.cancel()
        latestBarRefreshTask = nil
        immediateLatestBarTask?.cancel()
        immediateLatestBarTask = nil
        positionLoadTask?.cancel()
        positionLoadTask = nil
        tradeExecutionsLoadTask?.cancel()
        tradeExecutionsLoadTask = nil
        chartRenderTask?.cancel()
        chartRenderTask = nil
        chartRenderRevision += 1
        snapshotRequestID += 1
        boundStreamFeed = nil
        connectionStatus = .disconnected
    }

    func reload(service: (any AssetDetailServicing)? = nil) {
        let resolvedService = service ?? self.service
        guard let resolvedService else {
            return
        }

        self.service = resolvedService
        startSnapshotLoad(
            service: resolvedService,
            range: selectedRange,
            feed: feed,
            showsBlockingLoading: asset == nil
        )
        loadOpenPosition(service: resolvedService)
        if showsTradeMarkers && selectedRange != .oneDay {
            loadTradeExecutions(service: resolvedService, forceRefresh: true)
        } else {
            hasLoadedTradeExecutions = false
        }
    }

    /// Async pull-to-refresh entry point so SwiftUI `.refreshable` stays active until refresh completes.
    func refresh(service: (any AssetDetailServicing)? = nil) async {
        let resolvedService = service ?? self.service
        guard let resolvedService else {
            return
        }

        self.service = resolvedService
        startSnapshotLoad(
            service: resolvedService,
            range: selectedRange,
            feed: feed,
            showsBlockingLoading: asset == nil
        )
        loadOpenPosition(service: resolvedService)
        if showsTradeMarkers && selectedRange != .oneDay {
            loadTradeExecutions(service: resolvedService, forceRefresh: true)
        } else {
            hasLoadedTradeExecutions = false
        }

        if let snapshotLoadTask {
            await snapshotLoadTask.value
        }
        if let positionLoadTask {
            await positionLoadTask.value
        }
    }

    // MARK: - Trade Markers

    func setShowsTradeMarkers(_ enabled: Bool) {
        guard showsTradeMarkers != enabled else {
            if enabled, selectedRange != .oneDay, !hasLoadedTradeExecutions, let service {
                loadTradeExecutions(service: service, forceRefresh: false)
            }
            return
        }

        showsTradeMarkers = enabled
        guard enabled else {
            tradeExecutionsLoadTask?.cancel()
            tradeExecutionsLoadTask = nil
            chartTradeMarkers = .empty
            return
        }

        guard selectedRange != .oneDay else {
            chartTradeMarkers = .empty
            return
        }

        if hasLoadedTradeExecutions {
            recomputeChartTradeMarkers()
        } else if let service {
            loadTradeExecutions(service: service, forceRefresh: false)
        }
    }

    func invalidateTradeExecutions() {
        hasLoadedTradeExecutions = false
        if showsTradeMarkers, selectedRange != .oneDay, let service {
            loadTradeExecutions(service: service, forceRefresh: true)
        }
    }

    func tradeMarkers(for point: AssetChartPoint) -> [FinancialChartTradeMarker] {
        guard showsTradeMarkers, selectedRange != .oneDay else {
            return []
        }
        return chartTradeMarkers.markers(for: point)
    }

    private func loadTradeExecutions(service: any AssetDetailServicing, forceRefresh: Bool) {
        guard showsTradeMarkers else {
            return
        }

        if !forceRefresh, tradeExecutionsLoadTask != nil {
            return
        }

        tradeExecutionsLoadTask?.cancel()
        let requestedSymbol = symbol
        let afterDate = AssetTradeMarkerMapper.historyStartDate()
        tradeExecutionsLoadTask = Task { @MainActor [weak self, weak service] in
            defer {
                if let self, !Task.isCancelled {
                    self.tradeExecutionsLoadTask = nil
                }
            }
            guard let self, let service else {
                return
            }

            do {
                let orders = try await service.fetchSymbolOrders(
                    symbol: requestedSymbol,
                    after: afterDate,
                    forceRefresh: forceRefresh
                )
                try Task.checkCancellation()
                guard self.symbol == requestedSymbol else {
                    return
                }

                let parsed = await Task.detached(priority: .utility) {
                    AssetTradeMarkerMapper.executions(from: orders, symbol: requestedSymbol)
                }.value
                try Task.checkCancellation()
                guard self.symbol == requestedSymbol else {
                    return
                }

                self.tradeExecutions = parsed
                self.hasLoadedTradeExecutions = true
                self.recomputeChartTradeMarkers()
            } catch where error.isRequestCancellation {
                return
            } catch {
                // Non-blocking: trade markers are optional overlays and must never disrupt the price chart.
                return
            }
        }
    }

    private func recomputeChartTradeMarkers() {
        guard showsTradeMarkers, selectedRange != .oneDay, !tradeExecutions.isEmpty else {
            if !chartTradeMarkers.isEmpty {
                chartTradeMarkers = .empty
            }
            return
        }

        let activePoints = chartRenderModels.model(for: effectiveChartMode).financialPoints
        guard !activePoints.isEmpty else {
            if !chartTradeMarkers.isEmpty {
                chartTradeMarkers = .empty
            }
            return
        }

        let nextMarkers = AssetTradeMarkerMapper.map(
            executions: tradeExecutions,
            onto: activePoints,
            range: selectedRange
        )
        if chartTradeMarkers != nextMarkers {
            chartTradeMarkers = nextMarkers
        }
    }

    // MARK: - User Interactions

    func selectRange(_ range: AssetChartRange) {
        guard selectedRange != range else {
            return
        }

        selectedRange = range
        if range == .oneDay {
            chartTradeMarkers = .empty
        } else if showsTradeMarkers, !hasLoadedTradeExecutions, let service {
            loadTradeExecutions(service: service, forceRefresh: false)
        }

        if applyCachedChart(for: range) {
            // Cancel any in-flight range fetch so a slower previous request cannot overwrite this cached range.
            snapshotLoadTask?.cancel()
            snapshotLoadTask = nil
            snapshotRequestID += 1
            isLoadingChart = false
            errorMessage = nil
            recomputeChartTradeMarkers()
            return
        }

        isLoadingChart = true
        guard let service else {
            return
        }

        startSnapshotLoad(
            service: service,
            range: range,
            feed: feed,
            showsBlockingLoading: false
        )
    }

    func selectChartMode(_ mode: AssetChartMode) {
        guard chartMode != mode else {
            return
        }

        // O(1) instant mode toggle: `chartRenderModels` already holds both `.line` and `.candles`
        // sharing the exact same precomputed point arrays & digest.
        chartMode = mode
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

    // MARK: - Cached Metadata Helpers

    private func updateCachedAssetMetadata() {
        displayName = AppFormatter.displayText(asset?.name?.displayAssetName)
        exchangeText = AppFormatter.displayText(asset?.exchange)
        assetClassText = asset?.assetClass?
            .replacingOccurrences(of: "_", with: " ")
            .uppercased() ?? AppFormatter.placeholder
        supportsOptions = asset?.attributes?.contains("has_options") == true
    }

    private func updateCachedSessionMetadata() {
        sessionTimeline = MarketSessionTimeline(progress: sessionProgress)
        cachedActiveReferenceInterval = AssetIntradaySessionMapper.activeReferenceInterval(in: sessionProgress)
        if let sessionProgress {
            cachedHasActiveSessionProgress = sessionProgress.intervals.contains { interval in
                interval.contains(sessionProgress.referenceDate)
            }
        } else {
            cachedHasActiveSessionProgress = false
        }
    }

    private var shareChartRenderModel: AssetChartRenderModel {
        let lineModel = chartRenderModels.line
        let fallbackModel = chartRenderModels.model(for: effectiveChartMode)
        return lineModel.points.isEmpty ? fallbackModel : lineModel
    }

    // MARK: - Snapshot & Position Loading

    private func startSnapshotLoad(
        service: any AssetDetailServicing,
        range: AssetChartRange,
        feed requestedFeed: AlpacaMarketDataFeed,
        showsBlockingLoading: Bool
    ) {
        snapshotLoadTask?.cancel()
        snapshotRequestID += 1
        let requestID = snapshotRequestID

        isLoading = showsBlockingLoading
        isLoadingChart = true
        errorMessage = nil

        let requestedSymbol = symbol

        snapshotLoadTask = Task { @MainActor [weak self, weak service] in
            guard let self, let service else {
                return
            }

            // On cold start, fire an early lightweight snapshot in parallel to populate price/L1 immediately.
            let earlySnapshotTask: Task<Void, Never>? = showsBlockingLoading
                ? Task { @MainActor [weak self, weak service] in
                    guard let self, let service else { return }
                    do {
                        guard let earlySnapshot = try await service.fetchAssetSnapshot(
                            symbol: requestedSymbol,
                            feed: requestedFeed
                        ) else {
                            return
                        }
                        guard !Task.isCancelled,
                              self.snapshotRequestID == requestID,
                              self.selectedRange == range,
                              self.isLoading else {
                            return
                        }
                        self.apply(earlySnapshot)
                        if self.hasMarketData {
                            self.isLoading = false
                            self.lastUpdatedAt = Date()
                        }
                    } catch {
                        return
                    }
                }
                : nil

            defer {
                earlySnapshotTask?.cancel()
            }

            do {
                let snapshot = try await service.fetchAssetDetailSnapshot(
                    symbol: requestedSymbol,
                    range: range,
                    feed: requestedFeed
                )
                guard !Task.isCancelled, self.snapshotRequestID == requestID else {
                    return
                }
                guard self.selectedRange == snapshot.range else {
                    return
                }

                earlySnapshotTask?.cancel()
                self.apply(snapshot)
                self.isLoading = false
                self.errorMessage = nil
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled, self.snapshotRequestID == requestID else {
                    return
                }
                guard self.selectedRange == range else {
                    return
                }

                self.isLoading = false
                self.isLoadingChart = false
                self.applyBlockingSnapshotFailure(error)
            }
        }
    }

    private func loadOpenPosition(service: any AssetDetailServicing) {
        positionLoadTask?.cancel()
        let requestedSymbol = symbol
        positionLoadTask = Task { @MainActor [weak self, weak service] in
            guard let self, let service else {
                return
            }

            do {
                // `AlpacaClient.fetchOpenPosition` returns `nil` on HTTP 404 (no position).
                let loadedPosition = try await service.fetchOpenPosition(symbol: requestedSymbol)
                guard !Task.isCancelled, self.symbol == requestedSymbol else {
                    return
                }

                self.position = loadedPosition
            } catch where error.isRequestCancellation {
                return
            } catch {
                // Keep any previously loaded position on transient network failure instead of wiping UI.
                return
            }
        }
    }

    // MARK: - Supplemental & Latest Bar Polling

    private func startSupplementalRefreshLoop(service: any AssetDetailServicing) {
        supplementalRefreshLoopTask?.cancel()
        supplementalRefreshLoopTask = Task { @MainActor [weak self, weak service] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.supplementalSnapshotRefreshInterval)
                } catch {
                    return
                }

                guard let self, service != nil, !Task.isCancelled else {
                    return
                }

                self.triggerSupplementalSnapshotRefresh(forced: false)
            }
        }
    }

    private func triggerSupplementalSnapshotRefresh(forced: Bool) {
        guard let service else {
            return
        }

        // Coalesce like `flatMapFirst`: skip if a supplemental refresh is already running.
        guard supplementalFetchTask == nil else {
            return
        }

        if !forced {
            guard shouldRunSupplementalSnapshotRefresh else {
                return
            }
            if let lastUpdatedAt,
               Date().timeIntervalSince(lastUpdatedAt) < Self.supplementalSnapshotQuietThreshold {
                return
            }
        }

        let requestedSymbol = symbol
        let requestedFeed = feed

        supplementalFetchTask = Task { @MainActor [weak self, weak service] in
            defer {
                // A cancelled task finishing late must not clear its replacement.
                if !Task.isCancelled {
                    self?.supplementalFetchTask = nil
                }
            }
            guard let self, let service else {
                return
            }

            do {
                let resolvedSnapshot = try await service.fetchResolvedAssetSnapshot(
                    symbol: requestedSymbol,
                    feed: requestedFeed
                )
                guard !Task.isCancelled, self.feed == requestedFeed else {
                    return
                }
                self.apply(resolvedSnapshot)
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled, self.feed == requestedFeed else {
                    return
                }
                self.applySupplementalSnapshotFailure(error)
            }
        }
    }

    private var shouldRunSupplementalSnapshotRefresh: Bool {
        feed == .overnight || cachedHasActiveSessionProgress
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

    private func refreshLatestBarSoon() {
        guard shouldPollLatestBar, let service else {
            return
        }

        immediateLatestBarTask?.cancel()
        immediateLatestBarTask = Task { @MainActor [weak self, weak service] in
            guard let self, let service else {
                return
            }

            await self.refreshLatestBarIfNeeded(service: service)
            if !Task.isCancelled {
                self.immediateLatestBarTask = nil
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
            guard !Task.isCancelled, feed == requestedFeed, selectedRange == .oneDay else {
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
        selectedRange == .oneDay && cachedHasActiveSessionProgress
    }

    // MARK: - Realtime WebSocket Stream

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

    // MARK: - State Application

    private func apply(_ snapshot: AssetDetailSnapshot) {
        snapshotContentRevision += 1
        let previousFeed = feed
        feed = snapshot.feed
        sessionProgress = snapshot.sessionProgress
        asset = snapshot.asset
        selectedRange = snapshot.range
        apply(snapshot.stockSnapshot)
        latestOvernightBar = snapshot.feed == .overnight ? snapshot.latestBar : nil
        setChartBaseline(snapshot.chartBaseline, for: snapshot.range)
        scheduleSnapshotBarRender(
            rawBars: snapshot.bars,
            range: snapshot.range,
            feed: snapshot.feed,
            latestBar: snapshot.latestBar
        )
        if let service, previousFeed != feed || boundStreamFeed != feed {
            bindStream(service: service)
        }
        lastUpdatedAt = Date()
        refreshLatestBarSoon()
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
                let priceChanged = latestTrade?.price != trade.price || latestTrade?.timestamp != trade.timestamp
                latestTrade = trade
                if priceChanged {
                    didChangeChart = true
                }
            }

            if let incomingQuote = batch.latestQuote,
               Self.hasValidQuotePrice(incomingQuote),
               quote != incomingQuote {
                let previousMid = AssetIntradaySessionMapper.chartQuotePrice(quote)
                let nextMid = AssetIntradaySessionMapper.chartQuotePrice(incomingQuote)
                quote = incomingQuote
                if quoteAffectsChart(previousMid: previousMid, nextMid: nextMid) {
                    didChangeChart = true
                }
            }

            for bar in batch.bars {
                if isSnapshotRenderPendingForSelectedRange {
                    deferredRealtimeBars.append(bar)
                }
                if barSeries.merge(bar) {
                    didChangeChart = true
                }
            }

            if didChangeChart {
                latestCoreSessionClose = barSeries.latestClose ?? latestCoreSessionClose
                updateChartRenderModels()
            }
        } else {
            if let trade = batch.latestTrade,
               Self.hasValidMarketPrice(trade.price),
               latestTrade != trade {
                latestTrade = trade
            }

            if let incomingQuote = batch.latestQuote,
               Self.hasValidQuotePrice(incomingQuote),
               quote != incomingQuote {
                quote = incomingQuote
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

    /// Avoids triggering expensive 1D chart rebuilds when only bid/ask size flickers
    /// or when a newer trade already anchors the chart price.
    private func quoteAffectsChart(previousMid: Double?, nextMid: Double?) -> Bool {
        guard previousMid != nextMid else {
            return false
        }
        if feed == .overnight {
            return true
        }
        guard let quoteDate = parsedQuoteDate else {
            return false
        }
        if let tradeDate = parsedLatestTradeDate, tradeDate >= quoteDate {
            return false
        }
        return true
    }

    private func applyConnectionStatus(_ status: AssetRealtimeConnectionStatus) {
        if case .reconnecting = status {
            shouldResyncOnLive = true
        }

        connectionStatus = status
        if status == .live, shouldResyncOnLive {
            shouldResyncOnLive = false
            triggerSupplementalSnapshotRefresh(forced: true)
        }
    }

    private func apply(_ resolvedSnapshot: AlpacaResolvedStockSnapshot) {
        let previousFeed = feed
        feed = resolvedSnapshot.feed
        apply(resolvedSnapshot.snapshot)
        latestOvernightBar = resolvedSnapshot.feed == .overnight ? resolvedSnapshot.latestBar : nil
        var didMergeLatestBar = false

        if resolvedSnapshot.feed == .overnight {
            if selectedRange == .oneDay {
                barSeries.mergeOvernightSupplementBar(resolvedSnapshot.latestBar)
                recordLatestOvernightChartBar()
            }
        } else {
            barSeries.resetOvernightSupplementBars()
            didMergeLatestBar = mergeSupplementalLatestBar(resolvedSnapshot.latestBar)
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
            let merged = barSeries.mergeOvernightSupplementBar(bar)
            didChangeChart = merged || previousLatestBar != bar
        } else {
            didChangeChart = mergeSupplementalLatestBar(bar)
        }

        if didChangeChart {
            latestCoreSessionClose = barSeries.latestClose ?? latestCoreSessionClose
            updateChartRenderModels()
            lastUpdatedAt = Date()
        }
    }

    @discardableResult
    private func mergeSupplementalLatestBar(_ bar: AlpacaMarketBar?) -> Bool {
        guard selectedRange == .oneDay,
              let bar,
              Self.hasValidMarketPrice(bar.close) else {
            return false
        }

        if isSnapshotRenderPendingForSelectedRange {
            deferredRealtimeBars.append(bar)
        }
        let didChange = barSeries.merge(bar)
        if didChange {
            latestCoreSessionClose = barSeries.latestClose ?? latestCoreSessionClose
        }
        return didChange
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

    // MARK: - Off-Main-Thread Chart Rendering & Caching

    /// Normalizes raw snapshot bars, merges supplemental/overnight bars, maps intraday session slots,
    /// and builds chart render models completely off `@MainActor`.
    private func scheduleSnapshotBarRender(
        rawBars: [AlpacaMarketBar],
        range: AssetChartRange,
        feed snapshotFeed: AlpacaMarketDataFeed,
        latestBar: AlpacaMarketBar?
    ) {
        chartRenderRevision += 1
        let revision = chartRenderRevision
        chartRenderTask?.cancel()

        if selectedRange == range {
            isLoadingChart = true
        }
        clearPendingSnapshotRender()
        pendingSnapshotRenderRange = range

        let baseline = chartBaselines[range]
        let context = makeIntradaySessionContext(overnightEntries: [])
        let fallbackCoreClose = latestCoreSessionClose ?? dailyBar?.close

        chartRenderTask = Task { @MainActor [weak self] in
            let output = await Task.detached(priority: .userInitiated) { () -> (series: AssetDetailBarSeries, models: AssetChartRenderModels, coreClose: Double?) in
                var nextSeries = AssetDetailBarSeries.normalized(from: rawBars)
                var resolvedCoreClose = fallbackCoreClose

                if range == .oneDay {
                    resolvedCoreClose = nextSeries.latestClose ?? resolvedCoreClose
                    if snapshotFeed == .overnight {
                        nextSeries.resetOvernightSupplementBars(with: latestBar)
                        let overnightContext = AssetIntradaySessionContext(
                            symbol: context.symbol,
                            feed: context.feed,
                            sessionProgress: context.sessionProgress,
                            latestTrade: context.latestTrade,
                            quote: context.quote,
                            latestOvernightBar: context.latestOvernightBar,
                            overnightSupplementEntries: nextSeries.overnightSupplementEntries,
                            previousClose: context.previousClose,
                            dayOpen: context.dayOpen,
                            latestCoreSessionClose: resolvedCoreClose,
                            currentPrice: context.currentPrice
                        )
                        if let synthesized = AssetIntradaySessionMapper.latestOvernightChartBar(
                            referenceBar: nextSeries.latestEntry?.bar,
                            context: overnightContext
                        ) {
                            nextSeries.mergeOvernightSupplementBar(synthesized)
                        }
                    } else if let latestBar, AssetIntradaySessionMapper.hasValidMarketPrice(latestBar.close) {
                        nextSeries.merge(latestBar)
                        resolvedCoreClose = nextSeries.latestClose ?? resolvedCoreClose
                    }
                }

                let finalContext = AssetIntradaySessionContext(
                    symbol: context.symbol,
                    feed: context.feed,
                    sessionProgress: context.sessionProgress,
                    latestTrade: context.latestTrade,
                    quote: context.quote,
                    latestOvernightBar: context.latestOvernightBar,
                    overnightSupplementEntries: nextSeries.overnightSupplementEntries,
                    previousClose: context.previousClose,
                    dayOpen: context.dayOpen,
                    latestCoreSessionClose: resolvedCoreClose,
                    currentPrice: context.currentPrice
                )

                let renderInput = AssetIntradaySessionMapper.makeRenderInput(
                    fromParsedBars: nextSeries.entries,
                    range: range,
                    priceChangeBaseline: baseline,
                    context: finalContext
                )
                let models = AssetChartPreprocessor.makeRenderModels(
                    from: renderInput.bars,
                    xDomain: renderInput.xDomain,
                    priceChangeBaseline: renderInput.priceChangeBaseline,
                    mode: .line
                )
                return (nextSeries, models, resolvedCoreClose)
            }.value

            guard let self, !Task.isCancelled, revision == self.chartRenderRevision else {
                return
            }

            if self.shouldCacheChart(for: range) {
                self.chartCache[range] = AssetChartCacheEntry(
                    barSeries: output.series,
                    renderModels: output.models
                )
            } else {
                self.chartCache.removeValue(forKey: range)
            }

            let deferredBars = self.deferredRealtimeBars
            let hadDeferredUpdate = self.hasDeferredRealtimeChartUpdate
            self.clearPendingSnapshotRender()

            if self.selectedRange == range {
                self.barSeries = output.series
                if range == .oneDay, let coreClose = output.coreClose {
                    self.latestCoreSessionClose = coreClose
                }
                self.chartRenderModels = output.models
                self.isLoadingChart = false
                self.recomputeChartTradeMarkers()

                if hadDeferredUpdate, range == .oneDay {
                    // Replay realtime updates that arrived while the snapshot was rendering.
                    for bar in deferredBars {
                        self.barSeries.merge(bar)
                    }
                    if self.feed == .overnight, let latestOvernightBar = self.latestOvernightBar {
                        self.barSeries.mergeOvernightSupplementBar(latestOvernightBar)
                    }
                    self.latestCoreSessionClose = self.barSeries.latestClose ?? self.latestCoreSessionClose
                    self.updateChartRenderModels()
                }
            }
        }
    }

    private func clearPendingSnapshotRender() {
        pendingSnapshotRenderRange = nil
        deferredRealtimeBars.removeAll()
        hasDeferredRealtimeChartUpdate = false
    }

    private var isSnapshotRenderPendingForSelectedRange: Bool {
        pendingSnapshotRenderRange == selectedRange
    }

    private func updateChartRenderModels(showsLoading: Bool = false) {
        if isSnapshotRenderPendingForSelectedRange {
            // Don't cancel the in-flight snapshot render; it replays this update when it lands.
            hasDeferredRealtimeChartUpdate = true
            return
        }

        let range = selectedRange
        let currentSeries = barSeries
        let baseline = chartBaselines[range]
        let context = makeIntradaySessionContext(overnightEntries: currentSeries.overnightSupplementEntries)

        chartRenderRevision += 1
        let revision = chartRenderRevision
        chartRenderTask?.cancel()

        if showsLoading {
            isLoadingChart = true
        }

        chartRenderTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                let renderInput = AssetIntradaySessionMapper.makeRenderInput(
                    fromParsedBars: currentSeries.entries,
                    range: range,
                    priceChangeBaseline: baseline,
                    context: context
                )
                return AssetChartPreprocessor.makeRenderModels(
                    from: renderInput.bars,
                    xDomain: renderInput.xDomain,
                    priceChangeBaseline: renderInput.priceChangeBaseline,
                    mode: .line
                )
            }.value

            guard let self, !Task.isCancelled, revision == self.chartRenderRevision else {
                return
            }

            if self.shouldCacheChart(for: range) {
                self.chartCache[range] = AssetChartCacheEntry(
                    barSeries: currentSeries,
                    renderModels: result
                )
            } else {
                self.chartCache.removeValue(forKey: range)
            }

            if self.selectedRange == range {
                self.chartRenderModels = result
                self.isLoadingChart = false
                self.recomputeChartTradeMarkers()
            }
        }
    }

    @discardableResult
    private func applyCachedChart(for range: AssetChartRange) -> Bool {
        guard shouldCacheChart(for: range),
              let cached = chartCache[range] else {
            return false
        }

        chartRenderRevision += 1
        chartRenderTask?.cancel()
        clearPendingSnapshotRender()
        barSeries = cached.barSeries
        chartRenderModels = cached.renderModels
        if range == .oneDay {
            latestCoreSessionClose = barSeries.latestClose ?? latestCoreSessionClose
        }
        return true
    }

    private func shouldCacheChart(for range: AssetChartRange) -> Bool {
        !(range == .oneDay && cachedHasActiveSessionProgress)
    }

    private func makeIntradaySessionContext(
        overnightEntries: [AssetParsedMarketBar]
    ) -> AssetIntradaySessionContext {
        AssetIntradaySessionContext(
            symbol: symbol,
            feed: feed,
            sessionProgress: sessionProgress,
            latestTrade: latestTrade,
            quote: quote,
            latestOvernightBar: latestOvernightBar,
            overnightSupplementEntries: overnightEntries,
            previousClose: previousClose,
            dayOpen: dayOpen,
            latestCoreSessionClose: latestCoreSessionClose,
            currentPrice: currentPrice
        )
    }

    private func recordLatestOvernightChartBar() {
        guard feed == .overnight, selectedRange == .oneDay else {
            return
        }

        let context = makeIntradaySessionContext(overnightEntries: barSeries.overnightSupplementEntries)
        barSeries.mergeOvernightSupplementBar(
            AssetIntradaySessionMapper.latestOvernightChartBar(
                referenceBar: barSeries.latestEntry?.bar,
                context: context
            )
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
        let components = easternCalendar.dateComponents([.hour, .minute], from: date)
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

private struct AssetChartCacheEntry {
    let barSeries: AssetDetailBarSeries
    let renderModels: AssetChartRenderModels
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
