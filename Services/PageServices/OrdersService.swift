import Foundation

protocol OrdersServicing: Sendable {
    func fetchRecentOrders(credentials: AlpacaCredentials) async throws -> [AlpacaOrder]
    func fetchOrder(id: String, nested: Bool, credentials: AlpacaCredentials) async throws -> AlpacaOrder
    func cancelOrder(id: String, credentials: AlpacaCredentials) async throws
    func replaceOrder(id: String, request: AlpacaReplaceOrderRequest, credentials: AlpacaCredentials) async throws -> AlpacaOrder
}

struct OrdersService: OrdersServicing {
    private let alpaca: any AlpacaServicing

    init(alpaca: any AlpacaServicing) {
        self.alpaca = alpaca
    }

    func fetchRecentOrders(credentials: AlpacaCredentials) async throws -> [AlpacaOrder] {
        try await alpaca.fetchRecentOrders(credentials: credentials)
    }

    func fetchOrder(id: String, nested: Bool, credentials: AlpacaCredentials) async throws -> AlpacaOrder {
        try await alpaca.fetchOrder(id: id, nested: nested, credentials: credentials)
    }

    func cancelOrder(id: String, credentials: AlpacaCredentials) async throws {
        try await alpaca.cancelOrder(id: id, credentials: credentials)
    }

    func replaceOrder(
        id: String,
        request: AlpacaReplaceOrderRequest,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOrder {
        try await alpaca.replaceOrder(id: id, request: request, credentials: credentials)
    }
}
