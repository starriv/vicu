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

    func queryItems(accountCreatedAt: String?) -> [URLQueryItem] {
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
        case .oneMonth:
            return [
                URLQueryItem(name: "period", value: "1M"),
                URLQueryItem(name: "timeframe", value: "1D")
            ]
        case .threeMonths:
            return [
                URLQueryItem(name: "period", value: "3M"),
                URLQueryItem(name: "timeframe", value: "1D")
            ]
        case .oneYear:
            return [
                URLQueryItem(name: "period", value: "1A"),
                URLQueryItem(name: "timeframe", value: "1D")
            ]
        case .yearToDate:
            return [
                URLQueryItem(name: "start", value: Self.yearToDateStart()),
                URLQueryItem(name: "timeframe", value: "1D")
            ]
        }
    }

    private static func yearToDateStart(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        let year = calendar.component(.year, from: now)
        let start = calendar.date(
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

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: start)
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

        return timestamp.indices.compactMap { index -> PortfolioHistoryPoint? in
            guard index < equity.count, let value = equity[index] else {
                return nil
            }

            return PortfolioHistoryPoint(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp[index])),
                equity: value,
                profitLoss: optionalValue(at: index, in: profitLoss),
                profitLossPercent: optionalValue(at: index, in: profitLossPct)
            )
        }
    }

    private func optionalValue(at index: Int, in values: [Double?]?) -> Double? {
        guard let values, index < values.count else {
            return nil
        }
        return values[index]
    }
}

struct PortfolioHistoryPoint: Codable, Identifiable, Equatable, Sendable {
    let date: Date
    let equity: Double
    let profitLoss: Double?
    let profitLossPercent: Double?

    var id: Date { date }
}
