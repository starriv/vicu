import Foundation

protocol PortfolioServicing: Sendable {
    func fetchAccount(credentials: AlpacaCredentials) async throws -> AlpacaAccount
    func fetchPositions(credentials: AlpacaCredentials) async throws -> [AlpacaPosition]
    func fetchOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaPosition?
    func closeOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaOrder
    func fetchPortfolioHistory(
        range: PortfolioHistoryRange,
        accountCreatedAt: String?,
        credentials: AlpacaCredentials
    ) async throws -> [PortfolioHistoryPoint]
}

struct PortfolioService: PortfolioServicing {
    private let alpaca: any AlpacaServicing

    init(alpaca: any AlpacaServicing) {
        self.alpaca = alpaca
    }

    func fetchAccount(credentials: AlpacaCredentials) async throws -> AlpacaAccount {
        try await alpaca.fetchAccount(credentials: credentials)
    }

    func fetchPositions(credentials: AlpacaCredentials) async throws -> [AlpacaPosition] {
        try await alpaca.fetchPositions(credentials: credentials)
    }

    func fetchOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaPosition? {
        try await alpaca.fetchOpenPosition(symbolOrAssetID: symbolOrAssetID, credentials: credentials)
    }

    func closeOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaOrder {
        try await alpaca.closeOpenPosition(symbolOrAssetID: symbolOrAssetID, credentials: credentials)
    }

    func fetchPortfolioHistory(
        range: PortfolioHistoryRange,
        accountCreatedAt: String?,
        credentials: AlpacaCredentials
    ) async throws -> [PortfolioHistoryPoint] {
        try await alpaca.fetchPortfolioHistory(
            range: range,
            accountCreatedAt: accountCreatedAt,
            credentials: credentials
        )
    }
}
