import ActivityKit
import Foundation

// MARK: - Shared models
//
// These types are compiled into both the app and the VicuLiveActivities extension:
// ActivityKit requires the widget target to know the exact attribute and content
// state types.
//
// Design rule: the attribute/content payload is purely presentational. Every
// user-visible string is produced by the app (the only place that knows the user's
// chosen app language) and carried inside `ContentState`. The widget renders what
// it is given and never formats or translates text itself.

/// Order side, reduced to what the card needs for tint and label casing.
enum OrderActivitySide: String, Codable, Hashable, Sendable {
    case buy
    case sell
    case other

    init(rawSide: String?) {
        switch rawSide?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "buy":
            self = .buy
        case "sell":
            self = .sell
        default:
            self = .other
        }
    }
}

/// Coarse order lifecycle. Alpaca's raw `status` values are mapped once, in
/// `LiveActivityPolicy`, so terminal-state checks cannot drift apart.
enum OrderActivityPhase: String, Codable, Hashable, Sendable {
    case submitted
    case working
    case partiallyFilled
    case cancelRequested
    case filled
    case canceled
    case rejected
    case expired
    case replaced

    var isTerminal: Bool {
        switch self {
        case .filled, .canceled, .rejected, .expired, .replaced:
            true
        case .submitted, .working, .partiallyFilled, .cancelRequested:
            false
        }
    }
}

struct OrderActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: OrderActivityPhase
        var statusTitle: String
        var detailLine: String
        var fillProgress: Double
        var fillRatioText: String
        var asOfText: String
        var actionTitle: String?
        var additionalOrdersText: String?
        var allowsCancellation: Bool
    }

    let orderID: String
    let symbol: String
    let side: OrderActivitySide
    let sideLabel: String
    let orderTypeLabel: String
}

struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var phaseTitle: String
        var phaseSymbol: String
        var countdownLabel: String
        var sessionStart: Date
        var transitionAt: Date
        var cycleStart: Date
        var cycleEnd: Date
        var segments: [SessionActivitySegment]
        var summaryText: String?
        var summaryIsNegative: Bool
        var trailingText: String?
    }

    let marketName: String
}

/// One proportional slice of the trading-day rail. `weight` is the segment
/// duration in seconds so the widget can lay the rail out without recomputing
/// market hours.
struct SessionActivitySegment: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let weight: Double
    let isActive: Bool
}
