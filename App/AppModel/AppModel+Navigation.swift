import Foundation

struct OrderDetailNavigationRequest: Equatable, Hashable, Identifiable, Sendable {
    let id = UUID()
    let orderID: String
    let symbol: String?

    init(orderID: String, symbol: String? = nil) {
        self.orderID = orderID.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedSymbol = symbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let normalizedSymbol, !normalizedSymbol.isEmpty {
            self.symbol = normalizedSymbol
        } else {
            self.symbol = nil
        }
    }
}

extension AppModel {
    func openOrdersList(symbol: String, reason: OrdersListRequestReason) {
        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return
        }

        pendingOrdersListRequest = OrdersListRequest(symbol: normalizedSymbol, reason: reason)
        selectedTab = .orders
    }

    func openOrderDetail(orderID: String, symbol: String? = nil) {
        let request = OrderDetailNavigationRequest(orderID: orderID, symbol: symbol)
        guard !request.orderID.isEmpty else {
            return
        }

        pendingOrderDetailRequest = request
        selectedTab = .orders
    }

    func consumeOrdersListRequest(_ request: OrdersListRequest) {
        guard pendingOrdersListRequest?.id == request.id else {
            return
        }

        pendingOrdersListRequest = nil
    }

    func consumeOrderDetailRequest(_ request: OrderDetailNavigationRequest) {
        guard pendingOrderDetailRequest?.id == request.id else {
            return
        }

        pendingOrderDetailRequest = nil
    }

    func handleNotificationRoute(_ route: AppNotificationRoute) {
        switch route {
        case .orderDetail(let orderID, let symbol):
            openOrderDetail(orderID: orderID, symbol: symbol)
        }
    }

    func isFavoriteMarketSymbol(_ symbol: String) -> Bool {
        favoriteMarketSymbols.contains(normalizedMarketSymbol(symbol))
    }

    func favoriteMarketAsset(for symbol: String) -> AlpacaAsset? {
        favoriteMarketAssetBySymbol[normalizedMarketSymbol(symbol)]
    }

    func favoriteMarketQuote(for symbol: String) -> MarketActiveSymbol? {
        favoriteMarketQuotesBySymbol[normalizedMarketSymbol(symbol)]
    }
}
