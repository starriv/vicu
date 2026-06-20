import Foundation

protocol CredentialConnectionServicing: Sendable {
    func testConnection(credentials: AlpacaCredentials) async throws
}

struct CredentialConnectionService: CredentialConnectionServicing {
    private let alpaca: any AlpacaServicing

    init(alpaca: any AlpacaServicing) {
        self.alpaca = alpaca
    }

    func testConnection(credentials: AlpacaCredentials) async throws {
        try await alpaca.testConnection(credentials: credentials)
    }
}
