import Foundation

struct OrdersListRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let symbol: String
    let reason: OrdersListRequestReason

    init(symbol: String, reason: OrdersListRequestReason) {
        id = UUID()
        self.symbol = symbol
        self.reason = reason
    }

    var criteria: OrdersFilterCriteria {
        OrdersFilterCriteria(
            timeRange: .all,
            symbols: [symbol]
        )
    }
}

enum OrdersListRequestReason: String, Sendable {
    case assetDetail
}
