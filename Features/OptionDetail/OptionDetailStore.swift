import Foundation
import Observation
import RxSwift

@MainActor
@Observable
final class OptionDetailStore {
    let contractSymbol: String
    let descriptor: OptionContractDescriptor

    var selectedRange: AssetChartRange = .oneDay
    var chartMode: AssetChartMode = .line
    private(set) var snapshotModel: OptionDetailSnapshotModel
    private(set) var chartRenderModels: AssetChartRenderModels = .empty
    private(set) var tradeRows: [OptionTradeRowModel] = []
    private(set) var nextTradePageToken: String?
    private(set) var isLoadingSnapshot = false
    private(set) var isLoadingChart = false
    private(set) var isLoadingTrades = false
    private(set) var isLoadingMoreTrades = false
    private(set) var snapshotErrorMessage: String?
    private(set) var chartErrorMessage: String?
    private(set) var tradesErrorMessage: String?
    private(set) var tradeLoadMoreErrorMessage: String?
    private(set) var lastUpdatedAt: Date?

    @ObservationIgnored private var snapshot: AlpacaOptionSnapshot?
    @ObservationIgnored private var latestTrade: AlpacaOptionTrade?
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var snapshotDisposeBag = DisposeBag()
    @ObservationIgnored private var chartDisposeBag = DisposeBag()
    @ObservationIgnored private var tradeDisposeBag = DisposeBag()
    @ObservationIgnored private var tradeLoadMoreDisposeBag = DisposeBag()
    @ObservationIgnored private let snapshotRefreshRequests = PublishSubject<Bool>()
    @ObservationIgnored private let chartRequests = PublishSubject<OptionDetailChartRequest>()
    @ObservationIgnored private let tradeRequests = PublishSubject<OptionDetailTradesRequest>()
    @ObservationIgnored private let tradeLoadMoreRequests = PublishSubject<OptionDetailTradesRequest>()
    @ObservationIgnored private var activeChartRequest: OptionDetailChartRequest?
    @ObservationIgnored private var activeTradeRequest: OptionDetailTradesRequest?
    @ObservationIgnored private var chartRenderTask: Task<Void, Never>?
    @ObservationIgnored private var chartRenderRevision = 0
    @ObservationIgnored private var chartCache: [OptionDetailChartCacheKey: OptionDetailChartCacheEntry] = [:]
    @ObservationIgnored private var tradeIDs = Set<String>()

    init(contractSymbol: String, initialSnapshot: AlpacaOptionSnapshot? = nil) {
        let normalizedSymbol = contractSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.contractSymbol = normalizedSymbol
        descriptor = OptionContractDescriptor(symbol: normalizedSymbol)
        snapshot = initialSnapshot
        snapshotModel = OptionDetailSnapshotModel(
            descriptor: descriptor,
            snapshot: initialSnapshot
        )
    }

    var canLoadMoreTrades: Bool {
        nextTradePageToken != nil && tradeLoadMoreErrorMessage == nil
    }

    var tradesLoadMoreTrigger: OptionTradesLoadMoreTrigger {
        OptionTradesLoadMoreTrigger(
            range: selectedRange,
            pageToken: nextTradePageToken,
            count: tradeRows.count
        )
    }

    var effectiveChartMode: AssetChartMode {
        selectedRange == .oneDay ? .line : chartMode
    }

    var hasInitialContent: Bool {
        snapshot != nil || !chartRenderModels.line.points.isEmpty || !tradeRows.isEmpty
    }

    func start(app: AppModel) {
        guard !isStarted else {
            return
        }

        self.app = app
        isStarted = true
        bindSnapshotPipeline(app: app)
        bindChartPipeline(app: app)
        bindTradePipeline(app: app)
        bindTradeLoadMorePipeline(app: app)
        reloadAll(forceReload: false)
    }

    func stop() {
        snapshotDisposeBag = DisposeBag()
        chartDisposeBag = DisposeBag()
        tradeDisposeBag = DisposeBag()
        tradeLoadMoreDisposeBag = DisposeBag()
        chartRenderTask?.cancel()
        chartRenderTask = nil
        chartRenderRevision += 1
        activeChartRequest = nil
        activeTradeRequest = nil
        isStarted = false
        isLoadingSnapshot = false
        isLoadingChart = false
        isLoadingTrades = false
        isLoadingMoreTrades = false
    }

    func reloadAll(forceReload: Bool = true) {
        snapshotRefreshRequests.onNext(forceReload)
        reloadChart(forceReload: forceReload)
        reloadTrades(forceReload: forceReload)
    }

    func selectRange(_ range: AssetChartRange) {
        guard selectedRange != range else {
            return
        }

        selectedRange = range
        if applyCachedChart(for: range, mode: effectiveChartMode) {
            chartErrorMessage = nil
            isLoadingChart = false
        } else {
            reloadChart(forceReload: false)
        }
        reloadTrades(forceReload: false)
    }

    func selectChartMode(_ mode: AssetChartMode) {
        guard chartMode != mode else {
            return
        }

        chartMode = mode
        guard selectedRange != .oneDay else {
            return
        }

        if applyCachedChart(for: selectedRange, mode: effectiveChartMode) {
            chartErrorMessage = nil
            isLoadingChart = false
        } else if let cachedBars = chartCache[OptionDetailChartCacheKey(range: selectedRange, mode: .line)]?.bars {
            scheduleChartRender(
                bars: cachedBars,
                range: selectedRange,
                mode: effectiveChartMode,
                showsLoading: true
            )
        } else {
            reloadChart(forceReload: false)
        }
    }

    func selectedPriceChange(for selection: AssetChartSelection) -> AssetPeriodPriceChange {
        AssetPeriodPriceChange(
            current: selection.point.close,
            baseline: chartRenderModels.model(for: effectiveChartMode).priceChangeBaseline ?? selection.baseline
        )
    }

    func loadMoreTradesIfNeeded(force: Bool = false) {
        guard let nextTradePageToken else {
            return
        }

        if tradeLoadMoreErrorMessage != nil, !force {
            return
        }

        tradeLoadMoreRequests.onNext(
            OptionDetailTradesRequest(
                symbol: contractSymbol,
                range: selectedRange,
                pageToken: nextTradePageToken,
                forceReload: force
            )
        )
    }

    private func reloadChart(forceReload: Bool) {
        chartRequests.onNext(
            OptionDetailChartRequest(
                symbol: contractSymbol,
                range: selectedRange,
                forceReload: forceReload
            )
        )
    }

    private func reloadTrades(forceReload: Bool) {
        tradeRequests.onNext(
            OptionDetailTradesRequest(
                symbol: contractSymbol,
                range: selectedRange,
                pageToken: nil,
                forceReload: forceReload
            )
        )
    }

    private func bindSnapshotPipeline(app: AppModel) {
        snapshotDisposeBag = DisposeBag()

        let scheduledRefreshes = Observable<Int>
            .interval(.seconds(30), scheduler: MainScheduler.instance)
            .map { _ in false }

        Observable
            .merge(scheduledRefreshes, snapshotRefreshRequests)
            .do(onNext: { [weak self] forceReload in
                self?.beginSnapshotLoad(forceReload: forceReload)
            })
            .flatMapLatest { [weak app, contractSymbol] forceReload -> Observable<OptionDetailSnapshotLoadResult> in
                guard let app else {
                    return .empty()
                }

                return optionDetailSnapshotLoad(app: app, symbol: contractSymbol, forceReload: forceReload)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.applySnapshotResult(result)
            })
            .disposed(by: snapshotDisposeBag)
    }

    private func bindChartPipeline(app: AppModel) {
        chartDisposeBag = DisposeBag()

        chartRequests
            .observe(on: MainScheduler.instance)
            .distinctUntilChanged { lhs, rhs in
                lhs == rhs && !lhs.forceReload && !rhs.forceReload
            }
            .do(onNext: { [weak self] request in
                self?.beginChartLoad(request)
            })
            .debounce(.milliseconds(60), scheduler: MainScheduler.instance)
            .flatMapLatest { [weak app] request -> Observable<OptionDetailChartLoadResult> in
                guard let app else {
                    return .empty()
                }

                return optionDetailChartLoad(app: app, request: request)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.applyChartResult(result)
            })
            .disposed(by: chartDisposeBag)
    }

    private func bindTradePipeline(app: AppModel) {
        tradeDisposeBag = DisposeBag()

        tradeRequests
            .observe(on: MainScheduler.instance)
            .do(onNext: { [weak self] request in
                self?.beginTradeReset(request)
            })
            .debounce(.milliseconds(60), scheduler: MainScheduler.instance)
            .flatMapLatest { [weak app] request -> Observable<OptionDetailTradesLoadResult> in
                guard let app else {
                    return .empty()
                }

                return optionDetailTradesLoad(app: app, request: request)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.applyTradesResult(result)
            })
            .disposed(by: tradeDisposeBag)
    }

    private func bindTradeLoadMorePipeline(app: AppModel) {
        tradeLoadMoreDisposeBag = DisposeBag()

        tradeLoadMoreRequests
            .observe(on: MainScheduler.instance)
            .filter { $0.pageToken != nil }
            .do(onNext: { [weak self] _ in
                self?.beginTradeLoadMore()
            })
            .flatMapFirst { [weak app] request -> Observable<OptionDetailTradesLoadResult> in
                guard let app else {
                    return .empty()
                }

                return optionDetailTradesLoad(app: app, request: request)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.applyTradesResult(result)
            })
            .disposed(by: tradeLoadMoreDisposeBag)
    }

    private func beginSnapshotLoad(forceReload: Bool) {
        isLoadingSnapshot = true
        if forceReload {
            snapshotErrorMessage = nil
        }
    }

    private func beginChartLoad(_ request: OptionDetailChartRequest) {
        activeChartRequest = request
        isLoadingChart = true
        chartErrorMessage = nil
    }

    private func beginTradeReset(_ request: OptionDetailTradesRequest) {
        activeTradeRequest = request
        tradeRows = []
        tradeIDs = []
        nextTradePageToken = nil
        isLoadingTrades = true
        isLoadingMoreTrades = false
        tradesErrorMessage = nil
        tradeLoadMoreErrorMessage = nil
    }

    private func beginTradeLoadMore() {
        guard !isLoadingTrades, !isLoadingMoreTrades else {
            return
        }

        isLoadingMoreTrades = true
        tradeLoadMoreErrorMessage = nil
    }

    private func applySnapshotResult(_ result: OptionDetailSnapshotLoadResult) {
        isLoadingSnapshot = false

        switch result {
        case .success(let loadedSnapshot, let loadedLatestTrade):
            snapshot = loadedSnapshot ?? snapshot
            latestTrade = loadedLatestTrade ?? latestTrade
            snapshotModel = OptionDetailSnapshotModel(
                descriptor: descriptor,
                snapshot: snapshot,
                fallbackTrade: latestTrade
            )
            snapshotErrorMessage = nil
            lastUpdatedAt = Date()
        case .failure(let error):
            snapshotErrorMessage = error.localizedDescription
        }
    }

    private func applyChartResult(_ result: OptionDetailChartLoadResult) {
        switch result {
        case .success(let request, let page):
            guard request == activeChartRequest else {
                return
            }

            activeChartRequest = nil
            scheduleChartRender(
                bars: page.bars,
                range: request.range,
                mode: request.range == .oneDay ? .line : effectiveChartMode,
                showsLoading: false
            )
            chartErrorMessage = nil
        case .failure(let request, let error):
            guard request == activeChartRequest else {
                return
            }

            activeChartRequest = nil
            chartErrorMessage = error.localizedDescription
            isLoadingChart = false
        }
    }

    private func applyTradesResult(_ result: OptionDetailTradesLoadResult) {
        switch result {
        case .success(let request, let page):
            guard isCurrentTradesRequest(request) else {
                return
            }

            let newRows = page.trades.enumerated().map { index, trade in
                OptionTradeRowModel(trade: trade, offset: tradeRows.count + index)
            }
            nextTradePageToken = page.nextPageToken
            tradesErrorMessage = nil
            tradeLoadMoreErrorMessage = nil

            if request.isReset {
                tradeRows = newRows
                tradeIDs = Set(newRows.map(\.id))
                activeTradeRequest = nil
                isLoadingTrades = false
            } else {
                appendUniqueTrades(newRows)
                isLoadingMoreTrades = false
            }
        case .failure(let request, let error):
            guard isCurrentTradesRequest(request) else {
                return
            }

            if request.isReset {
                tradeRows = []
                tradeIDs = []
                nextTradePageToken = nil
                tradesErrorMessage = error.localizedDescription
                activeTradeRequest = nil
                isLoadingTrades = false
            } else {
                tradeLoadMoreErrorMessage = error.localizedDescription
                isLoadingMoreTrades = false
            }
        }
    }

    private func isCurrentTradesRequest(_ request: OptionDetailTradesRequest) -> Bool {
        guard request.symbol == contractSymbol,
              request.range == selectedRange else {
            return false
        }

        if request.isReset {
            return activeTradeRequest == nil || activeTradeRequest == request
        }

        return true
    }

    private func appendUniqueTrades(_ rows: [OptionTradeRowModel]) {
        var uniqueRows: [OptionTradeRowModel] = []
        for row in rows where !tradeIDs.contains(row.id) {
            uniqueRows.append(row)
            tradeIDs.insert(row.id)
        }

        tradeRows.append(contentsOf: uniqueRows)
    }

    @discardableResult
    private func applyCachedChart(for range: AssetChartRange, mode: AssetChartMode) -> Bool {
        let cacheKey = OptionDetailChartCacheKey(range: range, mode: mode)
        guard let cached = chartCache[cacheKey] else {
            return false
        }

        chartRenderRevision += 1
        chartRenderTask?.cancel()
        chartRenderModels = cached.renderModels
        return true
    }

    private func scheduleChartRender(
        bars: [AlpacaMarketBar],
        range: AssetChartRange,
        mode: AssetChartMode,
        showsLoading: Bool
    ) {
        chartRenderRevision += 1
        let revision = chartRenderRevision
        chartRenderTask?.cancel()
        if showsLoading {
            isLoadingChart = true
        }

        chartRenderTask = Task { [weak self, bars] in
            let inputBars = bars.enumerated().map { offset, bar in
                AssetChartInputBar(bar: bar, xPosition: Double(offset))
            }
            let renderModels = await Task.detached(priority: .userInitiated) {
                AssetChartPreprocessor.makeRenderModels(
                    from: inputBars,
                    xDomain: nil,
                    priceChangeBaseline: nil,
                    mode: mode
                )
            }.value

            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard revision == self.chartRenderRevision else { return }

            let cacheKey = OptionDetailChartCacheKey(range: range, mode: mode)
            self.chartCache[cacheKey] = OptionDetailChartCacheEntry(
                bars: bars,
                renderModels: renderModels
            )

            if self.selectedRange == range, self.effectiveChartMode == mode {
                self.chartRenderModels = renderModels
                self.isLoadingChart = false
            }
        }
    }
}

private struct OptionDetailChartCacheKey: Hashable {
    let range: AssetChartRange
    let mode: AssetChartMode
}

private struct OptionDetailChartCacheEntry {
    let bars: [AlpacaMarketBar]
    let renderModels: AssetChartRenderModels
}

private struct OptionDetailChartRequest: Equatable {
    let symbol: String
    let range: AssetChartRange
    let forceReload: Bool
}

private struct OptionDetailTradesRequest: Equatable {
    let symbol: String
    let range: AssetChartRange
    let pageToken: String?
    let forceReload: Bool

    var isReset: Bool {
        pageToken == nil
    }
}

private enum OptionDetailSnapshotLoadResult {
    case success(AlpacaOptionSnapshot?, AlpacaOptionTrade?)
    case failure(Error)
}

private enum OptionDetailChartLoadResult {
    case success(OptionDetailChartRequest, AlpacaOptionBarsPage)
    case failure(OptionDetailChartRequest, Error)
}

private enum OptionDetailTradesLoadResult {
    case success(OptionDetailTradesRequest, AlpacaOptionTradesPage)
    case failure(OptionDetailTradesRequest, Error)
}

private final class OptionDetailSnapshotLoadObserverBox: @unchecked Sendable {
    private let observer: AnyObserver<OptionDetailSnapshotLoadResult>

    init(_ observer: AnyObserver<OptionDetailSnapshotLoadResult>) {
        self.observer = observer
    }

    @MainActor
    func onNext(_ result: OptionDetailSnapshotLoadResult) {
        observer.onNext(result)
    }
}

private final class OptionDetailChartLoadObserverBox: @unchecked Sendable {
    private let observer: AnyObserver<OptionDetailChartLoadResult>

    init(_ observer: AnyObserver<OptionDetailChartLoadResult>) {
        self.observer = observer
    }

    @MainActor
    func onNext(_ result: OptionDetailChartLoadResult) {
        observer.onNext(result)
    }
}

private final class OptionDetailTradesLoadObserverBox: @unchecked Sendable {
    private let observer: AnyObserver<OptionDetailTradesLoadResult>

    init(_ observer: AnyObserver<OptionDetailTradesLoadResult>) {
        self.observer = observer
    }

    @MainActor
    func onNext(_ result: OptionDetailTradesLoadResult) {
        observer.onNext(result)
    }
}

private func optionDetailSnapshotLoad(
    app: AppModel,
    symbol: String,
    forceReload: Bool
) -> Observable<OptionDetailSnapshotLoadResult> {
    Observable.create { observer in
        let observerBox = OptionDetailSnapshotLoadObserverBox(observer)
        let task = Task { @MainActor [app, symbol, forceReload, observerBox] in
            do {
                async let snapshotRequest = app.fetchOptionSnapshot(
                    symbol: symbol,
                    forceReload: forceReload
                )
                async let latestTradeRequest = app.fetchLatestOptionTrade(
                    symbol: symbol,
                    forceReload: forceReload
                )
                let result = try await (snapshotRequest, latestTradeRequest)
                try Task.checkCancellation()
                observerBox.onNext(.success(result.0, result.1))
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                observerBox.onNext(.failure(error))
            }
        }

        return Disposables.create {
            task.cancel()
        }
    }
}

private func optionDetailChartLoad(
    app: AppModel,
    request: OptionDetailChartRequest
) -> Observable<OptionDetailChartLoadResult> {
    Observable.create { observer in
        let observerBox = OptionDetailChartLoadObserverBox(observer)
        let task = Task { @MainActor [app, request, observerBox] in
            do {
                let page = try await app.fetchOptionBars(
                    symbol: request.symbol,
                    range: request.range,
                    forceReload: request.forceReload
                )
                try Task.checkCancellation()
                observerBox.onNext(.success(request, page))
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                observerBox.onNext(.failure(request, error))
            }
        }

        return Disposables.create {
            task.cancel()
        }
    }
}

private func optionDetailTradesLoad(
    app: AppModel,
    request: OptionDetailTradesRequest
) -> Observable<OptionDetailTradesLoadResult> {
    Observable.create { observer in
        let observerBox = OptionDetailTradesLoadObserverBox(observer)
        let task = Task { @MainActor [app, request, observerBox] in
            do {
                let page = try await app.fetchOptionTrades(
                    symbol: request.symbol,
                    range: request.range,
                    pageToken: request.pageToken,
                    forceReload: request.forceReload
                )
                try Task.checkCancellation()
                observerBox.onNext(.success(request, page))
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                observerBox.onNext(.failure(request, error))
            }
        }

        return Disposables.create {
            task.cancel()
        }
    }
}
