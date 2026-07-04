import Foundation

enum AlpacaOptionFeed: String, CaseIterable, Identifiable, Sendable {
    case indicative
    case opra

    var id: String { rawValue }
}

enum AlpacaOptionContractType: String, CaseIterable, Identifiable, Sendable {
    case call
    case put

    var id: String { rawValue }

    var title: String {
        switch self {
        case .call:
            "Calls"
        case .put:
            "Puts"
        }
    }
}

struct AlpacaOptionChainResponse: Decodable, Sendable {
    let snapshots: [String: AlpacaOptionSnapshotPayload]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case snapshots
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaOptionChainPage: Sendable {
    let snapshots: [AlpacaOptionSnapshot]
    let nextPageToken: String?
}

struct AlpacaOptionSnapshotsResponse: Decodable, Sendable {
    let snapshots: [String: AlpacaOptionSnapshotPayload]
    let nextPageToken: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        snapshots = try container.decodeIfPresent([String: AlpacaOptionSnapshotPayload].self, forKey: .snapshots) ?? [:]
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }

    private enum CodingKeys: String, CodingKey {
        case snapshots
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaOptionSnapshotsPage: Sendable {
    let snapshots: [AlpacaOptionSnapshot]
    let nextPageToken: String?
}

struct AlpacaOptionBarsResponse: Decodable, Sendable {
    let bars: [String: [AlpacaMarketBar]]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case bars
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaOptionBarsPage: Sendable {
    let bars: [AlpacaMarketBar]
    let nextPageToken: String?
}

struct AlpacaOptionTradesResponse: Decodable, Sendable {
    let trades: [String: [AlpacaOptionTrade]]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case trades
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaOptionTradesPage: Sendable {
    let trades: [AlpacaOptionTrade]
    let nextPageToken: String?
}

struct AlpacaLatestOptionTradesResponse: Decodable, Sendable {
    let trades: [String: AlpacaOptionTrade]
}

struct AlpacaOptionContractsResponse: Decodable, Sendable {
    let contracts: [AlpacaOptionContract]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case optionContracts = "option_contracts"
        case contracts
        case nextPageToken = "next_page_token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contracts = try container.decodeIfPresent([AlpacaOptionContract].self, forKey: .optionContracts)
            ?? container.decodeIfPresent([AlpacaOptionContract].self, forKey: .contracts)
            ?? []
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

struct AlpacaOptionContractsPage: Sendable {
    let contracts: [AlpacaOptionContract]
    let nextPageToken: String?
}

struct AlpacaOptionContract: Decodable, Identifiable, Sendable {
    let contractID: String?
    let symbol: String
    let name: String?
    let status: String?
    let expirationDate: String?
    let rootSymbol: String?
    let underlyingSymbol: String?
    let type: String?
    let strikePrice: String?

    var id: String { contractID ?? symbol }

    enum CodingKeys: String, CodingKey {
        case contractID = "id"
        case symbol
        case name
        case status
        case expirationDate = "expiration_date"
        case rootSymbol = "root_symbol"
        case underlyingSymbol = "underlying_symbol"
        case type
        case strikePrice = "strike_price"
    }
}

struct AlpacaOptionSnapshot: Identifiable, Equatable, Sendable {
    let contractSymbol: String
    let latestTrade: AlpacaOptionTrade?
    let latestQuote: AlpacaOptionQuote?
    let greeks: AlpacaOptionGreeks?
    let impliedVolatility: Double?

    var id: String { contractSymbol }

    init(contractSymbol: String, payload: AlpacaOptionSnapshotPayload) {
        self.contractSymbol = contractSymbol
        self.latestTrade = payload.latestTrade
        self.latestQuote = payload.latestQuote
        self.greeks = payload.greeks
        self.impliedVolatility = payload.impliedVolatility
    }
}

struct AlpacaOptionSnapshotPayload: Decodable, Equatable, Sendable {
    let latestTrade: AlpacaOptionTrade?
    let latestQuote: AlpacaOptionQuote?
    let greeks: AlpacaOptionGreeks?
    let impliedVolatility: Double?

    enum CodingKeys: String, CodingKey {
        case latestTrade
        case latestQuote
        case greeks
        case impliedVolatility
        case impliedVolatilitySnake = "implied_volatility"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latestTrade = try container.decodeIfPresent(AlpacaOptionTrade.self, forKey: .latestTrade)
        latestQuote = try container.decodeIfPresent(AlpacaOptionQuote.self, forKey: .latestQuote)
        greeks = try container.decodeIfPresent(AlpacaOptionGreeks.self, forKey: .greeks)
        let camelCaseIV = try container.decodeIfPresent(Double.self, forKey: .impliedVolatility)
        let snakeCaseIV = try container.decodeIfPresent(Double.self, forKey: .impliedVolatilitySnake)
        impliedVolatility = camelCaseIV ?? snakeCaseIV
    }
}

struct AlpacaOptionTrade: Decodable, Equatable, Sendable {
    let tradeID: String?
    let exchange: String?
    let price: Double?
    let size: Double?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case tradeID = "i"
        case exchange = "x"
        case price = "p"
        case size = "s"
        case timestamp = "t"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tradeID = try container.decodeFlexibleStringIfPresent(forKey: .tradeID)
        exchange = try container.decodeIfPresent(String.self, forKey: .exchange)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        size = try container.decodeIfPresent(Double.self, forKey: .size)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }

        if let value = try? decode(String.self, forKey: key) {
            return value
        }

        if let value = try? decode(Int64.self, forKey: key) {
            return String(value)
        }

        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }

        return nil
    }
}

struct AlpacaOptionQuote: Decodable, Equatable, Sendable {
    let askExchange: String?
    let askPrice: Double?
    let askSize: Double?
    let bidExchange: String?
    let bidPrice: Double?
    let bidSize: Double?
    let timestamp: String?

    var spread: Double? {
        guard let askPrice, let bidPrice else {
            return nil
        }

        return max(0, askPrice - bidPrice)
    }

    var midpoint: Double? {
        guard let askPrice, let bidPrice else {
            return nil
        }

        return (askPrice + bidPrice) / 2
    }

    enum CodingKeys: String, CodingKey {
        case askExchange = "ax"
        case askPrice = "ap"
        case askSize = "as"
        case bidExchange = "bx"
        case bidPrice = "bp"
        case bidSize = "bs"
        case timestamp = "t"
    }
}

struct AlpacaOptionGreeks: Decodable, Equatable, Sendable {
    let delta: Double?
    let gamma: Double?
    let rho: Double?
    let theta: Double?
    let vega: Double?
}
