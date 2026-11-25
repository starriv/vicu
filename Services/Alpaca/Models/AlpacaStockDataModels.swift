import Foundation
import SwiftUI

struct MarketIndexQuote: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let price: Double?
    let change: Double?
    let percentChange: Double?

    var isPositive: Bool {
        (change ?? 0) >= 0
    }

    func updating(price latestPrice: Double) -> MarketIndexQuote {
        let previousClose = inferredPreviousClose
        let latestChange = previousClose.map { latestPrice - $0 }
        let latestPercentChange = previousClose.flatMap { close -> Double? in
            close == 0 ? nil : (latestPrice - close) / close
        }

        return MarketIndexQuote(
            id: id,
            title: title,
            symbol: symbol,
            price: latestPrice,
            change: latestChange,
            percentChange: latestPercentChange
        )
    }

    private var inferredPreviousClose: Double? {
        if let price, let change {
            return price - change
        }

        if let price, let percentChange, percentChange != -1 {
            return price / (1 + percentChange)
        }

        return nil
    }
}

struct MarketMover: Codable, Identifiable, Sendable {
    let symbol: String
    let price: Double?
    let change: Double?
    let percentChange: Double?

    var id: String { symbol }
    var isPositive: Bool {
        (change ?? 0) >= 0
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case price
        case change
        case percentChange = "percent_change"
    }
}

struct MarketActiveSymbol: Codable, Identifiable, Sendable {
    let symbol: String
    let companyName: String?
    let price: Double?
    let change: Double?
    let percentChange: Double?
    let volume: Double?
    let tradeCount: Double?

    var id: String { symbol }
    var isPositive: Bool {
        (change ?? 0) >= 0
    }

    init(
        symbol: String,
        companyName: String? = nil,
        price: Double?,
        change: Double?,
        percentChange: Double?,
        volume: Double?,
        tradeCount: Double?
    ) {
        self.symbol = symbol
        self.companyName = companyName
        self.price = price
        self.change = change
        self.percentChange = percentChange
        self.volume = volume
        self.tradeCount = tradeCount
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case companyName = "company_name"
        case price
        case change
        case percentChange = "percent_change"
        case volume
        case tradeCount = "trade_count"
    }
}

struct MarketSearchResult: Identifiable, Sendable {
    let asset: AlpacaAsset
    let quote: MarketActiveSymbol?

    var id: String { asset.symbol }
    var symbol: String { asset.symbol }
    var companyName: String { asset.name ?? AppFormatter.placeholder }
    var exchange: String { asset.exchange ?? AppFormatter.placeholder }
    var price: Double? { quote?.price }
    var percentChange: Double? { quote?.percentChange }
    var isPositive: Bool { quote?.isPositive ?? true }
}

enum MarketMostActiveSort: String, CaseIterable, Identifiable, Sendable {
    case volume
    case trades

    static var displayCases: [MarketMostActiveSort] {
        [.trades, .volume]
    }

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .volume:
            L10n.Markets.sortVolume
        case .trades:
            L10n.Markets.sortTrades
        }
    }

    var searchPopularSubtitle: LocalizedStringKey {
        switch self {
        case .volume:
            L10n.Markets.searchPopularVolumeSubtitle
        case .trades:
            L10n.Markets.searchPopularTradesSubtitle
        }
    }

    var icon: String {
        switch self {
        case .volume:
            "chart.bar.fill"
        case .trades:
            "flame"
        }
    }
}

enum AlpacaMarketDataFeed: String, Codable, CaseIterable, Identifiable, Sendable {
    case iex
    case sip
    case delayedSIP = "delayed_sip"
    case boats
    case overnight

    var id: String { rawValue }

    var streamPath: String {
        APIPaths.AlpacaStreams.marketDataStreamPath(feed: self)
    }
}

enum AssetChartRange: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case oneDay
    case oneWeek
    case oneMonth
    case threeMonths
    case oneYear
    case yearToDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay:
            "1D"
        case .oneWeek:
            "1W"
        case .oneMonth:
            "1M"
        case .threeMonths:
            "3M"
        case .oneYear:
            "1Y"
        case .yearToDate:
            "YTD"
        }
    }

    var timeframe: String {
        switch self {
        case .oneDay:
            "5Min"
        case .oneWeek:
            "15Min"
        case .oneMonth, .threeMonths, .yearToDate:
            "1Day"
        case .oneYear:
            "1Week"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .oneDay, .oneWeek:
            .day
        case .oneMonth, .threeMonths:
            .month
        case .oneYear, .yearToDate:
            .year
        }
    }

    var calendarValue: Int {
        switch self {
        case .oneDay:
            -1
        case .oneWeek:
            -7
        case .oneMonth:
            -1
        case .threeMonths:
            -3
        case .oneYear, .yearToDate:
            -1
        }
    }

    var requestLimit: Int {
        switch self {
        case .oneDay:
            10000
        case .oneWeek:
            900
        case .oneMonth:
            160
        case .threeMonths:
            260
        case .oneYear, .yearToDate:
            260
        }
    }

    func startDate(now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: 0) ?? .current

        if self == .yearToDate {
            let year = calendar.component(.year, from: now)
            return calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: year,
                    month: 1,
                    day: 1,
                    hour: 0,
                    minute: 0,
                    second: 0
                )
            ) ?? now
        }

        return calendar.date(byAdding: calendarComponent, value: calendarValue, to: now) ?? now
    }
}

struct AssetDetailSnapshot: Codable, Sendable {
    let asset: AlpacaAsset
    let stockSnapshot: AlpacaStockSnapshot?
    let bars: [AlpacaMarketBar]
    let chartBaseline: Double?
    let range: AssetChartRange
    let feed: AlpacaMarketDataFeed
    let sessionProgress: MarketSessionProgress?
    let latestBar: AlpacaMarketBar?
}

struct AlpacaResolvedStockSnapshot: Sendable {
    let snapshot: AlpacaStockSnapshot?
    let feed: AlpacaMarketDataFeed
    let activeSession: MarketSessionKind?
    let latestBar: AlpacaMarketBar?
}

struct AlpacaStockSnapshotsResponse: Decodable, Sendable {
    let snapshots: [String: AlpacaStockSnapshot]

    init(snapshots: [String: AlpacaStockSnapshot]) {
        self.snapshots = snapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.snapshots) {
            snapshots = try container.decode([String: AlpacaStockSnapshot].self, forKey: .snapshots)
        } else {
            snapshots = try [String: AlpacaStockSnapshot](from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case snapshots
    }
}

struct AlpacaLatestStockTradeResponse: Decodable, Sendable {
    let symbol: String?
    let trade: AlpacaStockTrade?
}

struct AlpacaLatestStockQuotesResponse: Decodable, Sendable {
    let quotes: [String: AlpacaStockQuote]
}

struct AlpacaStockQuotesResponse: Decodable, Sendable {
    let quotes: [String: [AlpacaStockQuote]]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case quotes
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaStockQuotesPage: Sendable {
    let quotes: [AlpacaStockQuote]
    let nextPageToken: String?
}

enum AlpacaSortDirection: String, Sendable {
    case asc
    case desc
}

struct AlpacaLatestStockBarsResponse: Decodable, Sendable {
    let bars: [String: AlpacaMarketBar]
}

struct AlpacaStockSnapshot: Codable, Sendable {
    let latestTrade: AlpacaStockTrade?
    let latestQuote: AlpacaStockQuote?
    let minuteBar: AlpacaMarketBar?
    let dailyBar: AlpacaMarketBar?
    let previousDailyBar: AlpacaMarketBar?

    static let empty = AlpacaStockSnapshot(
        latestTrade: nil,
        latestQuote: nil,
        minuteBar: nil,
        dailyBar: nil,
        previousDailyBar: nil
    )

    init(
        latestTrade: AlpacaStockTrade?,
        latestQuote: AlpacaStockQuote?,
        minuteBar: AlpacaMarketBar?,
        dailyBar: AlpacaMarketBar?,
        previousDailyBar: AlpacaMarketBar?
    ) {
        self.latestTrade = latestTrade
        self.latestQuote = latestQuote
        self.minuteBar = minuteBar
        self.dailyBar = dailyBar
        self.previousDailyBar = previousDailyBar
    }

    func withLatestTrade(_ trade: AlpacaStockTrade?) -> AlpacaStockSnapshot {
        AlpacaStockSnapshot(
            latestTrade: trade ?? latestTrade,
            latestQuote: latestQuote,
            minuteBar: minuteBar,
            dailyBar: dailyBar,
            previousDailyBar: previousDailyBar
        )
    }

    func withLatestQuote(_ quote: AlpacaStockQuote?) -> AlpacaStockSnapshot {
        AlpacaStockSnapshot(
            latestTrade: latestTrade,
            latestQuote: quote ?? latestQuote,
            minuteBar: minuteBar,
            dailyBar: dailyBar,
            previousDailyBar: previousDailyBar
        )
    }

    enum CodingKeys: String, CodingKey {
        case latestTrade
        case latestQuote
        case minuteBar
        case dailyBar
        case previousDailyBar = "prevDailyBar"
    }
}

struct AlpacaStockTrade: Codable, Sendable {
    let symbol: String?
    let exchange: String?
    let price: Double?
    let size: Double?
    let timestamp: String?
    let conditions: [String]?
    let tape: String?

    enum CodingKeys: String, CodingKey {
        case symbol = "S"
        case exchange = "x"
        case price = "p"
        case size = "s"
        case timestamp = "t"
        case conditions = "c"
        case tape = "z"
    }
}

struct AlpacaStockQuote: Codable, Sendable {
    let symbol: String?
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

    enum CodingKeys: String, CodingKey {
        case symbol = "S"
        case askExchange = "ax"
        case askPrice = "ap"
        case askSize = "as"
        case bidExchange = "bx"
        case bidPrice = "bp"
        case bidSize = "bs"
        case conditions = "c"
        case timestamp = "t"
        case tape = "z"
    }
}

struct AlpacaMarketBar: Codable, Sendable, Equatable {
    let symbol: String?
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double?
    let volume: Double?
    let vwap: Double?
    let tradeCount: Double?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case symbol = "S"
        case open = "o"
        case high = "h"
        case low = "l"
        case close = "c"
        case volume = "v"
        case vwap = "vw"
        case tradeCount = "n"
        case timestamp = "t"
    }
}

#if DEBUG
extension AlpacaMarketBar {
    var debugSummary: String {
        let openText = open.map { String($0) } ?? "nil"
        let highText = high.map { String($0) } ?? "nil"
        let lowText = low.map { String($0) } ?? "nil"
        let closeText = close.map { String($0) } ?? "nil"
        let volumeText = volume.map { String($0) } ?? "nil"
        let tradeCountText = tradeCount.map { String($0) } ?? "nil"

        return [
            "symbol=\(symbol ?? "nil")",
            "t=\(timestamp ?? "nil")",
            "o=\(openText)",
            "h=\(highText)",
            "l=\(lowText)",
            "c=\(closeText)",
            "v=\(volumeText)",
            "n=\(tradeCountText)"
        ].joined(separator: " ")
    }
}
#endif

struct AlpacaStockBarsResponse: Decodable, Sendable {
    let bars: [String: [AlpacaMarketBar]]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case bars
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaMarketMoversResponse: Decodable, Sendable {
    let gainers: [MarketMover]
    let losers: [MarketMover]
}

struct AlpacaMostActivesResponse: Decodable, Sendable {
    let mostActives: [MarketActiveSymbol]

    enum CodingKeys: String, CodingKey {
        case mostActives = "most_actives"
    }
}
