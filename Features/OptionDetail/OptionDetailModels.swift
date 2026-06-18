import Foundation
import SwiftUI

struct OptionDetailSnapshotModel {
    let descriptor: OptionContractDescriptor
    let lastPrice: Double?
    let midPrice: Double?
    let displayPrice: Double?
    let bidPrice: Double?
    let askPrice: Double?
    let bidSize: Double?
    let askSize: Double?
    let spread: Double?
    let quoteTime: String?
    let lastTradeTime: String?
    let priceText: String
    let typeTint: Color
    let updatedText: String
    let metricsTitle: String
    let metrics: [OptionDetailMetricModel]
    let specs: [OptionDetailMetricModel]

    init(
        descriptor: OptionContractDescriptor,
        snapshot: AlpacaOptionSnapshot?,
        fallbackTrade: AlpacaOptionTrade? = nil
    ) {
        let quote = snapshot?.latestQuote
        let trade = snapshot?.latestTrade ?? fallbackTrade
        let greeks = snapshot?.greeks
        let lastPrice = trade?.price
        let midPrice = quote?.midpoint
        let displayPrice = lastPrice ?? midPrice ?? quote?.bidPrice ?? quote?.askPrice

        self.descriptor = descriptor
        self.lastPrice = lastPrice
        self.midPrice = midPrice
        self.displayPrice = displayPrice
        bidPrice = quote?.bidPrice
        askPrice = quote?.askPrice
        bidSize = quote?.bidSize
        askSize = quote?.askSize
        spread = quote?.spread
        quoteTime = quote?.timestamp
        lastTradeTime = trade?.timestamp
        priceText = OptionValueText.money(displayPrice)
        typeTint = descriptor.isPut ? AppTheme.ColorToken.negative : AppTheme.ColorToken.positive

        let eventDate = AlpacaDateParser.date(quote?.timestamp) ?? AlpacaDateParser.date(trade?.timestamp)
        updatedText = OptionValueText.time(eventDate)

        var resolvedMetrics = [
            OptionDetailMetricModel(title: "Bid", value: OptionValueText.money(quote?.bidPrice)),
            OptionDetailMetricModel(title: "Ask", value: OptionValueText.money(quote?.askPrice)),
            OptionDetailMetricModel(title: "Mid", value: OptionValueText.money(midPrice)),
            OptionDetailMetricModel(title: "Last", value: OptionValueText.money(lastPrice))
        ]

        var greekMetrics: [OptionDetailMetricModel] = []
        Self.appendAvailableMetric(
            title: "IV",
            value: OptionValueText.percent(snapshot?.impliedVolatility),
            to: &greekMetrics
        )
        Self.appendAvailableMetric(
            title: "Delta",
            value: OptionValueText.decimal(greeks?.delta),
            to: &greekMetrics
        )
        Self.appendAvailableMetric(
            title: "Gamma",
            value: OptionValueText.decimal(greeks?.gamma),
            to: &greekMetrics
        )
        Self.appendAvailableMetric(
            title: "Theta",
            value: OptionValueText.decimal(greeks?.theta),
            to: &greekMetrics
        )
        Self.appendAvailableMetric(
            title: "Vega",
            value: OptionValueText.decimal(greeks?.vega),
            to: &greekMetrics
        )
        Self.appendAvailableMetric(
            title: "Rho",
            value: OptionValueText.decimal(greeks?.rho),
            to: &greekMetrics
        )

        metricsTitle = greekMetrics.isEmpty ? "Pricing & liquidity" : "Greeks & liquidity"
        resolvedMetrics.append(contentsOf: greekMetrics)
        resolvedMetrics.append(
            contentsOf: [
                OptionDetailMetricModel(title: "Bid Size", value: OptionValueText.size(quote?.bidSize)),
                OptionDetailMetricModel(title: "Ask Size", value: OptionValueText.size(quote?.askSize))
            ]
        )
        metrics = resolvedMetrics

        specs = [
            OptionDetailMetricModel(title: "Underlying", value: descriptor.underlyingSymbol),
            OptionDetailMetricModel(title: "Type", value: descriptor.typeText),
            OptionDetailMetricModel(title: "Expiration", value: descriptor.expirationText),
            OptionDetailMetricModel(title: "DTE", value: descriptor.dteText),
            OptionDetailMetricModel(title: "Strike", value: descriptor.strikeText),
            OptionDetailMetricModel(title: "Feed", value: "Indicative")
        ]
    }

    private static func appendAvailableMetric(
        title: String,
        value: String,
        to metrics: inout [OptionDetailMetricModel]
    ) {
        guard value != AppFormatter.placeholder else {
            return
        }

        metrics.append(OptionDetailMetricModel(title: title, value: value))
    }
}

struct OptionDetailMetricModel: Identifiable, Equatable {
    let title: String
    let value: String

    var id: String {
        title
    }
}

struct OptionTradeRowModel: Identifiable, Equatable {
    let id: String
    let dedupeKey: String
    let priceText: String
    let sizeText: String
    let exchangeText: String
    let timeText: String

    init(trade: AlpacaOptionTrade, offset: Int) {
        let timestamp = trade.timestamp ?? "na"
        let exchange = trade.exchange ?? AppFormatter.placeholder
        let fallbackKey = "\(timestamp)-\(exchange)-\(trade.price ?? 0)-\(trade.size ?? 0)"
        dedupeKey = trade.tradeID ?? fallbackKey
        id = trade.tradeID ?? "\(fallbackKey)-\(offset)"
        priceText = OptionValueText.money(trade.price)
        sizeText = OptionValueText.size(trade.size)
        exchangeText = exchange
        timeText = OptionValueText.time(AlpacaDateParser.date(trade.timestamp))
    }
}

struct OptionTradesLoadMoreTrigger: Equatable {
    let range: AssetChartRange
    let pageToken: String?
    let count: Int
}
