import Foundation
import RxSwift

struct AssetRealtimeBatch: Sendable {
    var connectionStatus: AssetRealtimeConnectionStatus?
    var latestTrade: AlpacaRealtimeTrade?
    var latestQuote: AlpacaRealtimeQuote?
    var dailyBar: AlpacaRealtimeBar?
    var tradingStatus: AlpacaRealtimeTradingStatus?
    var bars: [AlpacaMarketBar] = []

    var hasMarketData: Bool {
        latestTrade != nil
            || latestQuote != nil
            || dailyBar != nil
            || tradingStatus != nil
            || !bars.isEmpty
    }

    init?(events: [AssetRealtimeEvent], symbol: String) {
        guard !events.isEmpty else {
            return nil
        }

        let normalizedSymbol = symbol.uppercased()
        var barsByTimestamp: [String: AlpacaMarketBar] = [:]
        var orderedTimestamps: [String] = []
        var untimedBars: [AlpacaMarketBar] = []

        for event in events {
            switch event {
            case .connection(let status):
                connectionStatus = status
            case .trade(let trade):
                guard trade.symbol == normalizedSymbol else { continue }
                latestTrade = trade
            case .quote(let quote):
                guard quote.symbol == normalizedSymbol else { continue }
                latestQuote = quote
            case .minuteBar(let bar), .updatedBar(let bar):
                guard bar.symbol == normalizedSymbol else { continue }
                if let timestamp = bar.marketBar.timestamp {
                    if barsByTimestamp[timestamp] == nil {
                        orderedTimestamps.append(timestamp)
                    }
                    barsByTimestamp[timestamp] = bar.marketBar
                } else {
                    untimedBars.append(bar.marketBar)
                }
            case .dailyBar(let bar):
                guard bar.symbol == normalizedSymbol else { continue }
                dailyBar = bar
            case .status(let status):
                guard status.symbol == normalizedSymbol else { continue }
                tradingStatus = status
            }
        }

        var resolvedBars: [AlpacaMarketBar] = []
        resolvedBars.reserveCapacity(orderedTimestamps.count + untimedBars.count)
        for timestamp in orderedTimestamps {
            if let bar = barsByTimestamp[timestamp] {
                resolvedBars.append(bar)
            }
        }
        resolvedBars.append(contentsOf: untimedBars)
        bars = resolvedBars

        if connectionStatus == nil, !hasMarketData {
            return nil
        }
    }
}

func assetRealtimeBatches(
    from source: Observable<AssetRealtimeEvent>,
    symbol: String,
    scheduler: SerialDispatchQueueScheduler
) -> Observable<AssetRealtimeBatch> {
    source
        .observe(on: scheduler)
        .buffer(timeSpan: .milliseconds(250), count: 128, scheduler: scheduler)
        .compactMap { events in
            AssetRealtimeBatch(events: events, symbol: symbol)
        }
}

enum AssetExtendedTradingSession: Equatable, Sendable {
    case preMarket
    case afterHours
    case overnight

    var title: String {
        switch self {
        case .preMarket:
            "Pre-market"
        case .afterHours:
            "After-hours"
        case .overnight:
            "Overnight"
        }
    }

    var completedTitle: String {
        switch self {
        case .preMarket:
            "Last pre-market"
        case .afterHours:
            "Last after-hours"
        case .overnight:
            "Last overnight"
        }
    }
}
