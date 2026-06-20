import Foundation
import Observation

@MainActor
@Observable
final class WatchlistsStore {
    var watchlists: [AlpacaWatchlist] = []
    var selectedWatchlistID: String?
    var isLoading = false
    var loadError: String?
    var mutatingWatchlistIDs = Set<String>()
    var mutatingSymbolIDs = Set<String>()

    var selectedWatchlist: AlpacaWatchlist? {
        guard let selectedWatchlistID,
              let selectedWatchlist = watchlist(id: selectedWatchlistID) else {
            return watchlists.first
        }

        return selectedWatchlist
    }

    func load(app: AppModel, forceReload: Bool = false) async {
        guard forceReload || !isLoading else {
            return
        }

        guard app.hasCredentials else {
            watchlists = []
            loadError = nil
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            watchlists = try await app.fetchWatchlists()
            reconcileSelection()
            loadError = nil
        } catch where error.isRequestCancellation {
            return
        } catch {
            loadError = APIErrorDisplayMessage.message(for: error, locale: app.appLanguage.locale)
        }
    }

    func watchlist(id: String) -> AlpacaWatchlist? {
        watchlists.first { $0.id == id }
    }

    func select(_ watchlistID: String) {
        guard watchlists.contains(where: { $0.id == watchlistID }) else {
            return
        }

        selectedWatchlistID = watchlistID
    }

    func create(name: String, symbols: [String], app: AppModel) async throws -> AlpacaWatchlist {
        let watchlist = try await app.createWatchlist(
            name: name,
            symbols: WatchlistSymbolParser.symbols(from: symbols)
        )
        upsert(watchlist)
        selectedWatchlistID = watchlist.id
        return watchlist
    }

    func update(id: String, name: String, symbols: [String], app: AppModel) async throws -> AlpacaWatchlist {
        mutatingWatchlistIDs.insert(id)
        defer { mutatingWatchlistIDs.remove(id) }

        let watchlist = try await app.updateWatchlist(
            id: id,
            name: name,
            symbols: WatchlistSymbolParser.symbols(from: symbols)
        )
        upsert(watchlist)
        return watchlist
    }

    func delete(_ watchlist: AlpacaWatchlist, app: AppModel) async throws {
        mutatingWatchlistIDs.insert(watchlist.id)
        defer { mutatingWatchlistIDs.remove(watchlist.id) }

        try await app.deleteWatchlist(watchlist)
        watchlists.removeAll { $0.id == watchlist.id }
        reconcileSelection()
    }

    func addSymbol(_ symbol: String, to watchlist: AlpacaWatchlist, app: AppModel) async throws -> AlpacaWatchlist {
        let normalizedSymbol = WatchlistSymbolParser.symbol(from: symbol)
        let mutationID = symbolMutationID(watchlistID: watchlist.id, symbol: normalizedSymbol)
        mutatingSymbolIDs.insert(mutationID)
        mutatingWatchlistIDs.insert(watchlist.id)
        defer {
            mutatingSymbolIDs.remove(mutationID)
            mutatingWatchlistIDs.remove(watchlist.id)
        }

        let updatedWatchlist = try await app.addSymbol(normalizedSymbol, to: watchlist)
        upsert(updatedWatchlist)
        return updatedWatchlist
    }

    func removeSymbol(_ symbol: String, from watchlist: AlpacaWatchlist, app: AppModel) async throws -> AlpacaWatchlist {
        let normalizedSymbol = WatchlistSymbolParser.symbol(from: symbol)
        let mutationID = symbolMutationID(watchlistID: watchlist.id, symbol: normalizedSymbol)
        mutatingSymbolIDs.insert(mutationID)
        mutatingWatchlistIDs.insert(watchlist.id)
        defer {
            mutatingSymbolIDs.remove(mutationID)
            mutatingWatchlistIDs.remove(watchlist.id)
        }

        let updatedWatchlist = try await app.removeSymbol(normalizedSymbol, from: watchlist)
        upsert(updatedWatchlist)
        return updatedWatchlist
    }

    func reorderAssetsLocally(
        in watchlist: AlpacaWatchlist,
        from source: IndexSet,
        to destination: Int
    ) -> WatchlistAssetsReorder? {
        guard !source.isEmpty else {
            return nil
        }

        let currentWatchlist = self.watchlist(id: watchlist.id) ?? watchlist
        let currentAssets = currentWatchlist.assets ?? []
        guard !currentAssets.isEmpty else {
            return nil
        }

        let reorderedAssets = Self.reordered(currentAssets, from: source, to: destination)
        let reorderedSymbols = reorderedAssets.map(\.symbol)
        guard reorderedSymbols != currentWatchlist.symbols else {
            return nil
        }

        let optimisticWatchlist = currentWatchlist.replacingAssets(reorderedAssets)

        mutatingWatchlistIDs.insert(watchlist.id)
        upsert(optimisticWatchlist)
        return WatchlistAssetsReorder(
            originalWatchlist: currentWatchlist,
            optimisticWatchlist: optimisticWatchlist,
            symbols: reorderedSymbols
        )
    }

    func persistReorderedAssets(_ reorder: WatchlistAssetsReorder, app: AppModel) async throws -> AlpacaWatchlist {
        defer { mutatingWatchlistIDs.remove(reorder.watchlistID) }

        do {
            let updatedWatchlist = try await app.updateWatchlist(
                id: reorder.watchlistID,
                name: reorder.name,
                symbols: reorder.symbols
            )
            upsert(updatedWatchlist)
            return updatedWatchlist
        } catch {
            rollback(reorder)
            throw error
        }
    }

    func isMutating(_ watchlist: AlpacaWatchlist) -> Bool {
        mutatingWatchlistIDs.contains(watchlist.id)
    }

    func isMutatingSymbol(_ symbol: String, in watchlist: AlpacaWatchlist) -> Bool {
        mutatingSymbolIDs.contains(symbolMutationID(watchlistID: watchlist.id, symbol: symbol))
    }

    private func upsert(_ watchlist: AlpacaWatchlist) {
        if let index = watchlists.firstIndex(where: { $0.id == watchlist.id }) {
            watchlists[index] = watchlist
        } else {
            watchlists.append(watchlist)
        }

        reconcileSelection()
    }

    private func symbolMutationID(watchlistID: String, symbol: String) -> String {
        "\(watchlistID):\(WatchlistSymbolParser.symbol(from: symbol))"
    }

    private func rollback(_ reorder: WatchlistAssetsReorder) {
        guard let currentWatchlist = watchlist(id: reorder.watchlistID) else {
            upsert(reorder.originalWatchlist)
            return
        }

        guard currentWatchlist.symbols == reorder.symbols else {
            return
        }

        upsert(reorder.originalWatchlist)
    }

    private func reconcileSelection() {
        guard !watchlists.isEmpty else {
            selectedWatchlistID = nil
            return
        }

        if let selectedWatchlistID,
           watchlists.contains(where: { $0.id == selectedWatchlistID }) {
            return
        }

        selectedWatchlistID = watchlists.first?.id
    }

    private static func reordered(_ assets: [AlpacaAsset], from source: IndexSet, to destination: Int) -> [AlpacaAsset] {
        let movingAssets = source.sorted().compactMap { index in
            assets.indices.contains(index) ? assets[index] : nil
        }
        guard !movingAssets.isEmpty else {
            return assets
        }

        let sourceSet = Set(source)
        var remainingAssets = assets.enumerated()
            .filter { !sourceSet.contains($0.offset) }
            .map(\.element)
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), remainingAssets.count)
        remainingAssets.insert(contentsOf: movingAssets, at: insertionIndex)
        return remainingAssets
    }
}

struct WatchlistAssetsReorder {
    let originalWatchlist: AlpacaWatchlist
    let optimisticWatchlist: AlpacaWatchlist
    let symbols: [String]

    var watchlistID: String {
        optimisticWatchlist.id
    }

    var name: String {
        optimisticWatchlist.name
    }
}

private extension AlpacaWatchlist {
    func replacingAssets(_ assets: [AlpacaAsset]) -> AlpacaWatchlist {
        AlpacaWatchlist(
            id: id,
            accountID: accountID,
            name: name,
            assets: assets,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

enum WatchlistSymbolParser {
    static func symbol(from text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func symbols(from symbols: [String]) -> [String] {
        normalized(symbols)
    }

    static func symbols(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n\t ")
        let rawSymbols = text.components(separatedBy: separators)
        return normalized(rawSymbols)
    }

    private static func normalized(_ symbols: [String]) -> [String] {
        var seenSymbols = Set<String>()
        return symbols.compactMap { rawSymbol in
            let symbol = symbol(from: rawSymbol)
            guard !symbol.isEmpty, !seenSymbols.contains(symbol) else {
                return nil
            }

            seenSymbols.insert(symbol)
            return symbol
        }
    }
}
