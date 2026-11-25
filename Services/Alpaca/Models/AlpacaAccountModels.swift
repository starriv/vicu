import Foundation

struct AlpacaAccount: Codable, Hashable, Sendable {
    let id: String
    let accountNumber: String?
    let createdAt: String?
    let status: String?
    let currency: String?
    let buyingPower: String?
    let regtBuyingPower: String?
    let daytradingBuyingPower: String?
    let effectiveBuyingPower: String?
    let nonMarginableBuyingPower: String?
    let optionsBuyingPower: String?
    let bodDtbp: String?
    let cash: String?
    let accruedFees: String?
    let portfolioValue: String?
    let patternDayTrader: Bool?
    let tradingBlocked: Bool?
    let transfersBlocked: Bool?
    let accountBlocked: Bool?
    let tradeSuspendedByUser: Bool?
    let multiplier: String?
    let shortingEnabled: Bool?
    let equity: String?
    let lastEquity: String?
    let longMarketValue: String?
    let shortMarketValue: String?
    let positionMarketValue: String?
    let initialMargin: String?
    let maintenanceMargin: String?
    let lastMaintenanceMargin: String?
    let sma: String?
    let daytradeCount: Int?
    let balanceAsOf: String?
    let cryptoStatus: String?
    let optionsApprovedLevel: Int?
    let optionsTradingLevel: Int?
    let cryptoTier: Int?
    let intradayAdjustments: String?
    let pendingRegTAFFees: String?

    enum CodingKeys: String, CodingKey {
        case id
        case accountNumber = "account_number"
        case createdAt = "created_at"
        case status
        case currency
        case buyingPower = "buying_power"
        case regtBuyingPower = "regt_buying_power"
        case daytradingBuyingPower = "daytrading_buying_power"
        case effectiveBuyingPower = "effective_buying_power"
        case nonMarginableBuyingPower = "non_marginable_buying_power"
        case optionsBuyingPower = "options_buying_power"
        case bodDtbp = "bod_dtbp"
        case cash
        case accruedFees = "accrued_fees"
        case portfolioValue = "portfolio_value"
        case patternDayTrader = "pattern_day_trader"
        case tradingBlocked = "trading_blocked"
        case transfersBlocked = "transfers_blocked"
        case accountBlocked = "account_blocked"
        case tradeSuspendedByUser = "trade_suspended_by_user"
        case multiplier
        case shortingEnabled = "shorting_enabled"
        case equity
        case lastEquity = "last_equity"
        case longMarketValue = "long_market_value"
        case shortMarketValue = "short_market_value"
        case positionMarketValue = "position_market_value"
        case initialMargin = "initial_margin"
        case maintenanceMargin = "maintenance_margin"
        case lastMaintenanceMargin = "last_maintenance_margin"
        case sma
        case daytradeCount = "daytrade_count"
        case balanceAsOf = "balance_asof"
        case cryptoStatus = "crypto_status"
        case optionsApprovedLevel = "options_approved_level"
        case optionsTradingLevel = "options_trading_level"
        case cryptoTier = "crypto_tier"
        case intradayAdjustments = "intraday_adjustments"
        case pendingRegTAFFees = "pending_reg_taf_fees"
    }
}

struct AlpacaAccountActivitiesPage: Sendable {
    let activities: [AlpacaAccountActivity]
    let nextPageToken: String?
}

struct AlpacaAccountActivity: Decodable, Identifiable, Sendable {
    let activityType: String
    let id: String
    let cumulativeQuantity: String?
    let leavesQuantity: String?
    let price: String?
    let quantity: String?
    let side: String?
    let symbol: String?
    let transactionTime: String?
    let orderID: String?
    let type: String?
    let date: String?
    let netAmount: String?
    let cusip: String?
    let perShareAmount: String?
    let description: String?

    var occurredAt: Date? {
        AlpacaDateParser.date(transactionTime) ?? AlpacaDateParser.date(date)
    }

    enum CodingKeys: String, CodingKey {
        case activityType = "activity_type"
        case id
        case cumulativeQuantity = "cum_qty"
        case leavesQuantity = "leaves_qty"
        case price
        case quantity = "qty"
        case side
        case symbol
        case transactionTime = "transaction_time"
        case orderID = "order_id"
        case type
        case date
        case netAmount = "net_amount"
        case cusip
        case perShareAmount = "per_share_amount"
        case description
    }
}
