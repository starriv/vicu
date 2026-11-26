import Foundation

/// Timing and selection rules for Vicu's Live Activities. Everything here is a pure
/// function so the decisions can be unit tested without ActivityKit or a device.
enum LiveActivityPolicy {
    /// How long a finished order keeps its card before the system may drop it.
    static let terminalLinger: TimeInterval = 15 * 60
    /// A working card turns stale quickly: the app cannot refresh it in the background,
    /// so the card must admit that the numbers are a snapshot.
    static let workingStaleInterval: TimeInterval = 5 * 60
    /// Keep the session card for a few minutes after the last session of the day closes.
    static let sessionLinger: TimeInterval = 5 * 60

    // MARK: - Order phase

    static func phase(forStatus status: String?) -> OrderActivityPhase {
        switch normalized(status) {
        case "new", "pending_new", "calculated", nil:
            .submitted
        case "accepted", "accepted_for_bidding", "held", "stopped", "suspended", "pending_replace":
            .working
        case "partially_filled":
            .partiallyFilled
        case "pending_cancel":
            .cancelRequested
        case "filled":
            .filled
        case "canceled":
            .canceled
        case "expired", "done_for_day":
            .expired
        case "replaced":
            .replaced
        case "rejected", "failed":
            .rejected
        default:
            .working
        }
    }

    static func isTerminal(_ order: AlpacaOrder) -> Bool {
        phase(forStatus: order.status).isTerminal
    }

    // MARK: - Timestamps

    /// Most recent moment something happened to the order, used both for "as of" text
    /// and for choosing the representative card.
    static func lastActivityDate(for order: AlpacaOrder) -> Date {
        [
            order.updatedAt,
            order.filledAt,
            order.canceledAt,
            order.failedAt,
            order.expiredAt,
            order.replacedAt,
            order.submittedAt,
            order.createdAt
        ]
        .compactMap { AlpacaDateParser.date($0) }
        .max() ?? Date()
    }

    static func staleDate(for phase: OrderActivityPhase, now: Date = Date()) -> Date {
        phase.isTerminal
            ? now.addingTimeInterval(terminalLinger)
            : now.addingTimeInterval(workingStaleInterval)
    }

    /// Absolute date at which the card may disappear on its own.
    static func dismissalDate(for phase: OrderActivityPhase, now: Date = Date()) -> Date? {
        guard phase.isTerminal else {
            return nil
        }

        return now.addingTimeInterval(terminalLinger)
    }

    // MARK: - Representative order

    /// One card at a time: the order that changed most recently among the working ones,
    /// falling back to an order that just finished so the outcome is still visible.
    static func representativeOrder(in orders: [AlpacaOrder], now: Date = Date()) -> AlpacaOrder? {
        let working = orders.filter { !isTerminal($0) }
        if let newestWorking = working.max(by: { lastActivityDate(for: $0) < lastActivityDate(for: $1) }) {
            return newestWorking
        }

        let cutoff = now.addingTimeInterval(-terminalLinger)
        return orders
            .filter { isTerminal($0) && lastActivityDate(for: $0) >= cutoff }
            .max(by: { lastActivityDate(for: $0) < lastActivityDate(for: $1) })
    }

    static func workingOrderCount(in orders: [AlpacaOrder]) -> Int {
        orders.filter { !isTerminal($0) }.count
    }

    // MARK: - Fill progress

    static func fillProgress(for order: AlpacaOrder) -> Double {
        guard let total = totalUnits(for: order), total > 0,
              let filled = filledUnits(for: order) else {
            return 0
        }

        return max(0, min(1, filled / total))
    }

    static func filledUnits(for order: AlpacaOrder) -> Double? {
        NumberParser.double(from: order.filledQuantity)
    }

    static func totalUnits(for order: AlpacaOrder) -> Double? {
        if let quantity = NumberParser.double(from: order.quantity) {
            return quantity
        }
        return nil
    }

    private static func normalized(_ status: String?) -> String? {
        let value = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return value.isEmpty ? nil : value
    }
}
