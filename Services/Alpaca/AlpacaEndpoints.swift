import Foundation

// These enums are module-internal by design: AlpacaClient builds endpoint values
// and passes them to AlpacaTradingClient / AlpacaMarketDataClient. Nothing outside
// Services/Alpaca/ should construct or inspect endpoint values directly — callers
// should go through AlpacaServicing or a page service instead.
enum AlpacaEndpoint: Sendable {
    case account
    case accountActivities(pageSize: Int, pageToken: String?)
    case assets(assetClass: String?)
    case asset(symbolOrAssetID: String)
    case marketClock
    case marketCalendar(market: String, start: String, end: String)
    case optionContracts(underlyingSymbol: String, expirationDateGTE: String?, expirationDateLTE: String?, limit: Int, pageToken: String?)
    case positions
    case position(symbolOrAssetID: String)
    case closePosition(symbolOrAssetID: String)
    case recentOrders
    case order(id: String, nested: Bool)
    case cancelOrder(id: String)
    case replaceOrder(id: String)
    case watchlists
    case createWatchlist
    case watchlist(id: String)
    case updateWatchlist(id: String)
    case deleteWatchlist(id: String)
    case addSymbolToWatchlist(id: String)
    case watchlistSymbol(id: String, symbol: String)
    case portfolioHistory(range: PortfolioHistoryRange, accountCreatedAt: String?)
    case submitOrder

    var path: String {
        switch self {
        case .account:
            APIPaths.AlpacaTrading.account
        case .accountActivities:
            APIPaths.AlpacaTrading.accountActivities
        case .assets:
            APIPaths.AlpacaTrading.assets
        case .asset(let symbolOrAssetID):
            APIPaths.AlpacaTrading.asset(symbolOrAssetID)
        case .marketClock:
            APIPaths.AlpacaTrading.marketClock
        case .marketCalendar(let market, _, _):
            APIPaths.AlpacaTrading.marketCalendar(market)
        case .optionContracts:
            APIPaths.AlpacaTrading.optionContracts
        case .positions:
            APIPaths.AlpacaTrading.positions
        case .position(let symbolOrAssetID), .closePosition(let symbolOrAssetID):
            APIPaths.AlpacaTrading.position(symbolOrAssetID)
        case .recentOrders, .submitOrder:
            APIPaths.AlpacaTrading.orders
        case .order(let id, _), .cancelOrder(let id), .replaceOrder(let id):
            APIPaths.AlpacaTrading.order(id)
        case .watchlists, .createWatchlist:
            APIPaths.AlpacaTrading.watchlists
        case .watchlist(let id), .updateWatchlist(let id), .deleteWatchlist(let id), .addSymbolToWatchlist(let id):
            APIPaths.AlpacaTrading.watchlist(id)
        case .watchlistSymbol(let id, let symbol):
            APIPaths.AlpacaTrading.watchlistSymbol(id: id, symbol: symbol)
        case .portfolioHistory:
            APIPaths.AlpacaTrading.portfolioHistory
        }
    }

    var method: HTTPMethod {
        switch self {
        case .submitOrder, .createWatchlist, .addSymbolToWatchlist:
            .post
        case .replaceOrder:
            .patch
        case .updateWatchlist:
            .put
        case .deleteWatchlist, .watchlistSymbol, .cancelOrder, .closePosition:
            .delete
        default:
            .get
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .accountActivities(let pageSize, let pageToken):
            var items = [
                URLQueryItem(name: "direction", value: "desc"),
                URLQueryItem(name: "page_size", value: String(pageSize))
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .assets(let assetClass):
            var items = [
                URLQueryItem(name: "status", value: "active")
            ]

            if let assetClass, !assetClass.isEmpty {
                items.append(URLQueryItem(name: "asset_class", value: assetClass))
            }

            return items
        case .marketClock:
            return [
                URLQueryItem(name: "markets", value: "NYSE,NASDAQ")
            ]
        case .marketCalendar(_, let start, let end):
            return [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end)
            ]
        case .optionContracts(let underlyingSymbol, let expirationDateGTE, let expirationDateLTE, let limit, let pageToken):
            var items = [
                URLQueryItem(name: "underlying_symbols", value: underlyingSymbol),
                URLQueryItem(name: "status", value: "active"),
                URLQueryItem(name: "limit", value: String(limit))
            ]

            if let expirationDateGTE, !expirationDateGTE.isEmpty {
                items.append(URLQueryItem(name: "expiration_date_gte", value: expirationDateGTE))
            }

            if let expirationDateLTE, !expirationDateLTE.isEmpty {
                items.append(URLQueryItem(name: "expiration_date_lte", value: expirationDateLTE))
            }

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .recentOrders:
            return [
                URLQueryItem(name: "status", value: "all"),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "direction", value: "desc")
            ]
        case .order(_, let nested):
            return nested ? [URLQueryItem(name: "nested", value: "true")] : []
        case .portfolioHistory(let range, let accountCreatedAt):
            return range.queryItems(accountCreatedAt: accountCreatedAt)
        default:
            return []
        }
    }
}

// Same visibility rationale as AlpacaEndpoint above.
enum AlpacaMarketDataEndpoint: Sendable {
    case stockSnapshots(symbols: [String], feed: AlpacaMarketDataFeed)
    case stockLatestTrade(symbol: String, feed: AlpacaMarketDataFeed)
    case stockLatestQuotes(symbols: [String], feed: AlpacaMarketDataFeed)
    case stockLatestBars(symbols: [String], feed: AlpacaMarketDataFeed)
    case stockQuotes(symbol: String, feed: AlpacaMarketDataFeed, interval: StockDataInterval, limit: Int, pageToken: String?, sort: AlpacaSortDirection)
    case stockBars(symbol: String, range: AssetChartRange, feed: AlpacaMarketDataFeed, interval: StockDataInterval?)
    case optionChain(underlyingSymbol: String, feed: AlpacaOptionFeed, type: AlpacaOptionContractType?, expirationDate: String?, limit: Int, pageToken: String?)
    case optionSnapshots(symbols: [String], feed: AlpacaOptionFeed, limit: Int, pageToken: String?)
    case optionBars(symbol: String, range: AssetChartRange, feed: AlpacaOptionFeed, interval: StockDataInterval, limit: Int, pageToken: String?, sort: AlpacaSortDirection)
    case optionTrades(symbol: String, feed: AlpacaOptionFeed, interval: StockDataInterval, limit: Int, pageToken: String?, sort: AlpacaSortDirection)
    case optionLatestTrades(symbols: [String], feed: AlpacaOptionFeed)
    case news(symbols: [String], interval: NewsDataInterval, limit: Int, pageToken: String?, sort: AlpacaSortDirection, includeContent: Bool)
    case stockMovers(top: Int)
    case mostActiveStocks(top: Int, sort: MarketMostActiveSort)

    var path: String {
        switch self {
        case .stockSnapshots:
            APIPaths.AlpacaMarketData.stockSnapshots
        case .stockLatestTrade(let symbol, _):
            APIPaths.AlpacaMarketData.stockLatestTrade(symbol: symbol)
        case .stockLatestQuotes:
            APIPaths.AlpacaMarketData.stockLatestQuotes
        case .stockLatestBars:
            APIPaths.AlpacaMarketData.stockLatestBars
        case .stockQuotes:
            APIPaths.AlpacaMarketData.stockQuotes
        case .stockBars:
            APIPaths.AlpacaMarketData.stockBars
        case .optionChain(let underlyingSymbol, _, _, _, _, _):
            APIPaths.AlpacaMarketData.optionChainSnapshots(underlyingSymbol: underlyingSymbol)
        case .optionSnapshots:
            APIPaths.AlpacaMarketData.optionSnapshots
        case .optionBars:
            APIPaths.AlpacaMarketData.optionBars
        case .optionTrades:
            APIPaths.AlpacaMarketData.optionTrades
        case .optionLatestTrades:
            APIPaths.AlpacaMarketData.optionLatestTrades
        case .news:
            APIPaths.AlpacaMarketData.news
        case .stockMovers:
            APIPaths.AlpacaMarketData.stockMovers
        case .mostActiveStocks:
            APIPaths.AlpacaMarketData.mostActiveStocks
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .stockSnapshots(let symbols, let feed):
            return [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "currency", value: "USD")
            ]
        case .stockLatestTrade(_, let feed):
            return [
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "currency", value: "USD")
            ]
        case .stockLatestQuotes(let symbols, let feed):
            return [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "currency", value: "USD")
            ]
        case .stockLatestBars(let symbols, let feed):
            return [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "currency", value: "USD")
            ]
        case .stockQuotes(let symbol, let feed, let interval, let limit, let pageToken, let sort):
            var items = [
                URLQueryItem(name: "symbols", value: symbol),
                URLQueryItem(name: "start", value: interval.start),
                URLQueryItem(name: "end", value: interval.end),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "feed", value: Self.quotesFeedValue(feed)),
                URLQueryItem(name: "currency", value: "USD"),
                URLQueryItem(name: "sort", value: sort.rawValue)
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .stockBars(let symbol, let range, let feed, let intervalOverride):
            let interval = intervalOverride ?? Self.dateInterval(for: range)
            return [
                URLQueryItem(name: "symbols", value: symbol),
                URLQueryItem(name: "timeframe", value: range.timeframe),
                URLQueryItem(name: "start", value: interval.start),
                URLQueryItem(name: "end", value: interval.end),
                URLQueryItem(name: "limit", value: String(range.requestLimit)),
                URLQueryItem(name: "adjustment", value: "all"),
                URLQueryItem(name: "feed", value: Self.barsFeedValue(feed)),
                URLQueryItem(name: "currency", value: "USD"),
                URLQueryItem(name: "sort", value: "asc")
            ]
        case .optionChain(_, let feed, let type, let expirationDate, let limit, let pageToken):
            var items = [
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "limit", value: String(limit))
            ]

            if let type {
                items.append(URLQueryItem(name: "type", value: type.rawValue))
            }

            if let expirationDate, !expirationDate.isEmpty {
                items.append(URLQueryItem(name: "expiration_date", value: expirationDate))
            }

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .optionSnapshots(let symbols, let feed, let limit, let pageToken):
            var items = [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "limit", value: String(limit))
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .optionBars(let symbol, let range, _, let interval, let limit, let pageToken, let sort):
            var items = [
                URLQueryItem(name: "symbols", value: symbol),
                URLQueryItem(name: "timeframe", value: range.timeframe),
                URLQueryItem(name: "start", value: interval.start),
                URLQueryItem(name: "end", value: interval.end),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: sort.rawValue)
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .optionTrades(let symbol, _, let interval, let limit, let pageToken, let sort):
            var items = [
                URLQueryItem(name: "symbols", value: symbol),
                URLQueryItem(name: "start", value: interval.start),
                URLQueryItem(name: "end", value: interval.end),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: sort.rawValue)
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .optionLatestTrades(let symbols, let feed):
            return [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue)
            ]
        case .news(let symbols, let interval, let limit, let pageToken, let sort, let includeContent):
            var items = [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: sort.rawValue),
                URLQueryItem(name: "include_content", value: includeContent ? "true" : "false")
            ]

            if let start = interval.start, !start.isEmpty {
                items.append(URLQueryItem(name: "start", value: start))
            }

            if let end = interval.end, !end.isEmpty {
                items.append(URLQueryItem(name: "end", value: end))
            }

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .stockMovers(let top):
            return [
                URLQueryItem(name: "top", value: String(top))
            ]
        case .mostActiveStocks(let top, let sort):
            return [
                URLQueryItem(name: "by", value: sort.rawValue),
                URLQueryItem(name: "top", value: String(top))
            ]
        }
    }

    private static func barsFeedValue(_ feed: AlpacaMarketDataFeed) -> String {
        switch feed {
        case .delayedSIP:
            "sip"
        case .overnight:
            "boats"
        default:
            feed.rawValue
        }
    }

    private static func quotesFeedValue(_ feed: AlpacaMarketDataFeed) -> String {
        switch feed {
        case .delayedSIP:
            "sip"
        case .overnight:
            "iex"
        default:
            feed.rawValue
        }
    }

    private static func dateInterval(for range: AssetChartRange, now: Date = Date()) -> StockDataInterval {
        let startDate = range.startDate(now: now)
        let formatter = makeStockDataDateFormatter()
        return StockDataInterval(
            start: formatter.string(from: startDate),
            end: formatter.string(from: now)
        )
    }

    static func makeStockDataDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withColonSeparatorInTimeZone
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

// Implementation details for AlpacaMarketDataEndpoint query-param construction.
// Intentionally left internal (rather than private) so AlpacaClient can build
// interval values and pass them as endpoint case arguments.
struct StockDataInterval: Sendable {
    let start: String
    let end: String
}

struct NewsDataInterval: Sendable {
    let start: String?
    let end: String?
}
