import Foundation

struct MarketOverview: Codable, Sendable {
    let clock: AlpacaMarketClock
    let calendar: [AlpacaCalendarDay]
    let overnightCalendar: [AlpacaCalendarDay]
    let indexQuotes: [MarketIndexQuote]
    let gainers: [MarketMover]
    let losers: [MarketMover]
    let mostActive: [MarketActiveSymbol]

    var isEmpty: Bool {
        indexQuotes.isEmpty && gainers.isEmpty && losers.isEmpty && mostActive.isEmpty
    }

    func nextCoreOpen() -> String? {
        nextCalendarValue(\.coreStart)
    }

    func nextCoreClose() -> String? {
        nextCalendarValue(\.coreEnd)
    }

    private func nextCalendarValue(_ keyPath: KeyPath<AlpacaCalendarDay, String>) -> String? {
        let referenceDate = AlpacaDateParser.date(clock.timestamp) ?? Date()
        return calendar
            .compactMap { day -> (value: String, date: Date)? in
                let value = day[keyPath: keyPath]
                guard let date = AlpacaDateParser.date(value), date > referenceDate else {
                    return nil
                }

                return (value, date)
            }
            .min { $0.date < $1.date }?
            .value
    }
}

struct AlpacaMarketCalendarResponse: Decodable, Sendable {
    let calendar: [AlpacaCalendarDay]
}

struct AlpacaCalendarDay: Codable, Identifiable, Sendable {
    let date: String
    let coreStart: String
    let coreEnd: String
    let preStart: String?
    let preEnd: String?
    let postStart: String?
    let postEnd: String?
    let settlementDate: String?

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date
        case coreStart = "core_start"
        case coreEnd = "core_end"
        case preStart = "pre_start"
        case preEnd = "pre_end"
        case postStart = "post_start"
        case postEnd = "post_end"
        case settlementDate = "settlement_date"
    }
}

enum MarketSessionKind: String, Codable, Sendable {
    case overnight
    case preMarket
    case regular
    case afterHours

    var activePriority: Int {
        switch self {
        case .regular:
            0
        case .preMarket:
            1
        case .afterHours:
            2
        case .overnight:
            3
        }
    }

    var usesLatestRegularBarsFallback: Bool {
        switch self {
        case .preMarket, .afterHours:
            true
        case .regular, .overnight:
            false
        }
    }
}

struct MarketSessionInterval: Codable, Identifiable, Sendable {
    let session: MarketSessionKind
    let start: Date
    let end: Date
    let marketDate: String

    var id: String {
        "\(marketDate)-\(session.rawValue)"
    }

    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

struct MarketSessionProgress: Codable, Sendable {
    let intervals: [MarketSessionInterval]
    let referenceDate: Date

    var cycleStart: Date? {
        intervals.first?.start
    }

    var cycleEnd: Date? {
        intervals.last?.end
    }
}

enum MarketSessionSchedule {
    static func intervals(
        from days: [AlpacaCalendarDay],
        overnightDays: [AlpacaCalendarDay] = []
    ) -> [MarketSessionInterval] {
        days.flatMap { intervals(for: $0, overnightDays: overnightDays) }
            .filter { $0.start < $0.end }
            .sorted { $0.start < $1.start }
    }

    static func activeInterval(
        at date: Date,
        in days: [AlpacaCalendarDay],
        overnightDays: [AlpacaCalendarDay] = []
    ) -> MarketSessionInterval? {
        activeInterval(at: date, in: intervals(from: days, overnightDays: overnightDays))
    }

    /// Overload for callers that already built the interval list, so it isn't recomputed per query.
    static func activeInterval(
        at date: Date,
        in intervals: [MarketSessionInterval]
    ) -> MarketSessionInterval? {
        intervals
            .filter { $0.contains(date) }
            .min { lhs, rhs in
                if lhs.session.activePriority == rhs.session.activePriority {
                    return lhs.start < rhs.start
                }

                return lhs.session.activePriority < rhs.session.activePriority
            }
    }

    static func latestRegularInterval(
        before date: Date,
        in days: [AlpacaCalendarDay],
        overnightDays: [AlpacaCalendarDay] = []
    ) -> MarketSessionInterval? {
        intervals(from: days, overnightDays: overnightDays)
            .filter { $0.session == .regular && $0.start <= date }
            .map { interval in
                MarketSessionInterval(
                    session: interval.session,
                    start: interval.start,
                    end: min(date, interval.end),
                    marketDate: interval.marketDate
                )
            }
            .filter { $0.start < $0.end }
            .sorted { $0.start < $1.start }
            .last
    }

    static func progress(
        for activeInterval: MarketSessionInterval,
        in days: [AlpacaCalendarDay],
        overnightDays: [AlpacaCalendarDay] = [],
        at date: Date
    ) -> MarketSessionProgress {
        progress(for: activeInterval, in: intervals(from: days, overnightDays: overnightDays), at: date)
    }

    static func progress(
        for activeInterval: MarketSessionInterval,
        in intervals: [MarketSessionInterval],
        at date: Date
    ) -> MarketSessionProgress {
        let cycleIntervals = intervals.filter { $0.marketDate == activeInterval.marketDate }
        return MarketSessionProgress(intervals: cycleIntervals, referenceDate: date)
    }

    private static func intervals(
        for day: AlpacaCalendarDay,
        overnightDays: [AlpacaCalendarDay]
    ) -> [MarketSessionInterval] {
        var intervals: [MarketSessionInterval] = []

        if let overnightInterval = overnightInterval(for: day, overnightDays: overnightDays) {
            intervals.append(overnightInterval)
        }

        if let preStart = AlpacaDateParser.date(day.preStart),
           let preEnd = AlpacaDateParser.date(day.preEnd) ?? AlpacaDateParser.date(day.coreStart) {
            intervals.append(
                MarketSessionInterval(
                    session: .preMarket,
                    start: preStart,
                    end: preEnd,
                    marketDate: day.date
                )
            )
        }

        if let coreStart = AlpacaDateParser.date(day.coreStart),
           let coreEnd = AlpacaDateParser.date(day.coreEnd) {
            intervals.append(
                MarketSessionInterval(
                    session: .regular,
                    start: coreStart,
                    end: coreEnd,
                    marketDate: day.date
                )
            )
        }

        if let postStart = AlpacaDateParser.date(day.postStart) ?? AlpacaDateParser.date(day.coreEnd),
           let postEnd = AlpacaDateParser.date(day.postEnd) {
            intervals.append(
                MarketSessionInterval(
                    session: .afterHours,
                    start: postStart,
                    end: postEnd,
                    marketDate: day.date
                )
            )
        }

        return intervals
    }

    private static func overnightInterval(
        for day: AlpacaCalendarDay,
        overnightDays: [AlpacaCalendarDay]
    ) -> MarketSessionInterval? {
        if let actualInterval = actualOvernightInterval(for: day, overnightDays: overnightDays) {
            return actualInterval
        }

        guard let overnightStart = overnightStart(forMarketDate: day.date),
              let overnightEnd = AlpacaDateParser.date(day.preStart) else {
            return nil
        }

        return MarketSessionInterval(
            session: .overnight,
            start: overnightStart,
            end: overnightEnd,
            marketDate: day.date
        )
    }

    private static func actualOvernightInterval(
        for day: AlpacaCalendarDay,
        overnightDays: [AlpacaCalendarDay]
    ) -> MarketSessionInterval? {
        guard let expectedStart = overnightStart(forMarketDate: day.date),
              let expectedEnd = AlpacaDateParser.date(day.preStart) ?? AlpacaDateParser.date(day.coreStart) else {
            return nil
        }

        let lowerBound = expectedStart.addingTimeInterval(-60 * 60)
        let upperBound = expectedEnd.addingTimeInterval(60 * 60)
        let candidate = overnightDays
            .compactMap { overnightDay -> (start: Date, end: Date)? in
                guard let start = AlpacaDateParser.date(overnightDay.coreStart),
                      let end = AlpacaDateParser.date(overnightDay.coreEnd),
                      start < end else {
                    return nil
                }

                return (start, end)
            }
            .filter { interval in
                interval.start >= lowerBound
                    && interval.end <= upperBound
                    && interval.end <= expectedEnd.addingTimeInterval(60 * 5)
            }
            .max { lhs, rhs in
                lhs.end < rhs.end
            }

        guard let candidate else {
            return nil
        }

        return MarketSessionInterval(
            session: .overnight,
            start: candidate.start,
            end: candidate.end,
            marketDate: day.date
        )
    }

    private static func overnightStart(forMarketDate dateText: String) -> Date? {
        let parts = dateText.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        guard let marketDate = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2]
            )
        ),
              let previousDate = calendar.date(byAdding: .day, value: -1, to: marketDate) else {
            return nil
        }

        let previousComponents = calendar.dateComponents([.year, .month, .day], from: previousDate)
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: previousComponents.year,
                month: previousComponents.month,
                day: previousComponents.day,
                hour: 20,
                minute: 0,
                second: 0
            )
        )
    }
}

struct AlpacaMarketClockResponse: Decodable, Sendable {
    private let clocks: [AlpacaMarketClockPayload]

    enum CodingKeys: String, CodingKey {
        case clocks
    }

    func clock(market: String) throws -> AlpacaMarketClock {
        guard let marketClock = clocks.first(where: { $0.market.acronym == market }) else {
            throw APIClientError.decodingFailed(
                type: String(describing: Self.self),
                message: "Missing \(market) clock in v3 clock response."
            )
        }

        return marketClock.clock()
    }
}

private struct AlpacaMarketClockPayload: Decodable, Sendable {
    let isMarketDay: Bool
    let market: AlpacaClockMarket
    let timestamp: String?
    let nextOpen: String?
    let nextClose: String?
    let phase: String?
    let phaseUntil: String?

    enum CodingKeys: String, CodingKey {
        case isMarketDay = "is_market_day"
        case market
        case timestamp
        case nextOpen = "next_market_open"
        case nextClose = "next_market_close"
        case phase
        case phaseUntil = "phase_until"
    }

    func clock() -> AlpacaMarketClock {
        AlpacaMarketClock(
            timestamp: timestamp,
            isMarketDay: isMarketDay,
            isOpen: phase == "open",
            nextOpen: nextOpen,
            nextClose: nextClose,
            phase: phase,
            phaseUntil: phaseUntil
        )
    }
}

private struct AlpacaClockMarket: Decodable, Sendable {
    let acronym: String
    let mic: String?
    let name: String?
    let timezone: String?
}

struct AlpacaMarketClock: Codable, Sendable {
    let timestamp: String?
    let isMarketDay: Bool
    let isOpen: Bool
    let nextOpen: String?
    let nextClose: String?
    let phase: String?
    let phaseUntil: String?

    var activeSession: MarketSessionKind? {
        guard isMarketDay, let phase else {
            return nil
        }

        let normalizedPhase = phase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if isOpen || normalizedPhase == "open" {
            return .regular
        }

        if normalizedPhase.contains("overnight") {
            return .overnight
        }

        if normalizedPhase.contains("pre") {
            return .preMarket
        }

        if normalizedPhase.contains("post") || normalizedPhase.contains("after") {
            return .afterHours
        }

        return nil
    }
}

enum AlpacaDateParser {
    static func date(_ text: String?) -> Date? {
        guard let text else {
            return nil
        }

        return parser.date(from: text)
    }

    private static let parser = LockedAlpacaDateParser()
}

// @unchecked Sendable: DateFormatter access guarded by NSLock
private final class LockedAlpacaDateParser: @unchecked Sendable {
    private let lock = NSLock()
    private let fractionalSecondsFormatter = makeFormatter(fractionalSeconds: true)
    private let standardFormatter = makeFormatter(fractionalSeconds: false)
    private let dateOnlyFormatter = makeDateOnlyFormatter()

    func date(from text: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        return fractionalSecondsFormatter.date(from: text)
            ?? standardFormatter.date(from: text)
            ?? dateOnlyFormatter.date(from: text)
    }

    private static func makeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withColonSeparatorInTimeZone
        ]
        if fractionalSeconds {
            formatter.formatOptions.insert(.withFractionalSeconds)
        }
        return formatter
    }

    private static func makeDateOnlyFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }
}
