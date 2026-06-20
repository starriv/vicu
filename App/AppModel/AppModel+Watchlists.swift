import Foundation

extension AppModel {
    func fetchWatchlists() async throws -> [AlpacaWatchlist] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let summaries = try await services.watchlists.fetchWatchlists(credentials: credentials)
        guard !summaries.isEmpty else {
            return []
        }

        let watchlists = services.watchlists
        return try await withThrowingTaskGroup(of: (Int, AlpacaWatchlist).self) { group in
            for (index, summary) in summaries.enumerated() {
                group.addTask {
                    let detail = try await watchlists.fetchWatchlist(id: summary.id, credentials: credentials)
                    return (index, detail)
                }
            }

            var detailedWatchlists = Array<AlpacaWatchlist?>(repeating: nil, count: summaries.count)
            for try await (index, watchlist) in group {
                detailedWatchlists[index] = watchlist
            }

            return detailedWatchlists.compactMap(\.self)
        }
    }

    func createWatchlist(name: String, symbols: [String]) async throws -> AlpacaWatchlist {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else {
            throw APIClientError.underlying(L10n.Watchlists.nameRequired(locale: appLanguage.locale))
        }

        let watchlist = try await services.watchlists.createWatchlist(
            name: resolvedName,
            symbols: symbols,
            credentials: credentials
        )
        synchronizeFavoritesWatchlistAfterUpsert(watchlist)
        return watchlist
    }

    func updateWatchlist(id: String, name: String, symbols: [String]) async throws -> AlpacaWatchlist {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else {
            throw APIClientError.underlying(L10n.Watchlists.nameRequired(locale: appLanguage.locale))
        }

        let watchlist = try await services.watchlists.updateWatchlist(
            id: id,
            name: resolvedName,
            symbols: symbols,
            credentials: credentials
        )
        synchronizeFavoritesWatchlistAfterUpsert(watchlist)
        return watchlist
    }

    func deleteWatchlist(_ watchlist: AlpacaWatchlist) async throws {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        try await services.watchlists.deleteWatchlist(id: watchlist.id, credentials: credentials)
        if isFavoritesWatchlist(watchlist) {
            resetFavoriteMarketSymbols()
        }
    }

    func addSymbol(_ symbol: String, to watchlist: AlpacaWatchlist) async throws -> AlpacaWatchlist {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = Self.normalizedWatchlistSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            throw APIClientError.underlying(L10n.Watchlists.invalidSymbol(locale: appLanguage.locale))
        }

        let updatedWatchlist = try await services.watchlists.addSymbol(
            normalizedSymbol,
            toWatchlist: watchlist.id,
            credentials: credentials
        )
        synchronizeFavoritesWatchlistAfterUpsert(updatedWatchlist)
        return updatedWatchlist
    }

    func removeSymbol(_ symbol: String, from watchlist: AlpacaWatchlist) async throws -> AlpacaWatchlist {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = Self.normalizedWatchlistSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            throw APIClientError.underlying(L10n.Watchlists.invalidSymbol(locale: appLanguage.locale))
        }

        let updatedWatchlist = try await services.watchlists.removeSymbol(
            normalizedSymbol,
            fromWatchlist: watchlist.id,
            credentials: credentials
        )
        synchronizeFavoritesWatchlistAfterUpsert(updatedWatchlist)
        return updatedWatchlist
    }

    func searchWatchlistAssets(query: String, limit: Int = 16) async throws -> [AlpacaAsset] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let assets = try await watchlistAssets(credentials: credentials)
        return await Task.detached(priority: .userInitiated) {
            Self.rankMarketAssets(assets, query: normalizedQuery, limit: limit)
        }.value
    }

    private func synchronizeFavoritesWatchlistAfterUpsert(_ watchlist: AlpacaWatchlist) {
        let wasFavorites = favoritesWatchlist?.id == watchlist.id
        let isFavoritesName = watchlist.name.caseInsensitiveCompare(Self.favoritesWatchlistName) == .orderedSame
        guard wasFavorites || isFavoritesName else {
            return
        }

        guard isFavoritesName else {
            resetFavoriteMarketSymbols()
            return
        }

        favoritesWatchlist = watchlist
        favoriteMarketSymbols = Self.normalizedWatchlistSymbols(watchlist.symbols)
        favoriteMarketAssetBySymbol = (watchlist.assets ?? []).reduce(into: [:]) { assetsBySymbol, asset in
            let normalizedSymbol = Self.normalizedWatchlistSymbol(asset.symbol)
            guard !normalizedSymbol.isEmpty else {
                return
            }

            assetsBySymbol[normalizedSymbol] = asset
        }

        let validSymbols = Set(favoriteMarketSymbols)
        favoriteMarketQuotesBySymbol = favoriteMarketQuotesBySymbol.filter { symbol, _ in
            validSymbols.contains(symbol)
        }
    }

    private func isFavoritesWatchlist(_ watchlist: AlpacaWatchlist) -> Bool {
        favoritesWatchlist?.id == watchlist.id
            || watchlist.name.caseInsensitiveCompare(Self.favoritesWatchlistName) == .orderedSame
    }

    private func watchlistAssets(credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        if let watchlistAssetCache,
           let watchlistAssetCacheDate,
           Date().timeIntervalSince(watchlistAssetCacheDate) < watchlistAssetCacheTTL {
            return watchlistAssetCache
        }

        let fetchedAssets = try await services.watchlists.fetchAssets(assetClass: nil, credentials: credentials)
        let assets = fetchedAssets.filter { asset in
            !asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && asset.status?.lowercased() == "active"
        }

        watchlistAssetCache = assets
        watchlistAssetCacheDate = Date()
        return assets
    }

    private static func normalizedWatchlistSymbols(_ symbols: [String]) -> [String] {
        var seenSymbols = Set<String>()
        return symbols.compactMap { symbol in
            let normalizedSymbol = normalizedWatchlistSymbol(symbol)
            guard !normalizedSymbol.isEmpty, !seenSymbols.contains(normalizedSymbol) else {
                return nil
            }

            seenSymbols.insert(normalizedSymbol)
            return normalizedSymbol
        }
    }

    private static func normalizedWatchlistSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
