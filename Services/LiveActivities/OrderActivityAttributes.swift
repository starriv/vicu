import ActivityKit
import Foundation

struct OrderCancellationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let phase: OrderCancellationPhase
        let message: String
        let updatedAt: Date
    }

    let orderID: String
    let symbol: String
    let side: String
    let quantityText: String
    let orderType: String
}

enum OrderCancellationPhase: String, Codable, Hashable, Sendable {
    case awaitingConfirmation
    case submitting
    case submitted
    case failed
    case dismissed
}
