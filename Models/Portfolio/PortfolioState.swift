struct PortfolioState: Sendable {
    var account: AlpacaAccount?
    var positions: [AlpacaPosition] = []
    var orders: [AlpacaOrder] = []
    var historyRange: PortfolioHistoryRange = .oneDay
    var history: [PortfolioHistoryPoint] = []
    var isRefreshing = false
    var isLoadingHistory = false
    var hasLoadedAccount = false
    var hasLoadedPositions = false
    var hasLoadedOrders = false
    var hasLoadedHistory = false

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
        hasLoadedAccount = true
        hasLoadedPositions = true
        hasLoadedOrders = true
        hasLoadedHistory = true
    }

    mutating func applyAccount(_ account: AlpacaAccount) {
        self.account = account
        hasLoadedAccount = true
    }

    mutating func applyPositions(_ positions: [AlpacaPosition]) {
        self.positions = positions
        hasLoadedPositions = true
    }

    mutating func applyOrders(_ orders: [AlpacaOrder]) {
        self.orders = orders
        hasLoadedOrders = true
    }

    mutating func applyHistory(_ history: [PortfolioHistoryPoint]) {
        self.history = history
        hasLoadedHistory = true
    }

    mutating func prepareForRefresh() {
        isRefreshing = true
        if history.isEmpty {
            isLoadingHistory = true
        }
    }

    mutating func clear() {
        isRefreshing = false
        isLoadingHistory = false
        account = nil
        positions = []
        orders = []
        history = []
        hasLoadedAccount = false
        hasLoadedPositions = false
        hasLoadedOrders = false
        hasLoadedHistory = false
    }
}
