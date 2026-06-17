import Foundation

struct PortfolioState: Sendable {
    var account: AlpacaAccount?
    var positions: [AlpacaPosition] = []
    var orders: [AlpacaOrder] = []
    var historyRange: PortfolioHistoryRange = .oneDay
    var history: [PortfolioHistoryPoint] = []
    var isRefreshing = false
    var isLoadingHistory = false

    mutating func applySnapshot(
        account: AlpacaAccount,
        positions: [AlpacaPosition],
        orders: [AlpacaOrder],
        history: [PortfolioHistoryPoint]
    ) {
        self.account = account
        self.positions = positions
        self.orders = orders
        self.history = history
    }

    mutating func clear() {
        isRefreshing = false
        isLoadingHistory = false
        account = nil
        positions = []
        orders = []
        history = []
    }
}
