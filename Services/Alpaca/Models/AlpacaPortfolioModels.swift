import Foundation

enum PortfolioHistoryRange: String, Codable, CaseIterable, Identifiable, Sendable {
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

    var cacheFreshTTL: TimeInterval {
        switch self {
        case .oneDay:
            30
        case .oneWeek, .oneMonth, .threeMonths, .oneYear, .yearToDate:
            60
        }
    }

    var usesCalendarWindowDomain: Bool {
        switch self {
        case .oneDay:
            false
        case .oneWeek, .oneMonth, .threeMonths, .oneYear, .yearToDate:
            true
        }
    }

    func queryItems(accountCreatedAt: String?, now: Date = Date()) -> [URLQueryItem] {
        switch self {
        case .oneDay:
            return [
                URLQueryItem(name: "period", value: "1D"),
                URLQueryItem(name: "timeframe", value: "5Min"),
                URLQueryItem(name: "intraday_reporting", value: "continuous")
            ]
        case .oneWeek:
            return [
                URLQueryItem(name: "period", value: "1W"),
                URLQueryItem(name: "timeframe", value: "1H"),
                URLQueryItem(name: "intraday_reporting", value: "continuous"),
                URLQueryItem(name: "pnl_reset", value: "no_reset")
            ]
        case .oneMonth, .threeMonths, .oneYear, .yearToDate:
            let window = calendarWindow(now: now)
            return [
                URLQueryItem(name: "start", value: Self.isoDateTimeString(from: window.lowerBound)),
                URLQueryItem(name: "end", value: Self.isoDateTimeString(from: window.upperBound)),
                URLQueryItem(name: "timeframe", value: "1D"),
                URLQueryItem(name: "pnl_reset", value: "no_reset")
            ]
        }
    }

    /// Returns the authoritative calendar window `[start ... end]` in `America/New_York` time.
    func calendarWindow(now: Date = Date()) -> ClosedRange<Date> {
        let calendar = Self.newYorkCalendar
        let safeEnd = now

        let start: Date
        switch self {
        case .oneDay:
            start = calendar.date(byAdding: .day, value: -1, to: safeEnd) ?? safeEnd.addingTimeInterval(-86_400)
        case .oneWeek:
            start = calendar.date(byAdding: .day, value: -7, to: safeEnd) ?? safeEnd.addingTimeInterval(-7 * 86_400)
        case .oneMonth:
            start = calendar.date(byAdding: .month, value: -1, to: safeEnd) ?? safeEnd.addingTimeInterval(-30 * 86_400)
        case .threeMonths:
            start = calendar.date(byAdding: .month, value: -3, to: safeEnd) ?? safeEnd.addingTimeInterval(-90 * 86_400)
        case .oneYear:
            start = calendar.date(byAdding: .year, value: -1, to: safeEnd) ?? safeEnd.addingTimeInterval(-365 * 86_400)
        case .yearToDate:
            let year = calendar.component(.year, from: safeEnd)
            let jan1 = calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: year,
                    month: 1,
                    day: 1,
                    hour: 0,
                    minute: 0,
                    second: 0
                )
            ) ?? safeEnd
            start = jan1
        }

        if safeEnd <= start {
            return start...(start.addingTimeInterval(86_400))
        }
        return start...safeEnd
    }

    static var newYorkTimeZone: TimeZone {
        TimeZone(identifier: "America/New_York") ?? .current
    }

    static var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYorkTimeZone
        return calendar
    }

    private static func isoDateTimeString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = newYorkTimeZone
        return formatter.string(from: date)
    }
}

struct AlpacaPortfolioHistory: Decodable, Sendable {
    let timestamp: [Int]?
    let equity: [Double?]?
    let profitLoss: [Double?]?
    let profitLossPct: [Double?]?
    let baseValue: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case equity
        case profitLoss = "profit_loss"
        case profitLossPct = "profit_loss_pct"
        case baseValue = "base_value"
    }

    func points() -> [PortfolioHistoryPoint] {
        guard let timestamp, let equity else { return [] }

        var byTimestamp: [Int: PortfolioHistoryPoint] = [:]
        byTimestamp.reserveCapacity(min(timestamp.count, equity.count))

        for index in timestamp.indices {
            guard index < equity.count,
                  let value = equity[index],
                  value.isFinite else {
                continue
            }

            let rawTimestamp = timestamp[index]
            byTimestamp[rawTimestamp] = PortfolioHistoryPoint(
                date: Date(timeIntervalSince1970: TimeInterval(rawTimestamp)),
                equity: value,
                profitLoss: optionalFiniteValue(at: index, in: profitLoss),
                profitLossPercent: optionalFiniteValue(at: index, in: profitLossPct)
            )
        }

        return byTimestamp.values.sorted { $0.date < $1.date }
    }

    private func optionalFiniteValue(at index: Int, in values: [Double?]?) -> Double? {
        guard let values, index < values.count, let value = values[index], value.isFinite else {
            return nil
        }
        return value
    }
}

struct PortfolioHistoryPoint: Codable, Identifiable, Equatable, Sendable {
    let date: Date
    let equity: Double
    let profitLoss: Double?
    let profitLossPercent: Double?

    var id: Date { date }
}
