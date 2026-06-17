import Foundation
import Observation
import RxSwift

@MainActor
@Observable
final class AssetOptionsStore {
    let symbol: String
    let displayName: String

    var selectedFilter: AssetOptionTypeFilter = .all
    var selectedExpiration: AssetOptionExpirationFilter = .all
    private(set) var expirationOptions: [AssetOptionExpiration] = []
    private(set) var quickExpirationOptions: [AssetOptionExpiration] = []
    private(set) var expirationMenuGroups: [AssetOptionExpirationGroup] = []
    private(set) var isLoadingExpirations = false
    private(set) var expirationErrorMessage: String?
    private(set) var rows: [AssetOptionRowModel] = []
    private(set) var nextPageToken: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var loadMoreErrorMessage: String?

    @ObservationIgnored private let chainRequests = PublishSubject<AssetOptionsChainRequest>()
    @ObservationIgnored private let loadMoreRequests = PublishSubject<AssetOptionsChainRequest>()
    @ObservationIgnored private let expirationRequests = PublishSubject<AssetOptionsExpirationRequest>()
    @ObservationIgnored private var chainDisposeBag = DisposeBag()
    @ObservationIgnored private var loadMoreDisposeBag = DisposeBag()
    @ObservationIgnored private var expirationDisposeBag = DisposeBag()
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var rowIDs = Set<String>()
    @ObservationIgnored private var activeResetRequestKey: AssetOptionsRequestKey?

    init(symbol: String, displayName: String) {
        self.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.displayName = displayName
        rebuildExpirationDerivedState()
    }

    var shouldShowMoreExpirations: Bool {
        expirationOptions.count > quickExpirationOptions.count
    }

    var canLoadMore: Bool {
        nextPageToken != nil && loadMoreErrorMessage == nil
    }

    var loadMoreTrigger: AssetOptionsLoadMoreTrigger {
        AssetOptionsLoadMoreTrigger(
            filter: selectedFilter,
            expiration: selectedExpiration,
            pageToken: nextPageToken,
            count: rows.count
        )
    }

    func start(app: AppModel) {
        guard !isStarted else {
            return
        }

        isStarted = true
        self.app = app
        bindExpirationPipeline(app: app)
        bindChainPipeline(app: app)
        bindLoadMorePipeline(app: app)
        refreshAll(forceReload: false)
    }

    func stop() {
        chainDisposeBag = DisposeBag()
        loadMoreDisposeBag = DisposeBag()
        expirationDisposeBag = DisposeBag()
        isStarted = false
        app = nil
        activeResetRequestKey = nil
        isLoading = false
        isLoadingMore = false
        isLoadingExpirations = false
    }

    func selectFilter(_ filter: AssetOptionTypeFilter) {
        guard selectedFilter != filter else {
            return
        }

        selectedFilter = filter
        reloadOptions()
    }

    func selectExpiration(_ expiration: AssetOptionExpirationFilter) {
        guard selectedExpiration != expiration else {
            return
        }

        selectedExpiration = expiration
        rebuildExpirationDerivedState()
        reloadOptions()
    }

    func refreshAll(forceReload: Bool = true) {
        refreshExpirations(forceReload: forceReload)
        reloadOptions(forceReload: forceReload)
    }

    func reloadOptions(forceReload: Bool = false) {
        chainRequests.onNext(
            AssetOptionsChainRequest(
                symbol: symbol,
                filter: selectedFilter,
                expiration: selectedExpiration,
                pageToken: nil,
                forceReload: forceReload
            )
        )
    }

    func refreshExpirations(forceReload: Bool = true) {
        expirationRequests.onNext(
            AssetOptionsExpirationRequest(
                symbol: symbol,
                forceReload: forceReload
            )
        )
    }

    func loadMoreIfNeeded(force: Bool = false) {
        guard let nextPageToken else {
            return
        }

        if loadMoreErrorMessage != nil, !force {
            return
        }

        loadMoreRequests.onNext(
            AssetOptionsChainRequest(
                symbol: symbol,
                filter: selectedFilter,
                expiration: selectedExpiration,
                pageToken: nextPageToken,
                forceReload: force
            )
        )
    }

    private func bindExpirationPipeline(app: AppModel) {
        expirationDisposeBag = DisposeBag()

        expirationRequests
            .observe(on: MainScheduler.instance)
            .distinctUntilChanged { lhs, rhs in
                lhs.symbol == rhs.symbol
                    && !lhs.forceReload
                    && !rhs.forceReload
            }
            .do(onNext: { [weak self] _ in
                self?.beginExpirationLoad()
            })
            .flatMapLatest { request in
                assetOptionsExpirationLoad(app: app, request: request)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.applyExpirationResult(result)
            })
            .disposed(by: expirationDisposeBag)
    }

    private func bindChainPipeline(app: AppModel) {
        chainDisposeBag = DisposeBag()

        chainRequests
            .observe(on: MainScheduler.instance)
            .distinctUntilChanged { lhs, rhs in
                lhs.requestKey == rhs.requestKey
                    && !lhs.forceReload
                    && !rhs.forceReload
            }
            .do(onNext: { [weak self] request in
                self?.beginResetLoad(request)
            })
            .debounce(.milliseconds(60), scheduler: MainScheduler.instance)
            .flatMapLatest { request in
                assetOptionsChainLoad(app: app, request: request)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.applyChainResult(result)
            })
            .disposed(by: chainDisposeBag)
    }

    private func bindLoadMorePipeline(app: AppModel) {
        loadMoreDisposeBag = DisposeBag()

        loadMoreRequests
            .observe(on: MainScheduler.instance)
            .filter { $0.pageToken != nil }
            .do(onNext: { [weak self] _ in
                self?.beginLoadMore()
            })
            .flatMapFirst { request in
                assetOptionsChainLoad(app: app, request: request)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] result in
                self?.applyChainResult(result)
            })
            .disposed(by: loadMoreDisposeBag)
    }

    private func beginExpirationLoad() {
        isLoadingExpirations = true
        expirationErrorMessage = nil
    }

    private func beginResetLoad(_ request: AssetOptionsChainRequest) {
        activeResetRequestKey = request.requestKey
        rows = []
        rowIDs = []
        nextPageToken = nil
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        loadMoreErrorMessage = nil
    }

    private func beginLoadMore() {
        guard !isLoading, !isLoadingMore else {
            return
        }

        isLoadingMore = true
        loadMoreErrorMessage = nil
    }

    private func applyExpirationResult(_ result: AssetOptionsExpirationLoadResult) {
        isLoadingExpirations = false

        switch result {
        case .success(let request, let expirations):
            guard request.symbol == symbol else {
                return
            }

            expirationErrorMessage = nil
            setExpirationOptions(expirations.compactMap(AssetOptionExpiration.init(apiDate:)))
        case .failure(let request, _):
            guard request.symbol == symbol else {
                return
            }

            expirationErrorMessage = "Expirations unavailable"
        }
    }

    private func applyChainResult(_ result: AssetOptionsChainLoadResult) {
        switch result {
        case .success(let request, let page):
            guard isCurrentRequest(request) else {
                return
            }

            let pageRows = page.snapshots.map(AssetOptionRowModel.init(snapshot:))
            mergeExpirationOptions(from: pageRows)
            nextPageToken = page.nextPageToken
            errorMessage = nil
            loadMoreErrorMessage = nil

            if request.isReset {
                rows = Self.sortedRows(pageRows)
                rowIDs = Set(rows.map(\.id))
                activeResetRequestKey = nil
                isLoading = false
            } else {
                appendUnique(pageRows)
                isLoadingMore = false
            }
        case .failure(let request, let error):
            guard isCurrentRequest(request) else {
                return
            }

            if request.isReset {
                rows = []
                rowIDs = []
                nextPageToken = nil
                errorMessage = displayErrorMessage(for: error)
                activeResetRequestKey = nil
                isLoading = false
            } else {
                loadMoreErrorMessage = displayErrorMessage(for: error)
                isLoadingMore = false
            }
        }
    }

    private func displayErrorMessage(for error: Error) -> String {
        APIErrorDisplayMessage.message(for: error, locale: app?.appLanguage.locale ?? AppLocale.current)
    }

    private func isCurrentRequest(_ request: AssetOptionsChainRequest) -> Bool {
        guard request.symbol == symbol,
              request.filter == selectedFilter,
              request.expiration == selectedExpiration else {
            return false
        }

        if request.isReset {
            return activeResetRequestKey == nil || activeResetRequestKey == request.requestKey
        }

        return true
    }

    private func setExpirationOptions(_ expirations: [AssetOptionExpiration]) {
        var optionsByID = Dictionary(uniqueKeysWithValues: expirationOptions.map { ($0.id, $0) })
        for expiration in expirations {
            optionsByID[expiration.id] = expiration
        }

        expirationOptions = Self.sortedExpirations(Array(optionsByID.values))
        rebuildExpirationDerivedState()
    }

    private func mergeExpirationOptions(from rows: [AssetOptionRowModel]) {
        let expirations = rows.compactMap(\.expiration)
        guard !expirations.isEmpty else {
            return
        }

        setExpirationOptions(expirations)
    }

    private func rebuildExpirationDerivedState() {
        let selectedExactExpiration: AssetOptionExpiration?
        if case .exact(let expiration) = selectedExpiration {
            selectedExactExpiration = expiration
        } else {
            selectedExactExpiration = nil
        }

        var quickOptions: [AssetOptionExpiration] = []
        if let selectedExactExpiration {
            quickOptions.append(selectedExactExpiration)
        }

        for expiration in expirationOptions where expiration != selectedExactExpiration {
            guard quickOptions.count < Self.quickExpirationLimit else {
                break
            }

            quickOptions.append(expiration)
        }

        quickExpirationOptions = quickOptions

        let groupedOptions = Dictionary(grouping: expirationOptions, by: \.year)
        expirationMenuGroups = groupedOptions.keys.sorted().map { year in
            AssetOptionExpirationGroup(
                year: year,
                expirations: groupedOptions[year] ?? []
            )
        }
    }

    private func appendUnique(_ newRows: [AssetOptionRowModel]) {
        let uniqueRows = newRows.filter { rowIDs.insert($0.id).inserted }
        guard !uniqueRows.isEmpty else {
            return
        }

        rows = Self.mergeSortedRows(rows, Self.sortedRows(uniqueRows))
    }

    private static func sortedExpirations(_ expirations: [AssetOptionExpiration]) -> [AssetOptionExpiration] {
        expirations.sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey {
                return lhs.sortKey < rhs.sortKey
            }

            return lhs.id < rhs.id
        }
    }

    private static func sortedRows(_ rows: [AssetOptionRowModel]) -> [AssetOptionRowModel] {
        rows.sorted(by: rowSortsBefore)
    }

    private static func mergeSortedRows(_ existingRows: [AssetOptionRowModel], _ newRows: [AssetOptionRowModel]) -> [AssetOptionRowModel] {
        var mergedRows: [AssetOptionRowModel] = []
        mergedRows.reserveCapacity(existingRows.count + newRows.count)

        var existingIndex = 0
        var newIndex = 0

        while existingIndex < existingRows.count && newIndex < newRows.count {
            let existingRow = existingRows[existingIndex]
            let newRow = newRows[newIndex]

            if rowSortsBefore(newRow, existingRow) {
                mergedRows.append(newRow)
                newIndex += 1
            } else {
                mergedRows.append(existingRow)
                existingIndex += 1
            }
        }

        if existingIndex < existingRows.count {
            mergedRows.append(contentsOf: existingRows[existingIndex...])
        }

        if newIndex < newRows.count {
            mergedRows.append(contentsOf: newRows[newIndex...])
        }

        return mergedRows
    }

    private static func rowSortsBefore(_ lhs: AssetOptionRowModel, _ rhs: AssetOptionRowModel) -> Bool {
        if lhs.expirationSortKey != rhs.expirationSortKey {
            return lhs.expirationSortKey < rhs.expirationSortKey
        }

        if lhs.strikeSortKey != rhs.strikeSortKey {
            return lhs.strikeSortKey < rhs.strikeSortKey
        }

        if lhs.typeSortKey != rhs.typeSortKey {
            return lhs.typeSortKey < rhs.typeSortKey
        }

        return lhs.contractSymbol < rhs.contractSymbol
    }

    private static let quickExpirationLimit = 6
}

private struct AssetOptionsRequestKey: Equatable {
    let filter: AssetOptionTypeFilter
    let expiration: AssetOptionExpirationFilter
}

private struct AssetOptionsChainRequest: Equatable {
    let symbol: String
    let filter: AssetOptionTypeFilter
    let expiration: AssetOptionExpirationFilter
    let pageToken: String?
    let forceReload: Bool

    var isReset: Bool { pageToken == nil }
    var requestKey: AssetOptionsRequestKey {
        AssetOptionsRequestKey(filter: filter, expiration: expiration)
    }
}

private struct AssetOptionsExpirationRequest: Equatable {
    let symbol: String
    let forceReload: Bool
}

private enum AssetOptionsChainLoadResult {
    case success(AssetOptionsChainRequest, AlpacaOptionChainPage)
    case failure(AssetOptionsChainRequest, Error)
}

private enum AssetOptionsExpirationLoadResult {
    case success(AssetOptionsExpirationRequest, [String])
    case failure(AssetOptionsExpirationRequest, Error)
}

private final class AssetOptionsChainLoadObserverBox: @unchecked Sendable {
    private let observer: AnyObserver<AssetOptionsChainLoadResult>

    init(_ observer: AnyObserver<AssetOptionsChainLoadResult>) {
        self.observer = observer
    }

    @MainActor
    func onNext(_ result: AssetOptionsChainLoadResult) {
        observer.onNext(result)
    }
}

private final class AssetOptionsExpirationLoadObserverBox: @unchecked Sendable {
    private let observer: AnyObserver<AssetOptionsExpirationLoadResult>

    init(_ observer: AnyObserver<AssetOptionsExpirationLoadResult>) {
        self.observer = observer
    }

    @MainActor
    func onNext(_ result: AssetOptionsExpirationLoadResult) {
        observer.onNext(result)
    }
}

private func assetOptionsChainLoad(
    app: AppModel,
    request: AssetOptionsChainRequest
) -> Observable<AssetOptionsChainLoadResult> {
    Observable.create { observer in
        let observerBox = AssetOptionsChainLoadObserverBox(observer)
        let task = Task { @MainActor [app, request, observerBox] in
            do {
                let page = try await app.fetchAssetOptionChain(
                    symbol: request.symbol,
                    type: request.filter.contractType,
                    expirationDate: request.expiration.apiValue,
                    limit: AssetOptionsStore.pageSize,
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

private func assetOptionsExpirationLoad(
    app: AppModel,
    request: AssetOptionsExpirationRequest
) -> Observable<AssetOptionsExpirationLoadResult> {
    Observable.create { observer in
        let observerBox = AssetOptionsExpirationLoadObserverBox(observer)
        let task = Task { @MainActor [app, request, observerBox] in
            do {
                let expirations = try await app.fetchAssetOptionExpirations(
                    symbol: request.symbol,
                    forceReload: request.forceReload
                )
                try Task.checkCancellation()
                observerBox.onNext(.success(request, expirations))
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

private extension AssetOptionsStore {
    static let pageSize = 250
}
