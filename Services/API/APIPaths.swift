import Foundation

enum APIPaths {
    static func encodedPathSegment(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/")
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? trimmedValue
    }

    enum AlpacaTrading {
        static let paperBaseURL = URL(string: "https://paper-api.alpaca.markets")!
        static let liveBaseURL = URL(string: "https://api.alpaca.markets")!

        static let account = "v2/account"
        static let accountActivities = "v2/account/activities"
        static let assets = "v2/assets"
        static let marketClock = "v3/clock"
        static let optionContracts = "v2/options/contracts"
        static let positions = "v2/positions"
        static let orders = "v2/orders"
        static let watchlists = "v2/watchlists"
        static let portfolioHistory = "v2/account/portfolio/history"

        static func asset(_ symbolOrAssetID: String) -> String {
            "v2/assets/\(APIPaths.encodedPathSegment(symbolOrAssetID))"
        }

        static func marketCalendar(_ market: String) -> String {
            "v3/calendar/\(APIPaths.encodedPathSegment(market))"
        }

        static func position(_ symbolOrAssetID: String) -> String {
            "v2/positions/\(APIPaths.encodedPathSegment(symbolOrAssetID))"
        }

        static func order(_ id: String) -> String {
            "v2/orders/\(APIPaths.encodedPathSegment(id))"
        }

        static func watchlist(_ id: String) -> String {
            "v2/watchlists/\(APIPaths.encodedPathSegment(id))"
        }

        static func watchlistSymbol(id: String, symbol: String) -> String {
            let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return "v2/watchlists/\(APIPaths.encodedPathSegment(id))/\(APIPaths.encodedPathSegment(normalizedSymbol))"
        }
    }

    enum AlpacaMarketData {
        static let baseURL = URL(string: "https://data.alpaca.markets")!

        static let stockSnapshots = "v2/stocks/snapshots"
        static let stockLatestQuotes = "v2/stocks/quotes/latest"
        static let stockLatestBars = "v2/stocks/bars/latest"
        static let stockQuotes = "v2/stocks/quotes"
        static let stockBars = "v2/stocks/bars"
        static let optionSnapshots = "v1beta1/options/snapshots"
        static let optionBars = "v1beta1/options/bars"
        static let optionTrades = "v1beta1/options/trades"
        static let optionLatestTrades = "v1beta1/options/trades/latest"
        static let news = "v1beta1/news"
        static let stockMovers = "v1beta1/screener/stocks/movers"
        static let mostActiveStocks = "v1beta1/screener/stocks/most-actives"

        static func stockLatestTrade(symbol: String) -> String {
            "v2/stocks/\(APIPaths.encodedPathSegment(symbol))/trades/latest"
        }

        static func optionChainSnapshots(underlyingSymbol: String) -> String {
            "v1beta1/options/snapshots/\(APIPaths.encodedPathSegment(underlyingSymbol))"
        }
    }

    enum AlpacaStreams {
        static let marketDataBaseURL = URL(string: "wss://stream.data.alpaca.markets")!
        static let activityEvents = "v2beta1/events/activities"
        static let tradeEvents = "v2beta1/events/trades"

        static func marketDataStreamPath(feed: AlpacaMarketDataFeed) -> String {
            switch feed {
            case .iex, .sip, .delayedSIP:
                "v2/\(feed.rawValue)"
            case .boats, .overnight:
                "v1beta1/\(feed.rawValue)"
            }
        }
    }
}
