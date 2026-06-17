import Foundation

extension AppModel {
    func openOrdersList(symbol: String, reason: OrdersListRequestReason) {
        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return
        }

        pendingOrdersListRequest = OrdersListRequest(symbol: normalizedSymbol, reason: reason)
        selectedTab = .orders
    }

    func consumeOrdersListRequest(_ request: OrdersListRequest) {
        guard pendingOrdersListRequest?.id == request.id else {
            return
        }

        pendingOrdersListRequest = nil
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
