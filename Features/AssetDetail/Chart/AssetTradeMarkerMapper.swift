import Foundation

/// Lightweight, normalized trade execution extracted from a filled or partially-filled `AlpacaOrder`.
struct AssetTradeExecution: Equatable, Hashable, Sendable {
    let id: String
    let symbol: String
    let side: FinancialChartTradeSide
    let executedAt: Date
    let quantity: Double
    let price: Double
}

/// Pre-indexed set of chart trade markers for O(1) SwiftUI body evaluation and O(1) 120Hz scrubbing lookups.
struct AssetChartTradeMarkerSet: Equatable, Sendable {
    let markers: [FinancialChartTradeMarker]
    let digest: Int
    private let markersByTimestamp: [TimeInterval: [FinancialChartTradeMarker]]

    static let empty = AssetChartTradeMarkerSet(markers: [])

    init(markers: [FinancialChartTradeMarker]) {
        self.markers = markers
        self.digest = FinancialChartSeries.tradeMarkersDigest(for: markers)
        var byTimestamp: [TimeInterval: [FinancialChartTradeMarker]] = [:]
        byTimestamp.reserveCapacity(markers.count)
        for marker in markers {
            byTimestamp[marker.barDate.timeIntervalSince1970, default: []].append(marker)
        }
        self.markersByTimestamp = byTimestamp
    }

    var isEmpty: Bool {
        markers.isEmpty
    }

    /// O(1) lookup for exact bar match (line/area/non-aggregated candles), with O(log M) fallback
    /// for aggregated candlestick buckets whose `point.x` spans multiple raw bars.
    func markers(for point: AssetChartPoint, xTolerance: Double = 0.55) -> [FinancialChartTradeMarker] {
        guard !markers.isEmpty else {
            return []
        }

        if let exact = markersByTimestamp[point.date.timeIntervalSince1970] {
            return exact
        }

        guard xTolerance > 0 else {
            return []
        }

        let targetX = point.xPosition
        var low = 0
        var high = markers.count
        while low < high {
            let mid = (low + high) / 2
            if markers[mid].x < targetX - xTolerance {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var matched: [FinancialChartTradeMarker] = []
        var idx = low
        while idx < markers.count && markers[idx].x <= targetX + xTolerance {
            matched.append(markers[idx])
            idx += 1
        }
        return matched
    }
}

/// Pure, testable mapper turning filled Alpaca orders into bar-anchored chart trade markers
/// for non-intraday timeframes (`1W`, `1M`, `3M`, `1Y`, `YTD`).
enum AssetTradeMarkerMapper {
    static let historyLookbackDays = 400

    private static let nyTimeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3600) ?? .gmt

    static func historyStartDate(now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = nyTimeZone
        return calendar.date(byAdding: .day, value: -historyLookbackDays, to: now) ?? now.addingTimeInterval(-Double(historyLookbackDays) * 86_400)
    }

    /// Extracts executed fills for `symbol` from raw Alpaca orders (including any nested legs).
    static func executions(from orders: [AlpacaOrder], symbol: String) -> [AssetTradeExecution] {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty, !orders.isEmpty else {
            return []
        }

        var flattened: [AlpacaOrder] = []
        flattened.reserveCapacity(orders.count)
        var seenIDs = Set<String>()

        func collect(_ list: [AlpacaOrder]) {
            for order in list {
                if seenIDs.insert(order.id).inserted {
                    flattened.append(order)
                }
                if let legs = order.legs, !legs.isEmpty {
                    collect(legs)
                }
            }
        }
        collect(orders)

        var results: [AssetTradeExecution] = []
        results.reserveCapacity(flattened.count)

        for order in flattened {
            guard order.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedSymbol else {
                continue
            }

            let rawSide = order.side?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let side: FinancialChartTradeSide
            switch rawSide {
            case "buy":
                side = .buy
            case "sell":
                side = .sell
            default:
                continue
            }

            guard let qtyText = order.filledQuantity,
                  let qty = Double(qtyText),
                  qty.isFinite, qty > 0,
                  let priceText = order.filledAveragePrice,
                  let price = Double(priceText),
                  price.isFinite, price > 0 else {
                continue
            }

            let status = order.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let executedAt: Date?
            if let filledDate = AlpacaDateParser.date(order.filledAt) {
                executedAt = filledDate
            } else if status == "filled" || status == "partially_filled" {
                executedAt = AlpacaDateParser.date(order.updatedAt)
            } else {
                executedAt = nil
            }

            guard let executedAt else {
                continue
            }

            results.append(
                AssetTradeExecution(
                    id: order.id,
                    symbol: normalizedSymbol,
                    side: side,
                    executedAt: executedAt,
                    quantity: qty,
                    price: price
                )
            )
        }

        results.sort { lhs, rhs in
            if lhs.executedAt == rhs.executedAt {
                return lhs.id < rhs.id
            }
            return lhs.executedAt < rhs.executedAt
        }
        return results
    }

    /// Projects normalized executions onto non-intraday chart bars, aggregating multiple same-side fills
    /// on the same bar with volume-weighted average execution price.
    static func map(
        executions: [AssetTradeExecution],
        onto points: [FinancialChartPoint],
        range: AssetChartRange
    ) -> AssetChartTradeMarkerSet {
        guard range != .oneDay, !executions.isEmpty, !points.isEmpty else {
            return .empty
        }

        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = nyTimeZone

        // Pre-build O(1) day-key lookup for daily timeframes (1M / 3M / YTD)
        var dailyIndexByKey: [Int: Int] = [:]
        let isDailyRange = range == .oneMonth || range == .threeMonths || range == .yearToDate
        if isDailyRange {
            dailyIndexByKey.reserveCapacity(points.count)
            for (index, point) in points.enumerated() {
                dailyIndexByKey[nyDayKey(for: point.date, calendar: nyCalendar)] = index
            }
        }

        struct BucketKey: Hashable {
            let barIndex: Int
            let side: FinancialChartTradeSide
        }

        struct BucketAccumulator {
            var totalQuantity: Double = 0
            var weightedPriceSum: Double = 0
            var fillCount: Int = 0
        }

        var buckets: [BucketKey: BucketAccumulator] = [:]

        for execution in executions {
            let matchedIndex: Int?
            if isDailyRange {
                matchedIndex = matchDailyBarIndex(
                    for: execution.executedAt,
                    in: points,
                    dayIndexByKey: dailyIndexByKey,
                    calendar: nyCalendar
                )
            } else if range == .oneYear {
                matchedIndex = matchWeeklyBarIndex(
                    for: execution.executedAt,
                    in: points,
                    calendar: nyCalendar
                )
            } else {
                // .oneWeek (15Min bars)
                matchedIndex = matchFifteenMinuteBarIndex(
                    for: execution.executedAt,
                    in: points
                )
            }

            guard let barIndex = matchedIndex else {
                continue
            }

            let key = BucketKey(barIndex: barIndex, side: execution.side)
            var acc = buckets[key] ?? BucketAccumulator()
            acc.totalQuantity += execution.quantity
            acc.weightedPriceSum += execution.quantity * execution.price
            acc.fillCount += 1
            buckets[key] = acc
        }

        guard !buckets.isEmpty else {
            return .empty
        }

        let sortedEntries = buckets.sorted { lhs, rhs in
            if lhs.key.barIndex == rhs.key.barIndex {
                return lhs.key.side == .buy && rhs.key.side == .sell
            }
            return lhs.key.barIndex < rhs.key.barIndex
        }

        var markers: [FinancialChartTradeMarker] = []
        markers.reserveCapacity(sortedEntries.count)

        for (key, acc) in sortedEntries {
            guard acc.totalQuantity > 0 else { continue }
            let bar = points[key.barIndex]
            let avgPrice = acc.weightedPriceSum / acc.totalQuantity
            markers.append(
                FinancialChartTradeMarker(
                    id: "\(key.barIndex)-\(key.side.rawValue)-\(Int(bar.timestamp))",
                    side: key.side,
                    x: bar.x,
                    barDate: bar.date,
                    averagePrice: avgPrice,
                    totalQuantity: acc.totalQuantity,
                    fillCount: acc.fillCount,
                    barClose: bar.close,
                    barHigh: bar.high,
                    barLow: bar.low
                )
            )
        }

        return AssetChartTradeMarkerSet(markers: markers)
    }

    // MARK: - Bar Index Matching

    private static func nyDayKey(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }

    private static func matchDailyBarIndex(
        for date: Date,
        in points: [FinancialChartPoint],
        dayIndexByKey: [Int: Int],
        calendar: Calendar
    ) -> Int? {
        let key = nyDayKey(for: date, calendar: calendar)
        if let exact = dayIndexByKey[key] {
            return exact
        }

        guard let first = points.first, let last = points.last else {
            return nil
        }

        // Reject executions outside the displayed calendar span (with 1-day margin on right for same-day after-hours/overnight).
        let firstDayStart = calendar.startOfDay(for: first.date)
        let lastDayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last.date)) ?? last.date.addingTimeInterval(86_400)
        guard date >= firstDayStart && date <= lastDayEnd else {
            return nil
        }

        // Overnight / Sunday session execution inside the range snaps to nearest trading day bar within 48h.
        let idx = nearestDateIndex(for: date, in: points)
        if abs(points[idx].date.timeIntervalSince(date)) <= 48 * 3600 {
            return idx
        }
        return nil
    }

    private static func matchWeeklyBarIndex(
        for date: Date,
        in points: [FinancialChartPoint],
        calendar: Calendar
    ) -> Int? {
        guard let first = points.first, let last = points.last else {
            return nil
        }

        let firstDayStart = calendar.startOfDay(for: first.date)
        let maxEnd = last.date.addingTimeInterval(7 * 86_400)
        guard date >= firstDayStart && date <= maxEnd else {
            return nil
        }

        if date < first.date {
            return 0
        }

        let idx = lastIndexAtOrBefore(date, in: points)
        return idx
    }

    private static func matchFifteenMinuteBarIndex(
        for date: Date,
        in points: [FinancialChartPoint]
    ) -> Int? {
        guard let first = points.first, let last = points.last else {
            return nil
        }

        // Allow 15min pre-margin on left and extended-hours margin on right of the latest bar.
        let lowerBound = first.date.addingTimeInterval(-15 * 60)
        let upperBound = last.date.addingTimeInterval(20 * 3600)
        guard date >= lowerBound && date <= upperBound else {
            return nil
        }

        if date <= first.date {
            return 0
        }

        let idx = lastIndexAtOrBefore(date, in: points)
        if idx + 1 < points.count {
            let deltaPrev = abs(date.timeIntervalSince(points[idx].date))
            let deltaNext = abs(points[idx + 1].date.timeIntervalSince(date))
            // If fill fell cleanly within the 15Min bar starting at points[idx], anchor to idx.
            if deltaPrev <= 15 * 60 {
                return idx
            }
            // Otherwise (e.g., after-hours / pre-market gap between regular sessions), snap to closer bar.
            return deltaPrev <= deltaNext ? idx : (idx + 1)
        }
        return idx
    }

    private static func lastIndexAtOrBefore(_ date: Date, in points: [FinancialChartPoint]) -> Int {
        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date <= date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(low - 1, 0)
    }

    private static func nearestDateIndex(for date: Date, in points: [FinancialChartPoint]) -> Int {
        let idx = lastIndexAtOrBefore(date, in: points)
        guard idx + 1 < points.count else {
            return idx
        }
        let d0 = abs(date.timeIntervalSince(points[idx].date))
        let d1 = abs(points[idx + 1].date.timeIntervalSince(date))
        return d0 <= d1 ? idx : (idx + 1)
    }
}
