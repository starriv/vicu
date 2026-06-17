import Foundation

enum AssetRealtimeConnectionStatus: Equatable, Sendable {
    case connecting
    case authenticating
    case subscribing
    case live
    case reconnecting(String)
    case disconnected
    case failed(String)

    var title: String {
        switch self {
        case .connecting:
            "Connecting"
        case .authenticating:
            "Authenticating"
        case .subscribing:
            "Subscribing"
        case .live:
            "Live"
        case .reconnecting:
            "Reconnecting"
        case .disconnected:
            "Offline"
        case .failed:
            "Unavailable"
        }
    }
}

enum AssetRealtimeEvent: Sendable {
    case connection(AssetRealtimeConnectionStatus)
    case trade(AlpacaRealtimeTrade)
    case quote(AlpacaRealtimeQuote)
    case minuteBar(AlpacaRealtimeBar)
    case updatedBar(AlpacaRealtimeBar)
    case dailyBar(AlpacaRealtimeBar)
    case status(AlpacaRealtimeTradingStatus)
}

enum AlpacaRealtimeChannel: String, CaseIterable, Hashable, Sendable {
    case trades
    case quotes
    case bars
    case updatedBars
    case dailyBars
    case statuses

    static let assetDetail: Set<AlpacaRealtimeChannel> = [
        .trades,
        .quotes,
        .bars,
        .updatedBars,
        .dailyBars,
        .statuses
    ]

    static let quoteOnly: Set<AlpacaRealtimeChannel> = [.quotes]
    static let tradeQuote: Set<AlpacaRealtimeChannel> = [.trades, .quotes]
}

struct AlpacaRealtimeTrade: Sendable, Equatable {
    let symbol: String
    let price: Double?
    let size: Double?
    let exchange: String?
    let timestamp: String?
    let conditions: [String]?
    let tape: String?
}

struct AlpacaRealtimeQuote: Sendable, Equatable {
    let symbol: String
    let askExchange: String?
    let askPrice: Double?
    let askSize: Double?
    let bidExchange: String?
    let bidPrice: Double?
    let bidSize: Double?
    let conditions: [String]?
    let timestamp: String?
    let tape: String?

    var spread: Double? {
        guard let askPrice, let bidPrice else {
            return nil
        }

        return max(0, askPrice - bidPrice)
    }
}

struct AlpacaRealtimeBar: Sendable, Equatable {
    let symbol: String
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double?
    let volume: Double?
    let vwap: Double?
    let tradeCount: Double?
    let timestamp: String?

    var marketBar: AlpacaMarketBar {
        AlpacaMarketBar(
            symbol: symbol,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            vwap: vwap,
            tradeCount: tradeCount,
            timestamp: timestamp
        )
    }
}

struct AlpacaRealtimeTradingStatus: Sendable, Equatable {
    let symbol: String
    let statusCode: String?
    let statusMessage: String?
    let reasonCode: String?
    let reasonMessage: String?
    let timestamp: String?
    let tape: String?
}

struct AlpacaRealtimeSubscription: Sendable, Equatable {
    let trades: [String]
    let quotes: [String]
    let bars: [String]
    let updatedBars: [String]
    let dailyBars: [String]
    let statuses: [String]
}
