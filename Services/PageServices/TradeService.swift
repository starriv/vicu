import Foundation

protocol TradeServicing: Sendable {
    func fetchAccount(credentials: AlpacaCredentials) async throws -> AlpacaAccount
    func fetchAsset(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaAsset
    func fetchOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaPosition?
    func fetchCurrentStockSnapshot(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaResolvedStockSnapshot
    func submitOrder(_ draft: OrderDraft, clientOrderID: String?, credentials: AlpacaCredentials) async throws -> AlpacaOrder
}

struct TradeService: TradeServicing {
    private let alpaca: any AlpacaServicing

    init(alpaca: any AlpacaServicing) {
        self.alpaca = alpaca
    }

    func fetchAccount(credentials: AlpacaCredentials) async throws -> AlpacaAccount {
        try await alpaca.fetchAccount(credentials: credentials)
    }

    func fetchAsset(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaAsset {
        try await alpaca.fetchAsset(symbolOrAssetID: symbolOrAssetID, credentials: credentials)
    }

    func fetchOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaPosition? {
        try await alpaca.fetchOpenPosition(symbolOrAssetID: symbolOrAssetID, credentials: credentials)
    }

    func fetchCurrentStockSnapshot(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaResolvedStockSnapshot {
        try await alpaca.fetchCurrentStockSnapshot(symbol: symbol, feed: feed, credentials: credentials)
    }

    func submitOrder(
        _ draft: OrderDraft,
        clientOrderID: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOrder {
        try await alpaca.submitOrder(draft, clientOrderID: clientOrderID, credentials: credentials)
    }
}
