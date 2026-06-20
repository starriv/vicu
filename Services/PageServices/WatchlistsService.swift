import Foundation

protocol WatchlistsServicing: Sendable {
    func fetchWatchlists(credentials: AlpacaCredentials) async throws -> [AlpacaWatchlist]
    func fetchWatchlist(id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func createWatchlist(name: String, symbols: [String], credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func updateWatchlist(id: String, name: String, symbols: [String], credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func deleteWatchlist(id: String, credentials: AlpacaCredentials) async throws
    func addSymbol(_ symbol: String, toWatchlist id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func removeSymbol(_ symbol: String, fromWatchlist id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func fetchAssets(assetClass: String?, credentials: AlpacaCredentials) async throws -> [AlpacaAsset]
}

struct WatchlistsService: WatchlistsServicing {
    private let alpaca: any AlpacaServicing

    init(alpaca: any AlpacaServicing) {
        self.alpaca = alpaca
    }

    func fetchWatchlists(credentials: AlpacaCredentials) async throws -> [AlpacaWatchlist] {
        try await alpaca.fetchWatchlists(credentials: credentials)
    }

    func fetchWatchlist(id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist {
        try await alpaca.fetchWatchlist(id: id, credentials: credentials)
    }

    func createWatchlist(
        name: String,
        symbols: [String],
        credentials: AlpacaCredentials
    ) async throws -> AlpacaWatchlist {
        try await alpaca.createWatchlist(name: name, symbols: symbols, credentials: credentials)
    }

    func updateWatchlist(
        id: String,
        name: String,
        symbols: [String],
        credentials: AlpacaCredentials
    ) async throws -> AlpacaWatchlist {
        try await alpaca.updateWatchlist(id: id, name: name, symbols: symbols, credentials: credentials)
    }

    func deleteWatchlist(id: String, credentials: AlpacaCredentials) async throws {
        try await alpaca.deleteWatchlist(id: id, credentials: credentials)
    }

    func addSymbol(
        _ symbol: String,
        toWatchlist id: String,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaWatchlist {
        try await alpaca.addSymbol(symbol, toWatchlist: id, credentials: credentials)
    }

    func removeSymbol(
        _ symbol: String,
        fromWatchlist id: String,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaWatchlist {
        try await alpaca.removeSymbol(symbol, fromWatchlist: id, credentials: credentials)
    }

    func fetchAssets(assetClass: String?, credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        try await alpaca.fetchAssets(assetClass: assetClass, credentials: credentials)
    }
}
