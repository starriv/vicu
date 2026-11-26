import Foundation

struct AssetParsedMarketBar: Sendable {
    let bar: AlpacaMarketBar
    let date: Date
    let minuteKey: Int

    init(bar: AlpacaMarketBar, date: Date) {
        self.bar = bar
        self.date = date
        self.minuteKey = Int(floor(date.timeIntervalSince1970 / 60))
    }

    init?(bar: AlpacaMarketBar) {
        guard let date = AlpacaDateParser.date(bar.timestamp) else {
            return nil
        }
        self.init(bar: bar, date: date)
    }
}

struct AssetChartRenderInput: Sendable {
    let bars: [AssetChartInputBar]
    let xDomain: ClosedRange<Double>?
    let priceChangeBaseline: Double?
}

struct AssetIntradaySessionContext: Sendable {
    let symbol: String
    let feed: AlpacaMarketDataFeed
    let sessionProgress: MarketSessionProgress?
    let latestTrade: AlpacaRealtimeTrade?
    let quote: AlpacaRealtimeQuote?
    let latestOvernightBar: AlpacaMarketBar?
    let overnightSupplementEntries: [AssetParsedMarketBar]
    let previousClose: Double?
    let dayOpen: Double?
    let latestCoreSessionClose: Double?
    let currentPrice: Double?

    init(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        sessionProgress: MarketSessionProgress?,
        latestTrade: AlpacaRealtimeTrade?,
        quote: AlpacaRealtimeQuote?,
        latestOvernightBar: AlpacaMarketBar?,
        overnightSupplementEntries: [AssetParsedMarketBar],
        previousClose: Double?,
        dayOpen: Double?,
        latestCoreSessionClose: Double?,
        currentPrice: Double?
    ) {
        self.symbol = symbol
        self.feed = feed
        self.sessionProgress = sessionProgress
        self.latestTrade = latestTrade
        self.quote = quote
        self.latestOvernightBar = latestOvernightBar
        self.overnightSupplementEntries = overnightSupplementEntries
        self.previousClose = previousClose
        self.dayOpen = dayOpen
        self.latestCoreSessionClose = latestCoreSessionClose
        self.currentPrice = currentPrice
    }

    init(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        sessionProgress: MarketSessionProgress?,
        latestTrade: AlpacaRealtimeTrade?,
        quote: AlpacaRealtimeQuote?,
        latestOvernightBar: AlpacaMarketBar?,
        overnightSupplementBars: [AlpacaMarketBar],
        previousClose: Double?,
        dayOpen: Double?,
        latestCoreSessionClose: Double?,
        currentPrice: Double?
    ) {
        self.init(
            symbol: symbol,
            feed: feed,
            sessionProgress: sessionProgress,
            latestTrade: latestTrade,
            quote: quote,
            latestOvernightBar: latestOvernightBar,
            overnightSupplementEntries: overnightSupplementBars.compactMap(AssetParsedMarketBar.init(bar:)),
            previousClose: previousClose,
            dayOpen: dayOpen,
            latestCoreSessionClose: latestCoreSessionClose,
            currentPrice: currentPrice
        )
    }
}

/// Pure, testable mapper that translates raw Alpaca bars + intraday session schedules
/// into normalized, pre-parsed chart inputs without bloating `AssetDetailStore`.
enum AssetIntradaySessionMapper {
    static let oneDayChartSlotDuration: TimeInterval = 5 * 60
    static let maxRetainedBars = 900
    static let maxOvernightSupplementBars = 300

    static func makeRenderInput(
        from sourceBars: [AlpacaMarketBar],
        range: AssetChartRange,
        priceChangeBaseline: Double?,
        context: AssetIntradaySessionContext
    ) -> AssetChartRenderInput {
        makeRenderInput(
            fromParsedBars: preParseBars(sourceBars),
            range: range,
            priceChangeBaseline: priceChangeBaseline,
            context: context
        )
    }

    static func makeRenderInput(
        fromParsedBars parsedSource: [AssetParsedMarketBar],
        range: AssetChartRange,
        priceChangeBaseline: Double?,
        context: AssetIntradaySessionContext
    ) -> AssetChartRenderInput {
        let indexedSourceBars = indexedInputBars(from: parsedSource)

        guard range == .oneDay else {
            return AssetChartRenderInput(
                bars: indexedSourceBars,
                xDomain: nil,
                priceChangeBaseline: priceChangeBaseline
            )
        }

        guard context.feed == .overnight else {
            if let extendedFallback = extendedSessionFallbackInput(
                from: parsedSource,
                priceChangeBaseline: priceChangeBaseline,
                context: context
            ) {
                return extendedFallback
            }

            return activeSessionInput(
                from: parsedSource,
                priceChangeBaseline: priceChangeBaseline,
                context: context
            ) ?? AssetChartRenderInput(
                bars: indexedSourceBars,
                xDomain: nil,
                priceChangeBaseline: priceChangeBaseline
            )
        }

        let overnightBars = overnightChartBars(
            referenceBar: parsedSource.last,
            context: context
        )
        guard !overnightBars.isEmpty,
              let latestOvernightDate = overnightBars.last?.date else {
            return overnightFallbackInput(
                from: indexedSourceBars,
                priceChangeBaseline: priceChangeBaseline,
                context: context
            ) ?? AssetChartRenderInput(
                bars: indexedSourceBars,
                xDomain: nil,
                priceChangeBaseline: priceChangeBaseline
            )
        }

        let overnightKeys = Set(overnightBars.map(\.minuteKey))
        let dedupedSource = parsedSource.filter { !overnightKeys.contains($0.minuteKey) }
        let sourceInputBars = indexedInputBars(from: dedupedSource)
        let sourceCount = sourceInputBars.count

        let overnightInputBars = overnightBars.map { parsedBar in
            AssetChartInputBar(
                bar: parsedBar.bar,
                date: parsedBar.date,
                xPosition: overnightLatestXPosition(for: parsedBar.date, sourceCount: sourceCount, sessionProgress: context.sessionProgress)
            )
        }

        guard let latestXPosition = overnightInputBars.last?.xPosition else {
            return AssetChartRenderInput(
                bars: indexedSourceBars,
                xDomain: nil,
                priceChangeBaseline: priceChangeBaseline
            )
        }

        let xDomain = overnightXDomain(
            for: latestOvernightDate,
            sourceCount: sourceCount,
            latestXPosition: latestXPosition,
            sessionProgress: context.sessionProgress
        )

        return AssetChartRenderInput(
            bars: sourceInputBars + overnightInputBars,
            xDomain: xDomain,
            priceChangeBaseline: priceChangeBaseline
        )
    }

    static func normalizedBars(_ bars: [AlpacaMarketBar], maxCount: Int = maxRetainedBars) -> [AlpacaMarketBar] {
        // Parse timestamps once before sorting (O(N) parses instead of O(N log N) locked DateFormatter calls).
        let keyed = bars.map { bar in
            (bar: bar, timestamp: AlpacaDateParser.date(bar.timestamp)?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude)
        }
        let sorted = keyed.sorted { $0.timestamp < $1.timestamp }.map(\.bar)
        guard sorted.count > maxCount else {
            return sorted
        }
        return Array(sorted.suffix(maxCount))
    }

    static func minuteKey(for bar: AlpacaMarketBar) -> Int? {
        guard let date = AlpacaDateParser.date(bar.timestamp) else {
            return nil
        }
        return Int(floor(date.timeIntervalSince1970 / 60))
    }

    static func minuteTimestamp(for date: Date) -> Date {
        let interval = floor(date.timeIntervalSince1970 / 60) * 60
        return Date(timeIntervalSince1970: interval)
    }

    static func hasValidMarketPrice(_ price: Double?) -> Bool {
        guard let price else {
            return false
        }
        return price.isFinite && price > 0
    }

    static func activeReferenceInterval(in sessionProgress: MarketSessionProgress?) -> MarketSessionInterval? {
        guard let sessionProgress else {
            return nil
        }

        return sessionProgress.intervals
            .filter { $0.contains(sessionProgress.referenceDate) }
            .min(by: sessionIntervalPrioritySort)
    }

    static func completedExtendedInterval(
        containing date: Date,
        in progress: MarketSessionProgress
    ) -> MarketSessionInterval? {
        progress.intervals
            .filter { interval in
                interval.session.extendedTradingSession != nil
                    && interval.start <= date
                    && date <= interval.end
                    && interval.end <= progress.referenceDate
            }
            .min(by: sessionIntervalPrioritySort)
    }

    static func latestOvernightChartBar(
        referenceBar: AlpacaMarketBar?,
        context: AssetIntradaySessionContext
    ) -> AlpacaMarketBar? {
        let baseBar = context.latestOvernightBar ?? makeSyntheticChartBar(
            symbol: context.symbol,
            price: referenceBar?.close ?? context.latestCoreSessionClose ?? 0,
            timestamp: nil,
            referenceBar: referenceBar,
            latestCoreSessionClose: context.latestCoreSessionClose
        )

        guard let baseBar else {
            return nil
        }

        return applyingLatestRealtimePrice(to: baseBar, context: context)
    }

    // MARK: - Private Helpers

    private static func preParseBars(_ bars: [AlpacaMarketBar]) -> [AssetParsedMarketBar] {
        bars.compactMap(AssetParsedMarketBar.init(bar:))
    }

    private static func indexedInputBars(from parsedBars: [AssetParsedMarketBar]) -> [AssetChartInputBar] {
        parsedBars.enumerated().map { offset, item in
            AssetChartInputBar(bar: item.bar, date: item.date, xPosition: Double(offset))
        }
    }

    private static func overnightFallbackInput(
        from sourceInputBars: [AssetChartInputBar],
        priceChangeBaseline: Double?,
        context: AssetIntradaySessionContext
    ) -> AssetChartRenderInput? {
        guard !sourceInputBars.isEmpty,
              let interval = activeOvernightInterval(
                for: context.sessionProgress?.referenceDate ?? Date(),
                sessionProgress: context.sessionProgress
              ) else {
            return nil
        }

        let sourceCount = sourceInputBars.count
        let totalUnits = oneDaySlotMetrics(for: interval.end, in: interval).totalUnits
        return AssetChartRenderInput(
            bars: sourceInputBars,
            xDomain: 0...max(Double(sourceCount) + totalUnits, Double(sourceCount), 1),
            priceChangeBaseline: priceChangeBaseline
        )
    }

    private static func extendedSessionFallbackInput(
        from parsedBars: [AssetParsedMarketBar],
        priceChangeBaseline: Double?,
        context: AssetIntradaySessionContext
    ) -> AssetChartRenderInput? {
        guard let interval = activeReferenceInterval(in: context.sessionProgress),
              interval.session.usesLatestRegularBarsFallback else {
            return nil
        }

        let baseBars = parsedBars.filter { $0.date < interval.start }
        guard baseBars.count >= 2 else {
            return nil
        }

        let baseInputBars = indexedInputBars(from: baseBars)
        let baseCount = baseInputBars.count
        var overlayInputBars: [AssetChartInputBar] = parsedBars.compactMap { item in
            guard item.date >= interval.start && item.date <= interval.end else {
                return nil
            }

            return AssetChartInputBar(
                bar: item.bar,
                date: item.date,
                xPosition: Double(baseCount) + oneDayXPosition(for: item.date, in: interval)
            )
        }

        if let realtimeInputBar = realtimeActiveSessionInputBar(in: interval, context: context) {
            upsertNewerChartInputBar(
                AssetChartInputBar(
                    bar: realtimeInputBar.bar,
                    date: realtimeInputBar.date,
                    xPosition: Double(baseCount) + realtimeInputBar.xPosition
                ),
                in: &overlayInputBars
            )
        }

        overlayInputBars.sort { lhs, rhs in
            if lhs.xPosition == rhs.xPosition {
                return (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
            }
            return lhs.xPosition < rhs.xPosition
        }

        let totalUnits = oneDaySlotMetrics(for: interval.end, in: interval).totalUnits
        let upperBound = max(
            Double(baseCount) + totalUnits,
            (overlayInputBars.last?.xPosition ?? 0) + 1,
            Double(baseCount),
            1
        )

        return AssetChartRenderInput(
            bars: baseInputBars + overlayInputBars,
            xDomain: 0...upperBound,
            priceChangeBaseline: priceChangeBaseline
        )
    }

    private static func activeSessionInput(
        from parsedBars: [AssetParsedMarketBar],
        priceChangeBaseline: Double?,
        context: AssetIntradaySessionContext
    ) -> AssetChartRenderInput? {
        let latestBarDate = parsedBars.last?.date
        guard let interval = activeNonOvernightInterval(
            for: latestBarDate,
            sessionProgress: context.sessionProgress
        ) else {
            return nil
        }

        var resolvedInputBars: [AssetChartInputBar] = parsedBars.compactMap { item in
            guard item.date >= interval.start && item.date <= interval.end else {
                return nil
            }

            return AssetChartInputBar(
                bar: item.bar,
                date: item.date,
                xPosition: oneDayXPosition(for: item.date, in: interval)
            )
        }

        if let realtimeInputBar = realtimeActiveSessionInputBar(in: interval, context: context) {
            upsertNewerChartInputBar(realtimeInputBar, in: &resolvedInputBars)
        }

        if resolvedInputBars.count < 2,
           let openingInputBar = openingActiveSessionInputBar(
            in: interval,
            inputBars: resolvedInputBars,
            priceChangeBaseline: priceChangeBaseline,
            context: context
           ) {
            appendUniqueChartInputBar(openingInputBar, to: &resolvedInputBars)
        }

        resolvedInputBars.sort { lhs, rhs in
            if lhs.xPosition == rhs.xPosition {
                return (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
            }
            return lhs.xPosition < rhs.xPosition
        }

        guard resolvedInputBars.count >= 2 else {
            return nil
        }

        let totalUnits = oneDaySlotMetrics(for: interval.end, in: interval).totalUnits
        let xDomain = 0...max(totalUnits, (resolvedInputBars.last?.xPosition ?? 0) + 1, 1)

        return AssetChartRenderInput(
            bars: resolvedInputBars,
            xDomain: xDomain,
            priceChangeBaseline: priceChangeBaseline
        )
    }

    private static func realtimeActiveSessionInputBar(
        in interval: MarketSessionInterval,
        context: AssetIntradaySessionContext
    ) -> AssetChartInputBar? {
        guard let realtimePrice = latestRealtimeChartPrice(context: context),
              let realtimeDate = AlpacaDateParser.date(realtimePrice.timestamp),
              realtimeDate >= interval.start,
              realtimeDate <= interval.end else {
            return nil
        }

        let chartDate = minuteTimestamp(for: realtimeDate)
        return AssetChartInputBar(
            bar: AlpacaMarketBar(
                symbol: context.symbol,
                open: realtimePrice.price,
                high: realtimePrice.price,
                low: realtimePrice.price,
                close: realtimePrice.price,
                volume: 0,
                vwap: nil,
                tradeCount: nil,
                timestamp: formatISO8601(chartDate)
            ),
            date: chartDate,
            xPosition: oneDayXPosition(for: chartDate, in: interval)
        )
    }

    private static func openingActiveSessionInputBar(
        in interval: MarketSessionInterval,
        inputBars: [AssetChartInputBar],
        priceChangeBaseline: Double?,
        context: AssetIntradaySessionContext
    ) -> AssetChartInputBar? {
        let price = priceChangeBaseline
            ?? context.previousClose
            ?? inputBars.first?.bar.open
            ?? inputBars.first?.bar.close
            ?? context.dayOpen
            ?? context.latestCoreSessionClose
            ?? context.currentPrice
        guard hasValidMarketPrice(price) else {
            return nil
        }

        return AssetChartInputBar(
            bar: AlpacaMarketBar(
                symbol: context.symbol,
                open: price,
                high: price,
                low: price,
                close: price,
                volume: 0,
                vwap: nil,
                tradeCount: nil,
                timestamp: formatISO8601(interval.start)
            ),
            date: interval.start,
            xPosition: oneDayXPosition(for: interval.start, in: interval)
        )
    }

    private static func upsertNewerChartInputBar(
        _ inputBar: AssetChartInputBar,
        in inputBars: inout [AssetChartInputBar]
    ) {
        guard let inputDate = inputBar.date ?? AlpacaDateParser.date(inputBar.bar.timestamp) else {
            inputBars.append(inputBar)
            return
        }

        let inputKey = Int(floor(inputDate.timeIntervalSince1970 / 60))
        guard let index = inputBars.firstIndex(where: { existing in
            guard let existingDate = existing.date ?? AlpacaDateParser.date(existing.bar.timestamp) else {
                return false
            }
            return Int(floor(existingDate.timeIntervalSince1970 / 60)) == inputKey
        }) else {
            inputBars.append(inputBar)
            return
        }

        let existingDate = inputBars[index].date ?? AlpacaDateParser.date(inputBars[index].bar.timestamp) ?? .distantPast
        if inputDate >= existingDate {
            inputBars[index] = inputBar
        }
    }

    private static func appendUniqueChartInputBar(
        _ inputBar: AssetChartInputBar,
        to inputBars: inout [AssetChartInputBar]
    ) {
        guard let inputDate = inputBar.date ?? AlpacaDateParser.date(inputBar.bar.timestamp) else {
            inputBars.append(inputBar)
            return
        }

        let inputKey = Int(floor(inputDate.timeIntervalSince1970 / 60))
        let exists = inputBars.contains { existing in
            guard let existingDate = existing.date ?? AlpacaDateParser.date(existing.bar.timestamp) else {
                return false
            }
            return Int(floor(existingDate.timeIntervalSince1970 / 60)) == inputKey
        }
        if !exists {
            inputBars.append(inputBar)
        }
    }

    private static func overnightChartBars(
        referenceBar: AssetParsedMarketBar?,
        context: AssetIntradaySessionContext
    ) -> [AssetParsedMarketBar] {
        var barsByKey: [Int: AssetParsedMarketBar] = [:]
        barsByKey.reserveCapacity(context.overnightSupplementEntries.count + 1)

        for entry in context.overnightSupplementEntries {
            if let existing = barsByKey[entry.minuteKey], existing.date > entry.date {
                continue
            }
            barsByKey[entry.minuteKey] = entry
        }

        if let latestBar = latestOvernightChartBar(referenceBar: referenceBar?.bar, context: context) {
            storeOvernightBar(latestBar, in: &barsByKey)
        }

        let referenceDate = referenceBar?.date
        return barsByKey.values
            .filter { item in
                if let referenceDate {
                    return item.date > referenceDate
                }
                return true
            }
            .sorted { $0.date < $1.date }
    }

    private static func storeOvernightBar(_ bar: AlpacaMarketBar, in barsByKey: inout [Int: AssetParsedMarketBar]) {
        guard let candidate = AssetParsedMarketBar(bar: bar) else {
            return
        }
        if let existing = barsByKey[candidate.minuteKey], existing.date > candidate.date {
            return
        }
        barsByKey[candidate.minuteKey] = candidate
    }

    private static func applyingLatestRealtimePrice(
        to baseBar: AlpacaMarketBar,
        context: AssetIntradaySessionContext
    ) -> AlpacaMarketBar {
        guard let realtimePrice = latestRealtimeChartPrice(context: context),
              let realtimeDate = AlpacaDateParser.date(realtimePrice.timestamp),
              let baseDate = AlpacaDateParser.date(baseBar.timestamp),
              realtimeDate >= baseDate else {
            return baseBar
        }

        let realtimeMinute = minuteTimestamp(for: realtimeDate)
        if realtimeMinute == baseDate {
            return AlpacaMarketBar(
                symbol: context.symbol,
                open: baseBar.open,
                high: max(baseBar.high ?? realtimePrice.price, realtimePrice.price),
                low: min(baseBar.low ?? realtimePrice.price, realtimePrice.price),
                close: realtimePrice.price,
                volume: baseBar.volume,
                vwap: baseBar.vwap,
                tradeCount: baseBar.tradeCount,
                timestamp: baseBar.timestamp
            )
        }

        let open = baseBar.close ?? realtimePrice.price
        return AlpacaMarketBar(
            symbol: context.symbol,
            open: open,
            high: max(open, realtimePrice.price),
            low: min(open, realtimePrice.price),
            close: realtimePrice.price,
            volume: 0,
            vwap: nil,
            tradeCount: nil,
            timestamp: formatISO8601(realtimeMinute)
        )
    }

    private static func latestRealtimeChartPrice(
        context: AssetIntradaySessionContext
    ) -> (price: Double, timestamp: String)? {
        let tradePrice: (price: Double, timestamp: String)?
        if let price = context.latestTrade?.price,
           hasValidMarketPrice(price),
           let timestamp = context.latestTrade?.timestamp {
            tradePrice = (price, timestamp)
        } else {
            tradePrice = nil
        }

        let quotePrice: (price: Double, timestamp: String)?
        if let price = chartQuotePrice(context.quote),
           let timestamp = context.quote?.timestamp {
            quotePrice = (price, timestamp)
        } else {
            quotePrice = nil
        }

        return newerChartPrice(preferred: tradePrice, fallback: quotePrice)
    }

    private static func newerChartPrice(
        preferred: (price: Double, timestamp: String)?,
        fallback: (price: Double, timestamp: String)?
    ) -> (price: Double, timestamp: String)? {
        guard let preferred else { return fallback }
        guard let fallback else { return preferred }
        guard let preferredDate = AlpacaDateParser.date(preferred.timestamp) else {
            return AlpacaDateParser.date(fallback.timestamp) == nil ? preferred : fallback
        }
        guard let fallbackDate = AlpacaDateParser.date(fallback.timestamp) else {
            return preferred
        }
        return preferredDate >= fallbackDate ? preferred : fallback
    }

    static func chartQuotePrice(_ quote: AlpacaRealtimeQuote?) -> Double? {
        guard let quote else { return nil }
        switch (hasValidMarketPrice(quote.bidPrice), hasValidMarketPrice(quote.askPrice)) {
        case (true, true):
            return ((quote.bidPrice ?? 0) + (quote.askPrice ?? 0)) / 2
        case (true, false):
            return quote.bidPrice
        case (false, true):
            return quote.askPrice
        case (false, false):
            return nil
        }
    }

    private static func makeSyntheticChartBar(
        symbol: String,
        price: Double,
        timestamp: String?,
        referenceBar: AlpacaMarketBar?,
        latestCoreSessionClose: Double?
    ) -> AlpacaMarketBar? {
        guard price > 0 else { return nil }

        let referenceClose = referenceBar?.close ?? latestCoreSessionClose ?? price
        let timestamp = timestamp ?? formatISO8601(Date())
        let eventDate = AlpacaDateParser.date(timestamp)
        let referenceDate = AlpacaDateParser.date(referenceBar?.timestamp)
        if let eventDate, let referenceDate, eventDate <= referenceDate {
            return nil
        }

        return AlpacaMarketBar(
            symbol: symbol,
            open: referenceClose,
            high: max(referenceClose, price),
            low: min(referenceClose, price),
            close: price,
            volume: 0,
            vwap: nil,
            tradeCount: nil,
            timestamp: timestamp
        )
    }

    private static func overnightLatestXPosition(
        for date: Date,
        sourceCount: Int,
        sessionProgress: MarketSessionProgress?
    ) -> Double {
        guard let interval = activeOvernightInterval(for: date, sessionProgress: sessionProgress) else {
            return Double(sourceCount)
        }
        return Double(sourceCount) + oneDaySlotMetrics(for: date, in: interval).elapsedUnits
    }

    private static func overnightXDomain(
        for date: Date,
        sourceCount: Int,
        latestXPosition: Double,
        sessionProgress: MarketSessionProgress?
    ) -> ClosedRange<Double> {
        let upperBound: Double
        if let interval = activeOvernightInterval(for: date, sessionProgress: sessionProgress) {
            upperBound = Double(sourceCount) + oneDaySlotMetrics(for: date, in: interval).totalUnits
        } else {
            upperBound = latestXPosition + 1
        }
        return 0...max(upperBound, latestXPosition + 1, 1)
    }

    private static func oneDayXPosition(for date: Date, in interval: MarketSessionInterval) -> Double {
        oneDaySlotMetrics(for: date, in: interval).elapsedUnits
    }

    private static func oneDaySlotMetrics(
        for date: Date,
        in interval: MarketSessionInterval
    ) -> (elapsedUnits: Double, totalUnits: Double) {
        let totalSlots = max(
            1.0,
            interval.end.timeIntervalSince(interval.start) / oneDayChartSlotDuration
        )
        let elapsedSlots = date.timeIntervalSince(interval.start) / oneDayChartSlotDuration
        return (min(max(elapsedSlots, 0), totalSlots), totalSlots)
    }

    private static func activeOvernightInterval(
        for date: Date,
        sessionProgress: MarketSessionProgress?
    ) -> MarketSessionInterval? {
        if let containingDate = sessionProgress?.intervals.first(where: {
            $0.session == .overnight && $0.contains(date)
        }) {
            return containingDate
        }
        if let referenceDate = sessionProgress?.referenceDate,
           let containingReference = sessionProgress?.intervals.first(where: {
               $0.session == .overnight && $0.contains(referenceDate)
           }) {
            return containingReference
        }
        return sessionProgress?.intervals.first { $0.session == .overnight }
    }

    private static func activeNonOvernightInterval(
        for date: Date?,
        sessionProgress: MarketSessionProgress?
    ) -> MarketSessionInterval? {
        let intervals = sessionProgress?.intervals.filter { $0.session != .overnight } ?? []
        if let date,
           let containingDate = intervals.filter({
               $0.start <= date && date <= $0.end
           }).min(by: sessionIntervalPrioritySort) {
            return containingDate
        }
        if let referenceDate = sessionProgress?.referenceDate,
           let containingReference = intervals.first(where: { $0.contains(referenceDate) }) {
            return containingReference
        }
        return nil
    }

    private static func sessionIntervalPrioritySort(
        _ lhs: MarketSessionInterval,
        _ rhs: MarketSessionInterval
    ) -> Bool {
        if lhs.session.activePriority == rhs.session.activePriority {
            return lhs.start < rhs.start
        }
        return lhs.session.activePriority < rhs.session.activePriority
    }

    private static func formatISO8601(_ date: Date) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt)
        )
    }
}

extension MarketSessionKind {
    var extendedTradingSession: AssetExtendedTradingSession? {
        switch self {
        case .overnight:
            .overnight
        case .preMarket:
            .preMarket
        case .afterHours:
            .afterHours
        case .regular:
            nil
        }
    }
}
