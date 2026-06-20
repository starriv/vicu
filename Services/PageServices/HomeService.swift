import Foundation

protocol HomeServicing: Sendable {
    func fetchAccount(credentials: AlpacaCredentials) async throws -> AlpacaAccount
    func fetchAccountActivities(pageSize: Int, pageToken: String?, credentials: AlpacaCredentials) async throws -> AlpacaAccountActivitiesPage
}

struct HomeService: HomeServicing {
    private let alpaca: any AlpacaServicing

    init(alpaca: any AlpacaServicing) {
        self.alpaca = alpaca
    }

    func fetchAccount(credentials: AlpacaCredentials) async throws -> AlpacaAccount {
        try await alpaca.fetchAccount(credentials: credentials)
    }

    func fetchAccountActivities(
        pageSize: Int,
        pageToken: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaAccountActivitiesPage {
        try await alpaca.fetchAccountActivities(pageSize: pageSize, pageToken: pageToken, credentials: credentials)
    }
}
