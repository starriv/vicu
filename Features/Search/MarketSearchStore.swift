import Foundation
import Observation

struct MarketSearchRowModel: Identifiable, Equatable, Sendable {
    let symbol: String
    let companyName: String?
    let exchange: String?
    let isETF: Bool
    let isFractionable: Bool
    let isHeld: Bool
    let isExactMatch: Bool
    let price: Double?
    let percentChange: Double?
    let priceText: String?
    let percentChangeText: String?
    let isPositive: Bool

    var id: String { symbol }

    var hasQuote: Bool {
        price != nil
    }

    nonisolated static func make(
        from record: SearchableAssetRecord,
        queryUpper: String,
        owned: Set<String>,
        quote: MarketActiveSymbol?
    ) -> MarketSearchRowModel {
        let price = quote?.price
        let percentChange = quote?.percentChange
        return MarketSearchRowModel(
            symbol: record.symbol,
            companyName: record.displayName,
            exchange: record.exchange,
            isETF: record.isETF,
            isFractionable: record.fractionable,
            isHeld: owned.contains(record.symbol),
            isExactMatch: record.symbol == queryUpper,
            price: price,
            percentChange: percentChange,
            priceText: price.map { AppFormatter.money($0) },
            percentChangeText: percentChange.map { AppFormatter.signedPercent($0) },
            isPositive: quote?.isPositive ?? true
        )
    }

    nonisolated func updatingQuote(_ quote: MarketActiveSymbol) -> MarketSearchRowModel {
        MarketSearchRowModel(
            symbol: symbol,
            companyName: companyName,
            exchange: exchange,
            isETF: isETF,
            isFractionable: isFractionable,
            isHeld: isHeld,
            isExactMatch: isExactMatch,
            price: quote.price,
            percentChange: quote.percentChange,
            priceText: quote.price.map { AppFormatter.money($0) },
            percentChangeText: quote.percentChange.map { AppFormatter.signedPercent($0) },
            isPositive: quote.isPositive
        )
    }
}

@MainActor
@Observable
final class MarketSearchStore {
    var scope: MarketSearchScope = .all
    var popularSort: MarketMostActiveSort = .trades
    var showsAllPopular = false

    var recentSymbols: [String] = []
    var popularSymbols: [MarketActiveSymbol] = []
    var results: [MarketSearchRowModel] = []
    var activeQuery: String = ""

    var isLoadingPopular = false
    var hasLoadedPopularOnce = false
    var isCatalogSyncing = false
    var isSearching = false
    var lastCatalogErrorMessage: String?
    var defaultSearchSymbol = AppModel.searchPlaceholderFallbackSymbol

    var shouldShowPopularSkeleton: Bool {
        popularSymbols.isEmpty && (isLoadingPopular || !hasLoadedPopularOnce)
    }

    var shouldShowTrendingSection: Bool {
        !popularSymbols.isEmpty || shouldShowPopularSkeleton
    }

    @ObservationIgnored private var indexWarmupTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var quoteEnrichmentTask: Task<Void, Never>?
    @ObservationIgnored private var directLookupTask: Task<Void, Never>?
    @ObservationIgnored private var popularTask: Task<Void, Never>?
    @ObservationIgnored private var activeSearchGeneration = 0
    @ObservationIgnored private var lastContextID: String?
    @ObservationIgnored private var lastAppliedIndexTimestamp: Date?

    func handleContextAppearance(contextID: String, app: AppModel) async {
        if let previousContext = lastContextID, previousContext != contextID {
            resetForContextChange()
        }
        lastContextID = contextID
        await onAppear(app: app)
    }

    func onAppear(app: AppModel) async {
        syncRecentSymbols(app: app)
        if let cachedPopular = app.cachedPopularMarketSymbols(sort: popularSort), !cachedPopular.isEmpty {
            popularSymbols = app.enrichPopularSymbolsWithCompanyNames(cachedPopular)
            defaultSearchSymbol = AppModel.searchPlaceholderSymbol(from: popularSymbols)
            hasLoadedPopularOnce = true
        }

        startCatalogWarmupIfNeeded(app: app)
        loadPopularSymbols(app: app, force: false)
        await app.refreshFavoriteMarketSymbols()
    }

    func onDisappear() {
        searchTask?.cancel()
        searchTask = nil
        quoteEnrichmentTask?.cancel()
        quoteEnrichmentTask = nil
        directLookupTask?.cancel()
        directLookupTask = nil
        popularTask?.cancel()
        popularTask = nil
        isLoadingPopular = false
        isSearching = false
    }

    func resetForContextChange() {
        indexWarmupTask?.cancel()
        indexWarmupTask = nil
        searchTask?.cancel()
        searchTask = nil
        quoteEnrichmentTask?.cancel()
        quoteEnrichmentTask = nil
        directLookupTask?.cancel()
        directLookupTask = nil
        popularTask?.cancel()
        popularTask = nil

        activeSearchGeneration += 1
        lastAppliedIndexTimestamp = nil
        scope = .all
        showsAllPopular = false
        recentSymbols = []
        popularSymbols = []
        results = []
        isLoadingPopular = false
        hasLoadedPopularOnce = false
        isCatalogSyncing = false
        isSearching = false
        lastCatalogErrorMessage = nil
        defaultSearchSymbol = AppModel.searchPlaceholderFallbackSymbol
    }

    func syncRecentSymbols(app: AppModel) {
        let latest = app.recentSearchSymbols()
        if recentSymbols != latest {
            recentSymbols = latest
        }
    }

    func refresh(app: AppModel) async {
        guard app.hasCredentials else { return }

        syncRecentSymbols(app: app)
        async let favoritesRefresh: Void = app.refreshFavoriteMarketSymbols(forceReload: true)
        async let popularRefresh: Void = refreshPopularSymbolsNow(app: app)
        async let indexRefresh: Void = refreshSearchIndexNow(app: app)
        _ = await (favoritesRefresh, popularRefresh, indexRefresh)
    }

    private func refreshSearchIndexNow(app: AppModel) async {
        if let refreshed = try? await app.ensureSearchIndex(allowStaleReturn: false), !refreshed.isEmpty {
            applyIndexIfNewer(refreshed, timestamp: app.searchIndexTimestamp(), app: app)
        }
    }

    func updateQuery(_ rawQuery: String, app: AppModel, immediate: Bool = false) {
        let normalized = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        activeQuery = normalized

        searchTask?.cancel()
        quoteEnrichmentTask?.cancel()
        directLookupTask?.cancel()

        guard !normalized.isEmpty, app.hasCredentials else {
            activeSearchGeneration += 1
            results = []
            isSearching = false
            return
        }

        activeSearchGeneration += 1
        let generation = activeSearchGeneration

        // Immediate fast-path if index is already in memory
        if let index = app.searchIndexSnapshot(), !index.isEmpty {
            executeIndexedSearch(
                query: normalized,
                scope: scope,
                index: index,
                app: app,
                generation: generation,
                immediate: immediate
            )
            return
        }

        // Cold-start path: immediately surface matches from local known universe (positions, favorites, popular)
        let fallbackRecords = app.localFallbackSearchRecords()
        if !fallbackRecords.isEmpty {
            let fallbackIndex = MarketSearchIndex(records: fallbackRecords)
            let owned = ownedSymbolSet(app: app)
            let favorites = favoriteSymbolSet(app: app)
            let quotesSnapshot = app.cachedSearchQuotesSnapshot()
            let localMatches = fallbackIndex.search(
                query: normalized,
                scope: scope,
                ownedSymbols: owned,
                favoriteSymbols: favorites,
                limit: 12
            )
            let queryUpper = normalized.uppercased()
            results = localMatches.map { record in
                MarketSearchRowModel.make(
                    from: record,
                    queryUpper: queryUpper,
                    owned: owned,
                    quote: quotesSnapshot[record.symbol]
                )
            }
        } else {
            results = []
        }

        isSearching = true
        startCatalogWarmupIfNeeded(app: app)

        // Fire a fast direct single-ticker lookup if the user typed a ticker and we don't have an exact match yet
        let normalizedUpper = normalized.uppercased()
        if MarketSearchIndex.looksLikeTicker(normalizedUpper),
           !results.contains(where: { $0.symbol == normalizedUpper }) {
            directLookupTask = Task { @MainActor [weak self] in
                guard let self else { return }
                if !immediate {
                    try? await Task.sleep(for: .milliseconds(160))
                }
                guard !Task.isCancelled, self.activeSearchGeneration == generation else { return }
                if let directRecord = await app.fetchDirectSearchAsset(symbol: normalizedUpper) {
                    guard !Task.isCancelled, self.activeSearchGeneration == generation else { return }
                    let owned = self.ownedSymbolSet(app: app)
                    let directRow = MarketSearchRowModel.make(
                        from: directRecord,
                        queryUpper: normalizedUpper,
                        owned: owned,
                        quote: app.cachedSearchQuote(forSymbol: directRecord.symbol)
                    )
                    if !self.results.contains(where: { $0.symbol == directRow.symbol }) {
                        self.results.insert(directRow, at: 0)
                        self.isSearching = false
                        self.scheduleQuoteEnrichment(
                            symbols: [directRow.symbol],
                            app: app,
                            generation: generation,
                            immediate: true
                        )
                    }
                }
            }
        }
    }

    func updateScope(_ newScope: MarketSearchScope, app: AppModel) {
        guard scope != newScope else { return }
        scope = newScope
        if !activeQuery.isEmpty {
            updateQuery(activeQuery, app: app, immediate: true)
        }
    }

    func updatePopularSort(_ newSort: MarketMostActiveSort, app: AppModel) {
        guard popularSort != newSort else { return }
        popularSort = newSort
        showsAllPopular = false
        loadPopularSymbols(app: app, force: false)
    }

    func loadPopularSymbols(app: AppModel, force: Bool) {
        popularTask?.cancel()
        let sort = popularSort

        guard app.hasCredentials else {
            popularSymbols = []
            isLoadingPopular = false
            hasLoadedPopularOnce = true
            return
        }

        if !force, let cached = app.cachedPopularMarketSymbols(sort: sort), !cached.isEmpty {
            popularSymbols = app.enrichPopularSymbolsWithCompanyNames(cached)
            defaultSearchSymbol = AppModel.searchPlaceholderSymbol(from: popularSymbols)
            hasLoadedPopularOnce = true
        }

        isLoadingPopular = popularSymbols.isEmpty
        popularTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.popularSort == sort {
                    self.isLoadingPopular = false
                }
            }
            do {
                let symbols = try await app.fetchSearchPopularMarketSymbols(limit: 12, sort: sort)
                guard !Task.isCancelled, self.popularSort == sort else { return }
                self.popularSymbols = app.enrichPopularSymbolsWithCompanyNames(symbols)
                self.defaultSearchSymbol = AppModel.searchPlaceholderSymbol(from: self.popularSymbols)
                self.hasLoadedPopularOnce = true
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled, self.popularSort == sort else { return }
                self.hasLoadedPopularOnce = true
            }
        }
    }

    func consumeCatalogErrorMessage() -> String? {
        defer { lastCatalogErrorMessage = nil }
        return lastCatalogErrorMessage
    }

    func recordRecentSelection(_ symbol: String, app: AppModel) {
        app.recordRecentSearchSymbol(symbol)
        recentSymbols = app.recentSearchSymbols()
    }

    func removeRecentSymbol(_ symbol: String, app: AppModel) {
        app.removeRecentSearchSymbol(symbol)
        recentSymbols = app.recentSearchSymbols()
    }

    func clearRecentSymbols(app: AppModel) {
        app.clearRecentSearchSymbols()
        recentSymbols = []
    }

    var displayedPopularSymbols: [MarketActiveSymbol] {
        if showsAllPopular || popularSymbols.count <= 6 {
            return popularSymbols
        }
        return Array(popularSymbols.prefix(6))
    }

    var canExpandPopularSymbols: Bool {
        !showsAllPopular && popularSymbols.count > 6
    }

    // MARK: - Private

    private func refreshPopularSymbolsNow(app: AppModel) async {
        let sort = popularSort
        if popularSymbols.isEmpty {
            isLoadingPopular = true
        }
        defer {
            if popularSort == sort {
                isLoadingPopular = false
            }
        }
        do {
            let symbols = try await app.fetchSearchPopularMarketSymbols(limit: 12, sort: sort)
            guard !Task.isCancelled, popularSort == sort else { return }
            popularSymbols = app.enrichPopularSymbolsWithCompanyNames(symbols)
            defaultSearchSymbol = AppModel.searchPlaceholderSymbol(from: popularSymbols)
            hasLoadedPopularOnce = true
        } catch where error.isRequestCancellation {
            return
        } catch {
            hasLoadedPopularOnce = true
        }
    }

    private func startCatalogWarmupIfNeeded(app: AppModel) {
        guard app.hasCredentials else { return }
        guard indexWarmupTask == nil else { return }

        if app.searchIndexSnapshot() == nil {
            isCatalogSyncing = true
        }

        indexWarmupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isCatalogSyncing = false
                self.indexWarmupTask = nil
                if app.searchIndexSnapshot() == nil {
                    self.isSearching = false
                }
            }

            if app.searchIndexSnapshot() == nil {
                await app.hydrateSearchIndexFromDisk()
            }

            if let diskIndex = app.searchIndexSnapshot(), !diskIndex.isEmpty {
                self.isCatalogSyncing = false
                self.applyIndexIfNewer(diskIndex, timestamp: app.searchIndexTimestamp(), app: app)
            }

            do {
                let resolved = try await app.ensureSearchIndex(allowStaleReturn: true)
                guard !Task.isCancelled else { return }
                if !resolved.isEmpty {
                    self.applyIndexIfNewer(resolved, timestamp: app.searchIndexTimestamp(), app: app)
                } else {
                    self.isSearching = false
                }
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if app.searchIndexSnapshot() == nil {
                    self.isSearching = false
                    if !self.activeQuery.isEmpty {
                        self.lastCatalogErrorMessage = APIErrorDisplayMessage.message(
                            for: error,
                            locale: app.appLanguage.locale
                        )
                    }
                }
            }
        }
    }

    private func applyIndexIfNewer(
        _ index: MarketSearchIndex,
        timestamp: Date?,
        app: AppModel
    ) {
        if let timestamp, let lastApplied = lastAppliedIndexTimestamp, timestamp <= lastApplied {
            return
        }
        lastAppliedIndexTimestamp = timestamp ?? Date()

        if !popularSymbols.isEmpty {
            popularSymbols = app.enrichPopularSymbolsWithCompanyNames(popularSymbols)
        }

        if !activeQuery.isEmpty {
            let generation = activeSearchGeneration
            executeIndexedSearch(
                query: activeQuery,
                scope: scope,
                index: index,
                app: app,
                generation: generation,
                immediate: true
            )
        }
    }

    private func executeIndexedSearch(
        query: String,
        scope: MarketSearchScope,
        index: MarketSearchIndex,
        app: AppModel,
        generation: Int,
        immediate: Bool
    ) {
        let owned = ownedSymbolSet(app: app)
        let favorites = favoriteSymbolSet(app: app)
        let quotesSnapshot = app.cachedSearchQuotesSnapshot()
        let queryUpper = query.uppercased()

        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(for: .milliseconds(55))
                guard !Task.isCancelled, self.activeSearchGeneration == generation else {
                    return
                }
            }

            let rows = await Task.detached(priority: .userInitiated) {
                let matchedRecords = index.search(
                    query: query,
                    scope: scope,
                    ownedSymbols: owned,
                    favoriteSymbols: favorites,
                    limit: 16
                )
                return matchedRecords.map { record in
                    MarketSearchRowModel.make(
                        from: record,
                        queryUpper: queryUpper,
                        owned: owned,
                        quote: quotesSnapshot[record.symbol]
                    )
                }
            }.value

            guard !Task.isCancelled, self.activeSearchGeneration == generation else {
                return
            }

            if self.results != rows {
                self.results = rows
            }
            self.isSearching = false

            let symbolsToEnrich = Array(rows.prefix(8).map(\.symbol))
            if !symbolsToEnrich.isEmpty {
                self.scheduleQuoteEnrichment(
                    symbols: symbolsToEnrich,
                    app: app,
                    generation: generation,
                    immediate: immediate
                )
            }
        }
    }

    private func scheduleQuoteEnrichment(
        symbols: [String],
        app: AppModel,
        generation: Int,
        immediate: Bool
    ) {
        quoteEnrichmentTask?.cancel()
        quoteEnrichmentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(for: .milliseconds(220))
            }
            guard !Task.isCancelled, self.activeSearchGeneration == generation else {
                return
            }

            let quotes = await app.fetchSearchQuotes(forSymbols: symbols)
            guard !Task.isCancelled, self.activeSearchGeneration == generation, !quotes.isEmpty else {
                return
            }

            var updated = self.results
            var didChange = false
            for idx in updated.indices {
                let row = updated[idx]
                guard let quote = quotes[row.symbol], quote.price != nil else {
                    continue
                }
                if row.price != quote.price || row.percentChange != quote.percentChange {
                    updated[idx] = row.updatingQuote(quote)
                    didChange = true
                }
            }
            if didChange {
                self.results = updated
            }
        }
    }

    private func ownedSymbolSet(app: AppModel) -> Set<String> {
        Set(app.portfolio.positions.map { $0.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
    }

    private func favoriteSymbolSet(app: AppModel) -> Set<String> {
        Set(app.favoriteMarketSymbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
    }
}
