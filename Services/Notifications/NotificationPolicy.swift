import Foundation
import UserNotifications

enum NotificationPriority: Equatable, Sendable {
    case high
    case normal
    case low

    var relevanceScore: Double {
        switch self {
        case .high: 1.0
        case .normal: 0.7
        case .low: 0.4
        }
    }

    var interruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .high, .normal: .active
        case .low: .passive
        }
    }

    var playsSound: Bool {
        self != .low
    }
}

/// Pure decision rules for local notifications: what should interrupt the user,
/// what should stay quiet (handled by Live Activities), priority ranking, and
/// thread grouping. Kept free of `UNUserNotificationCenter` calls for unit testing.
enum NotificationPolicy {
    enum Category {
        static let accountActivity = "ALPACA_ACCOUNT_ACTIVITY"
        static let orderSubmitted = "ALPACA_ORDER_SUBMITTED"
        static let orderStatus = "ALPACA_TRADE_ORDER_STATUS"
    }

    enum Action {
        static let viewOrder = "VICU_VIEW_ORDER"
    }

    /// Intermediate exchange plumbing states that do not warrant a banner
    /// because Live Activities already surface live working status.
    private static let suppressedTradeEvents: Set<String> = [
        "new",
        "pending_new",
        "accepted",
        "accepted_for_bidding",
        "calculated",
        "pending_cancel",
        "pending_replace"
    ]

    static func shouldNotify(
        orderSubmitted order: AlpacaOrder,
        preferences: AppNotificationPreferences
    ) -> Bool {
        preferences.allows(.tradeOrderSubmitted)
    }

    static func shouldNotify(
        tradeEvent event: AlpacaTradeEvent,
        preferences: AppNotificationPreferences
    ) -> Bool {
        guard preferences.allows(.tradeOrderStatus) else {
            return false
        }

        return !suppressedTradeEvents.contains(event.normalizedEvent)
    }

    static func shouldNotify(
        activityEvent event: AlpacaActivityEvent,
        preferences: AppNotificationPreferences
    ) -> Bool {
        guard preferences.allows(.accountActivity) else {
            return false
        }

        // Trade fills already arrive on the trade-event stream; avoid double banners.
        if event.activityType.uppercased() == "TRD", preferences.tradeOrderStatusNotificationsEnabled {
            return false
        }

        return true
    }

    static func priority(forTradeEvent event: AlpacaTradeEvent) -> NotificationPriority {
        switch event.normalizedEvent {
        case "fill", "rejected", "order_cancel_rejected", "order_replace_rejected", "trade_bust", "trade_correct":
            .high
        case "partial_fill", "canceled", "cancelled", "expired", "replaced", "done_for_day", "stopped", "suspended":
            .normal
        default:
            .low
        }
    }

    static func priority(forActivityEvent event: AlpacaActivityEvent) -> NotificationPriority {
        switch event.activityType.uppercased() {
        case "TRD", "CSD", "CSW", "ACATC", "ACATS", "OPASN", "OPEXC":
            .normal
        default:
            .low
        }
    }

    static func orderThreadIdentifier(symbol: String) -> String {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? "vicu.orders" : "vicu.order.\(normalized)"
    }

    static let accountThreadIdentifier = "vicu.account"
}
