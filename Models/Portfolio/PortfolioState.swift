import Foundation

struct PortfolioState: Sendable {
    var account: AlpacaAccount?
    var positions: [AlpacaPosition] = []
    var orders: [AlpacaOrder] = []
    var historyRange: PortfolioHistoryRange = .oneDay
    var history: [PortfolioHistoryPoint] = []
    var historyLoadedRange: PortfolioHistoryRange?
    var historyByRange: [PortfolioHistoryRange: [PortfolioHistoryPoint]] = [:]
    var historyUpdatedAtByRange: [PortfolioHistoryRange: Date] = [:]
    var isRefreshing = false
    var isLoadingHistory = false
    var hasLoadedAccount = false
    var hasLoadedPositions = false
    var hasLoadedOrders = false
    var hasLoadedHistory = false

    func displayedHistory(for range: PortfolioHistoryRange) -> [PortfolioHistoryPoint] {
        if let cached = historyByRange[range] {
            return cached
        }
        if historyLoadedRange == range {
            return history
        }
        return []
    }

    func isHistoryFresh(for range: PortfolioHistoryRange, now: Date = Date()) -> Bool {
        guard let updatedAt = historyUpdatedAtByRange[range],
              historyByRange[range] != nil else {
            return false
        }
        return now.timeIntervalSince(updatedAt) < range.cacheFreshTTL
    }

    mutating func applySnapshot(
        account: AlpacaAccount,
        positions: [AlpacaPosition],
        orders: [AlpacaOrder],
        history: [PortfolioHistoryPoint]
    ) {
        self.account = account
        self.positions = positions
        self.orders = orders
        applyHistory(history, for: historyRange)
        hasLoadedAccount = true
        hasLoadedPositions = true
        hasLoadedOrders = true
    }

    mutating func applyAccount(_ account: AlpacaAccount) {
        self.account = account
        hasLoadedAccount = true
    }

    mutating func applyPositions(_ positions: [AlpacaPosition]) {
        self.positions = positions
        hasLoadedPositions = true
    }

    mutating func applyOrders(_ orders: [AlpacaOrder]) {
        self.orders = orders
        hasLoadedOrders = true
    }

    mutating func applyHistory(
        _ history: [PortfolioHistoryPoint],
        for range: PortfolioHistoryRange? = nil,
        at timestamp: Date = Date()
    ) {
        let targetRange = range ?? historyRange
        historyByRange[targetRange] = history
        historyUpdatedAtByRange[targetRange] = timestamp
        if historyRange == targetRange {
            self.history = history
            self.historyLoadedRange = targetRange
            self.hasLoadedHistory = true
        }
    }

    mutating func selectHistoryRange(_ range: PortfolioHistoryRange) {
        historyRange = range
        if let cached = historyByRange[range] {
            history = cached
            historyLoadedRange = range
            hasLoadedHistory = true
        }
    }

    mutating func prepareForRefresh() {
        isRefreshing = true
        if displayedHistory(for: historyRange).isEmpty {
            isLoadingHistory = true
        }
    }

    mutating func clear() {
        isRefreshing = false
        isLoadingHistory = false
        account = nil
        positions = []
        orders = []
        history = []
        historyLoadedRange = nil
        historyByRange = [:]
        historyUpdatedAtByRange = [:]
        hasLoadedAccount = false
        hasLoadedPositions = false
        hasLoadedOrders = false
        hasLoadedHistory = false
    }
}

struct NormalizedPortfolioHistoryPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let equity: Double
    let profitLoss: Double?
    let profitLossPercent: Double?

    var id: Date { date }
}

enum PortfolioEquitySeriesNormalizer {
    static func liveAccountEquity(from account: AlpacaAccount?) -> Double? {
        if let portfolioValue = NumberParser.double(from: account?.portfolioValue), portfolioValue.isFinite {
            return portfolioValue
        }
        if let equity = NumberParser.double(from: account?.equity), equity.isFinite {
            return equity
        }
        return nil
    }

    static func normalize(
        history: [PortfolioHistoryPoint],
        account: AlpacaAccount?,
        range: PortfolioHistoryRange = .oneDay,
        now: Date = Date()
    ) -> [NormalizedPortfolioHistoryPoint] {
        guard !history.isEmpty else {
            return []
        }

        let liveEquity = liveAccountEquity(from: account)
        let offset = range == .oneDay
            ? inferredIntradayBaselineOffset(history: history, liveEquity: liveEquity)
            : 0
        let firstNormalizedEquity = history[0].equity + offset

        var normalized = history.map { point in
            let normalizedEquity = point.equity + offset
            let resolvedPL = point.profitLoss.flatMap { $0.isFinite ? $0 : nil }
            let resolvedPLPct: Double?
            if let existingPct = point.profitLossPercent, existingPct.isFinite {
                resolvedPLPct = existingPct
            } else if range == .oneDay, firstNormalizedEquity > 0, let resolvedPL {
                resolvedPLPct = resolvedPL / firstNormalizedEquity
            } else {
                resolvedPLPct = nil
            }

            return NormalizedPortfolioHistoryPoint(
                date: point.date,
                equity: normalizedEquity,
                profitLoss: resolvedPL,
                profitLossPercent: resolvedPLPct
            )
        }

        // For multi-day calendar-window ranges (1W/1M/3M/1Y/YTD), keep the trailing edge
        // synchronized with live account equity without drawing diagonal ramps across unfunded
        // gaps, dropping recent deposits during overnight/post-close windows, or duplicating today's bar.
        if range.usesCalendarWindowDomain,
           let liveEquity,
           let lastPoint = normalized.last {
            let nyCalendar = PortfolioHistoryRange.newYorkCalendar
            let parsedLastEquity = NumberParser.double(from: account?.lastEquity)
            let hasMaterialEquityDiff = abs(liveEquity - lastPoint.equity) > 0.01
            let isAtOrAheadOfNow = lastPoint.date >= now
            let isSameOrFutureNYDay = isAtOrAheadOfNow ||
                (range != .oneWeek && nyCalendar.isDate(lastPoint.date, inSameDayAs: now))

            if isSameOrFutureNYDay {
                // If yesterday's bar is still stale $0 while Alpaca already settled lastEquity > 0,
                // reflect yesterday's deposit on yesterday's bar before updating today's bar.
                if hasMaterialEquityDiff,
                   let settledYesterday = parsedLastEquity,
                   settledYesterday > 0,
                   normalized.count >= 2,
                   normalized[normalized.count - 2].equity <= 0.01 {
                    let prevBar = normalized[normalized.count - 2]
                    let yesterdayRef = nyCalendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-24 * 3600)
                    if nyCalendar.isDate(prevBar.date, inSameDayAs: yesterdayRef) {
                        normalized[normalized.count - 2] = NormalizedPortfolioHistoryPoint(
                            date: prevBar.date,
                            equity: settledYesterday,
                            profitLoss: prevBar.profitLoss,
                            profitLossPercent: prevBar.profitLossPercent
                        )
                    }
                }

                // Live equity includes cash transfers. Keep the broker's last reported P/L.
                normalized[normalized.count - 1] = NormalizedPortfolioHistoryPoint(
                    date: max(lastPoint.date, now),
                    equity: liveEquity,
                    profitLoss: lastPoint.profitLoss,
                    profitLossPercent: lastPoint.profitLossPercent
                )
            } else if now.timeIntervalSince(lastPoint.date) > 6 * 3600 || hasMaterialEquityDiff {
                let oneDay: TimeInterval = 24 * 3600
                let hasSettledYesterdayEquity = (parsedLastEquity ?? 0) > 0 && lastPoint.equity <= 0.01
                let yesterdayRef = nyCalendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-oneDay)
                let lastPointIsStaleYesterdayBar = hasSettledYesterdayEquity &&
                    normalized.count >= 2 &&
                    nyCalendar.isDate(lastPoint.date, inSameDayAs: yesterdayRef)

                if lastPointIsStaleYesterdayBar, let settledYesterday = parsedLastEquity {
                    // Alpaca's daily/hourly bar for yesterday (e.g. 20:00 ET) has not reflected yesterday's
                    // deposit yet while account.lastEquity already has it: update yesterday's bar in place
                    // so the deposit step lands accurately on yesterday before stepping to today's live equity.
                    normalized[normalized.count - 1] = NormalizedPortfolioHistoryPoint(
                        date: lastPoint.date,
                        equity: settledYesterday,
                        profitLoss: lastPoint.profitLoss,
                        profitLossPercent: lastPoint.profitLossPercent
                    )
                } else {
                    let carryCutoff = now.addingTimeInterval(hasSettledYesterdayEquity ? -2 * oneDay : -oneDay)

                    if carryCutoff.timeIntervalSince(lastPoint.date) > 12 * 3600 {
                        // Insert flat carry-forward points across multi-day gaps so scrubbing stays
                        // smooth and reflects the true historical balance before a recent deposit.
                        let step: TimeInterval = range == .oneWeek ? oneDay : 7 * oneDay
                        var cursor = lastPoint.date.addingTimeInterval(step)
                        while cursor < carryCutoff {
                            if cursor > (normalized.last?.date ?? .distantPast) {
                                normalized.append(
                                    NormalizedPortfolioHistoryPoint(
                                        date: cursor,
                                        equity: lastPoint.equity,
                                        profitLoss: lastPoint.profitLoss,
                                        profitLossPercent: lastPoint.profitLossPercent
                                    )
                                )
                            }
                            cursor = cursor.addingTimeInterval(step)
                        }
                        if carryCutoff > (normalized.last?.date ?? .distantPast) {
                            normalized.append(
                                NormalizedPortfolioHistoryPoint(
                                    date: carryCutoff,
                                    equity: lastPoint.equity,
                                    profitLoss: lastPoint.profitLoss,
                                    profitLossPercent: lastPoint.profitLossPercent
                                )
                            )
                        }
                    }

                    if hasSettledYesterdayEquity, let settledYesterday = parsedLastEquity {
                        let yesterdayDate = now.addingTimeInterval(-oneDay)
                        if yesterdayDate > (normalized.last?.date ?? .distantPast) && yesterdayDate < now {
                            normalized.append(
                                NormalizedPortfolioHistoryPoint(
                                    date: yesterdayDate,
                                    equity: settledYesterday,
                                    profitLoss: lastPoint.profitLoss,
                                    profitLossPercent: lastPoint.profitLossPercent
                                )
                            )
                        }
                    }
                }

                if now > (normalized.last?.date ?? .distantPast) {
                    normalized.append(
                        NormalizedPortfolioHistoryPoint(
                            date: now,
                            equity: liveEquity,
                            profitLoss: lastPoint.profitLoss,
                            profitLossPercent: lastPoint.profitLossPercent
                        )
                    )
                }
            }
        }

        return normalized
    }

    /// Detects Alpaca `1D` `/v2/account/portfolio/history` responses where `equity` is reported
    /// as 0-based intraday P/L rather than total account equity, and returns the missing
    /// baseline offset. Never shifts multi-day histories or flat all-zero pre-funding histories.
    static func inferredIntradayBaselineOffset(
        history: [PortfolioHistoryPoint],
        liveEquity: Double?
    ) -> Double {
        guard let liveEquity, liveEquity > 0,
              let first = history.first,
              let last = history.last else {
            return 0
        }

        // Require actual intraday variation so an all-zero pre-funding series is never shifted into a fake flat line.
        let hasVariation = history.contains { abs($0.equity - first.equity) > 0.001 }
        guard hasVariation else {
            return 0
        }

        let gap = liveEquity - last.equity
        guard gap > max(1.0, liveEquity * 0.15) else {
            return 0
        }

        let firstIsZeroBasedOrPL: Bool = {
            if let firstPL = first.profitLoss, firstPL.isFinite {
                return abs(first.equity - firstPL) <= max(1.0, abs(firstPL) * 0.05)
            }
            return first.equity <= 0.01
        }()

        let lastIsZeroBasedOrPL: Bool = {
            if let lastPL = last.profitLoss, lastPL.isFinite {
                return abs(last.equity - lastPL) <= max(1.0, abs(lastPL) * 0.05)
            }
            return abs(last.equity) <= 0.01
        }()

        guard firstIsZeroBasedOrPL && lastIsZeroBasedOrPL else {
            return 0
        }

        return gap
    }
}

enum PortfolioChartTimeline {
    static func xDomain(
        for range: PortfolioHistoryRange,
        dates: [Date],
        now: Date = Date()
    ) -> ClosedRange<Double> {
        let firstDate = dates.first
        let lastDate = dates.last

        if !range.usesCalendarWindowDomain {
            guard let firstDate, let lastDate, lastDate > firstDate else {
                let anchor = (firstDate ?? now).timeIntervalSince1970
                return anchor...(anchor + 1)
            }
            return firstDate.timeIntervalSince1970...lastDate.timeIntervalSince1970
        }

        let referenceNow = max(now, lastDate ?? now)
        let window = range.calendarWindow(now: referenceNow)
        let lower = min(window.lowerBound, firstDate ?? window.lowerBound).timeIntervalSince1970
        let upper = max(window.upperBound, lastDate ?? window.upperBound).timeIntervalSince1970
        return lower...max(upper, lower + 1)
    }

    /// Computes axis tick labels aligned exactly to the slot centers of `xDomain`
    /// so every label matches the crosshair timestamp directly above it.
    static func axisLabels(
        for range: PortfolioHistoryRange,
        dates: [Date],
        now: Date = Date(),
        locale: Locale = .current
    ) -> [String] {
        let domain = xDomain(for: range, dates: dates, now: now)
        let span = domain.upperBound - domain.lowerBound
        guard span > 1 else {
            return []
        }

        let slotCount: Int
        switch range {
        case .oneDay, .oneWeek, .oneMonth, .threeMonths:
            slotCount = 5
        case .oneYear:
            slotCount = 6
        case .yearToDate:
            let nyCalendar = PortfolioHistoryRange.newYorkCalendar
            let currentMonth = max(1, min(12, nyCalendar.component(.month, from: Date(timeIntervalSince1970: domain.upperBound))))
            if currentMonth == 1 {
                slotCount = 5
            } else {
                slotCount = currentMonth <= 6 ? currentMonth : 6
            }
        }

        let referenceEndDate = Date(timeIntervalSince1970: domain.upperBound)
        let labels = (0..<slotCount).map { slot -> String in
            let fraction: Double
            if slotCount <= 1 {
                fraction = 0.5
            } else {
                // Span from 5% to 95% so edge labels land accurately on the starting & current month/date.
                fraction = 0.05 + 0.90 * (Double(slot) / Double(slotCount - 1))
            }
            let timestamp = domain.lowerBound + span * fraction
            let date = Date(timeIntervalSince1970: timestamp)
            return formatTick(
                date: date,
                range: range,
                referenceEndDate: referenceEndDate,
                locale: locale
            )
        }

        return deduped(labels)
    }

    private static func formatTick(
        date: Date,
        range: PortfolioHistoryRange,
        referenceEndDate: Date,
        locale: Locale
    ) -> String {
        switch range {
        case .oneDay:
            return formatTime(date)
        case .oneWeek:
            // Keep 1W axis ticks in device local time to match 1W hourly crosshair timestamps.
            return formatMonthDay(date, timeZone: .current)
        case .oneMonth, .threeMonths:
            return formatMonthDay(date, timeZone: PortfolioHistoryRange.newYorkTimeZone)
        case .oneYear:
            return formatYearMonth(date)
        case .yearToDate:
            let nyCalendar = PortfolioHistoryRange.newYorkCalendar
            if nyCalendar.component(.month, from: date) == 1 &&
                nyCalendar.component(.month, from: referenceEndDate) == 1 {
                return formatMonthDay(date, timeZone: PortfolioHistoryRange.newYorkTimeZone)
            }
            return formatShortMonth(date, locale: locale)
        }
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func formatMonthDay(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private static func formatYearMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = PortfolioHistoryRange.newYorkTimeZone
        formatter.dateFormat = "yy/MM"
        return formatter.string(from: date)
    }

    private static func formatShortMonth(_ date: Date, locale: Locale) -> String {
        let resolvedLocale = AppLocale.resolvedLocale(for: locale)
        let formatter = DateFormatter()
        formatter.locale = resolvedLocale
        formatter.timeZone = PortfolioHistoryRange.newYorkTimeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private static func deduped(_ labels: [String]) -> [String] {
        var result: [String] = []
        for label in labels where !label.isEmpty && result.last != label {
            result.append(label)
        }
        return result
    }
}
