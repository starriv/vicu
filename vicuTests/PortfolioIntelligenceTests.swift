import XCTest
@testable import vicu

final class PortfolioIntelligenceTests: XCTestCase {
    private let service = LocalPortfolioIntelligenceService()
    private let enLocale = Locale(identifier: "en")
    private let zhLocale = Locale(identifier: "zh-Hans")

    func testEmptyPortfolioReturnsEmptyGradeAndSafeZeros() async {
        let state = PortfolioState()
        let snapshot = await service.analyze(portfolio: state, environment: .paper, locale: enLocale)

        XCTAssertEqual(snapshot.health.grade, .empty)
        XCTAssertEqual(snapshot.health.score, 0)
        XCTAssertTrue(snapshot.actions.isEmpty)
        XCTAssertTrue(snapshot.allocation.segments.isEmpty)
        XCTAssertEqual(snapshot.openOrdersCount, 0)
    }

    func testLeveragedConcentratedPortfolioTriggersCriticalMarginAndConcentrationActions() async {
        var state = PortfolioState()
        state.account = makeAccount(
            equity: "100000",
            cash: "-80000",
            buyingPower: "0",
            longMV: "180000",
            shortMV: "0"
        )
        state.positions = [
            makePosition(symbol: "NVDA", marketValue: "120000", unrealizedPL: "24000", unrealizedPLPC: "0.25"),
            makePosition(symbol: "TSLA", marketValue: "60000", unrealizedPL: "-9000", unrealizedPLPC: "-0.13")
        ]

        let snapshot = await service.analyze(portfolio: state, environment: .paper, locale: enLocale)

        XCTAssertLessThan(snapshot.health.score, 60)
        XCTAssertGreaterThan(snapshot.health.leverageRatio, 1.7)
        XCTAssertEqual(snapshot.health.topHoldingSymbol, "NVDA")
        XCTAssertEqual(snapshot.health.concentrationRatio, 120000.0 / 180000.0, accuracy: 0.001)

        let actionKinds = snapshot.actions.map(\.kind)
        XCTAssertTrue(actionKinds.contains(.marginPressure))
        XCTAssertTrue(actionKinds.contains(.concentrationRisk))
        XCTAssertTrue(actionKinds.contains(.takeProfit))
        XCTAssertTrue(actionKinds.contains(.lossReview))
        XCTAssertEqual(snapshot.actions.first?.severity, .critical)
    }

    func testBalancedPortfolioProducesHighHealthScoreAndAllocationSegments() async {
        var state = PortfolioState()
        state.account = makeAccount(
            equity: "100000",
            cash: "15000",
            buyingPower: "15000",
            longMV: "85000",
            shortMV: "0"
        )
        state.positions = [
            makePosition(symbol: "AAPL", marketValue: "20000", unrealizedPL: "1200", unrealizedPLPC: "0.06"),
            makePosition(symbol: "MSFT", marketValue: "20000", unrealizedPL: "900", unrealizedPLPC: "0.047"),
            makePosition(symbol: "VOO", marketValue: "25000", unrealizedPL: "1500", unrealizedPLPC: "0.063"),
            makePosition(symbol: "QQQ", marketValue: "20000", unrealizedPL: "800", unrealizedPLPC: "0.041")
        ]
        state.applyHistory([
            PortfolioHistoryPoint(date: Date(timeIntervalSince1970: 1_700_000_000), equity: 96_000, profitLoss: 0, profitLossPercent: 0),
            PortfolioHistoryPoint(date: Date(timeIntervalSince1970: 1_700_086_400), equity: 100_000, profitLoss: 4_000, profitLossPercent: 0.0416)
        ])

        let snapshot = await service.analyze(portfolio: state, environment: .live, locale: enLocale)

        XCTAssertGreaterThanOrEqual(snapshot.health.score, 75)
        XCTAssertTrue(snapshot.health.grade == .strong || snapshot.health.grade == .balanced)
        XCTAssertEqual(snapshot.attribution.topContributors.first?.symbol, "VOO")
        XCTAssertTrue(snapshot.attribution.topDetractors.isEmpty)

        let categories = Set(snapshot.allocation.segments.map(\.category))
        XCTAssertEqual(categories, Set([.stock, .etf, .cash]))
        let totalWeight = snapshot.allocation.segments.reduce(0.0) { $0 + $1.weight }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.001)
    }

    func testCopilotRoutesTickerAndRebalanceAndChineseQueries() async {
        var state = PortfolioState()
        state.account = makeAccount(
            equity: "50000",
            cash: "5000",
            buyingPower: "10000",
            longMV: "45000",
            shortMV: "0"
        )
        state.positions = [
            makePosition(symbol: "AAPL", marketValue: "30000", unrealizedPL: "4500", unrealizedPLPC: "0.176"),
            makePosition(symbol: "SPY", marketValue: "15000", unrealizedPL: "-600", unrealizedPLPC: "-0.038")
        ]

        let snapshot = await service.analyze(portfolio: state, environment: .paper, locale: zhLocale)

        let tickerReply = await service.respond(
            to: "帮我看看 AAPL 持仓怎么样",
            portfolio: state,
            snapshot: snapshot,
            environment: .paper,
            locale: zhLocale
        )
        XCTAssertEqual(tickerReply.role, .assistant)
        XCTAssertEqual(tickerReply.destination, .position(symbol: "AAPL"))
        XCTAssertTrue(tickerReply.text.contains("AAPL"))

        let rebalanceReply = await service.respond(
            to: "如何降低集中度进行再平衡？",
            portfolio: state,
            snapshot: snapshot,
            environment: .paper,
            locale: zhLocale
        )
        XCTAssertEqual(rebalanceReply.destination, .trade(symbol: "AAPL", side: .sell))
        XCTAssertFalse(rebalanceReply.highlights.isEmpty)

        let marginReply = await service.respond(
            to: "Analyze my margin and cash buffer",
            portfolio: state,
            snapshot: snapshot,
            environment: .paper,
            locale: enLocale
        )
        XCTAssertEqual(marginReply.destination, .account)
    }

    func testZeroBasedProfitLossShiftedHistoryReconstructsTrueAccountEquity() {
        let account = makeAccount(
            equity: "5220.04",
            cash: "34.29",
            buyingPower: "34.29",
            longMV: "5185.75",
            shortMV: "0"
        )
        let rawHistory = [
            PortfolioHistoryPoint(date: Date(timeIntervalSince1970: 1_700_000_000), equity: 0, profitLoss: 0, profitLossPercent: nil),
            PortfolioHistoryPoint(date: Date(timeIntervalSince1970: 1_700_000_300), equity: -20, profitLoss: -20, profitLossPercent: nil),
            PortfolioHistoryPoint(date: Date(timeIntervalSince1970: 1_700_000_600), equity: 215.93, profitLoss: 215.93, profitLossPercent: nil)
        ]

        let normalized = PortfolioEquitySeriesNormalizer.normalize(history: rawHistory, account: account)

        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized[0].equity, 5004.11, accuracy: 0.01)
        XCTAssertEqual(normalized[1].equity, 4984.11, accuracy: 0.01)
        XCTAssertEqual(normalized[2].equity, 5220.04, accuracy: 0.01)
        XCTAssertEqual(normalized[2].profitLoss ?? 0, 215.93, accuracy: 0.01)
        XCTAssertEqual(normalized[2].profitLossPercent ?? 0, 215.93 / 5004.11, accuracy: 0.0001)
    }

    func testNormalEquityHistoryIsNotShifted() {
        let account = makeAccount(
            equity: "116173.01",
            cash: "115534.38",
            buyingPower: "463925.39",
            longMV: "638.53",
            shortMV: "0"
        )
        let rawHistory = [
            PortfolioHistoryPoint(date: Date(timeIntervalSince1970: 1_700_000_000), equity: 116179.37, profitLoss: 0, profitLossPercent: 0),
            PortfolioHistoryPoint(date: Date(timeIntervalSince1970: 1_700_000_600), equity: 116173.01, profitLoss: -6.36, profitLossPercent: -0.000055)
        ]

        let normalized = PortfolioEquitySeriesNormalizer.normalize(history: rawHistory, account: account)

        XCTAssertEqual(normalized[0].equity, 116179.37, accuracy: 0.01)
        XCTAssertEqual(normalized[1].equity, 116173.01, accuracy: 0.01)
    }

    func testYearToDateAndOneYearQueryItemsIncludeBothStartAndEndWithoutPeriod() {
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let nov25 = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12, minute: 0))!

        let ytdItems = Dictionary(
            uniqueKeysWithValues: PortfolioHistoryRange.yearToDate
                .queryItems(accountCreatedAt: nil, now: nov25)
                .map { ($0.name, $0.value ?? "") }
        )
        XCTAssertNil(ytdItems["period"])
        XCTAssertTrue(ytdItems["start"]?.hasPrefix("2026-01-01T00:00:00") == true)
        XCTAssertTrue(ytdItems["end"]?.hasPrefix("2026-11-25T12:00:00") == true)
        XCTAssertEqual(ytdItems["timeframe"], "1D")
        XCTAssertEqual(ytdItems["pnl_reset"], "no_reset")

        let oneYearItems = Dictionary(
            uniqueKeysWithValues: PortfolioHistoryRange.oneYear
                .queryItems(accountCreatedAt: nil, now: nov25)
                .map { ($0.name, $0.value ?? "") }
        )
        XCTAssertNil(oneYearItems["period"])
        XCTAssertTrue(oneYearItems["start"]?.hasPrefix("2025-11-25T12:00:00") == true)
        XCTAssertTrue(oneYearItems["end"]?.hasPrefix("2026-11-25T12:00:00") == true)
        XCTAssertEqual(oneYearItems["timeframe"], "1D")
        XCTAssertEqual(oneYearItems["pnl_reset"], "no_reset")

        let oneMonthItems = Dictionary(
            uniqueKeysWithValues: PortfolioHistoryRange.oneMonth
                .queryItems(accountCreatedAt: nil, now: nov25)
                .map { ($0.name, $0.value ?? "") }
        )
        XCTAssertNil(oneMonthItems["period"])
        XCTAssertTrue(oneMonthItems["start"]?.hasPrefix("2026-10-25T12:00:00") == true)
        XCTAssertTrue(oneMonthItems["end"]?.hasPrefix("2026-11-25T12:00:00") == true)
        XCTAssertEqual(oneMonthItems["timeframe"], "1D")
    }

    func testSameDayBarUpdatesInPlaceWithoutDoubleCountingProfitLoss() {
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let nov24 = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 16, minute: 0))!
        let nov25Open = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 0, minute: 0))!
        let nov25Afternoon = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 14, minute: 0))!

        // The account snapshot includes a $550 transfer after the last broker P/L bar.
        let account = makeAccount(
            equity: "106050",
            lastEquity: "105000",
            cash: "6050",
            buyingPower: "6050",
            longMV: "100000",
            shortMV: "0"
        )
        let historyWithSameDayBar = [
            PortfolioHistoryPoint(date: nov24, equity: 105_000, profitLoss: 5_000, profitLossPercent: 0.05),
            PortfolioHistoryPoint(date: nov25Open, equity: 105_500, profitLoss: 5_500, profitLossPercent: 0.055)
        ]

        let normalized = PortfolioEquitySeriesNormalizer.normalize(
            history: historyWithSameDayBar,
            account: account,
            range: .yearToDate,
            now: nov25Afternoon
        )

        // Must update today's bar in place (count == 2, not 3) and avoid double-counting intraday P/L.
        XCTAssertEqual(normalized.count, 2)
        XCTAssertEqual(normalized[1].equity, 106_050, accuracy: 0.01)
        XCTAssertEqual(normalized[1].profitLoss ?? 0, 5_500, accuracy: 0.01)
        XCTAssertEqual(normalized[1].profitLossPercent ?? 0, 0.055, accuracy: 0.0001)
    }

    func testOneWeekGapCarriesForwardAndAppendsLiveEquity() {
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let fri = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 16, minute: 0))!
        let sun = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 16, minute: 0))!
        let account = makeAccount(
            equity: "5180",
            lastEquity: "5000",
            cash: "180",
            buyingPower: "180",
            longMV: "5000",
            shortMV: "0"
        )
        let history = [
            PortfolioHistoryPoint(date: fri.addingTimeInterval(-3600), equity: 5_000, profitLoss: 0, profitLossPercent: 0),
            PortfolioHistoryPoint(date: fri, equity: 5_000, profitLoss: 0, profitLossPercent: 0)
        ]

        let normalized = PortfolioEquitySeriesNormalizer.normalize(
            history: history,
            account: account,
            range: .oneWeek,
            now: sun
        )

        XCTAssertGreaterThanOrEqual(normalized.count, 3)
        XCTAssertEqual(normalized.last?.date, sun)
        XCTAssertEqual(normalized.last?.equity ?? 0, 5_180, accuracy: 0.01)
        XCTAssertEqual(normalized.last?.profitLoss, 0)
    }

    func testJanuaryYTDUsesReferenceNowInsteadOfWallClock() {
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let jan18 = nyCalendar.date(from: DateComponents(year: 2026, month: 1, day: 18, hour: 12, minute: 0))!

        let janLabels = PortfolioChartTimeline.axisLabels(for: .yearToDate, dates: [], now: jan18, locale: enLocale)
        XCTAssertTrue(janLabels.allSatisfy { $0.contains("/") })
    }

    func testOneMonthAndThreeMonthsReflectYesterdayDepositDuringOvernightWindow() {
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let oct26 = nyCalendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 20, minute: 0))!
        let nov23 = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 20, minute: 0))!
        let nov24Close = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 20, minute: 0))!
        // 4.5 hours after Nov 24 20:00 ET (13:30 Beijing time) — previously fell into the <= 6h dead zone!
        let nov25Overnight = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 0, minute: 30))!

        let account = makeAccount(
            equity: "5183.09",
            lastEquity: "5000.00",
            cash: "34.29",
            buyingPower: "26.20",
            longMV: "5148.80",
            shortMV: "0"
        )
        let flatZeroOneMonth = [
            PortfolioHistoryPoint(date: oct26, equity: 0, profitLoss: 0, profitLossPercent: nil),
            PortfolioHistoryPoint(date: nov23, equity: 0, profitLoss: 0, profitLossPercent: nil),
            PortfolioHistoryPoint(date: nov24Close, equity: 0, profitLoss: 0, profitLossPercent: nil)
        ]

        for range in [PortfolioHistoryRange.oneMonth, PortfolioHistoryRange.threeMonths] {
            let normalized = PortfolioEquitySeriesNormalizer.normalize(
                history: flatZeroOneMonth,
                account: account,
                range: range,
                now: nov25Overnight
            )

            XCTAssertEqual(normalized.count, 4)
            XCTAssertEqual(normalized[0].equity, 0, accuracy: 0.01)
            XCTAssertEqual(normalized[1].equity, 0, accuracy: 0.01)
            // Yesterday's bar reflects settled deposit ($5,000), today reflects live equity ($5,183.09)
            XCTAssertEqual(normalized[2].equity, 5000.00, accuracy: 0.01)
            XCTAssertEqual(normalized[3].equity, 5183.09, accuracy: 0.01)
            XCTAssertEqual(normalized[3].profitLoss, 0)
            XCTAssertNil(normalized[3].profitLossPercent)
        }

        // Even when account.lastEquity has not rolled over yet (still 0), live equity must still step up!
        let unsettledAccount = makeAccount(
            equity: "5183.09",
            lastEquity: "0",
            cash: "5183.09",
            buyingPower: "5183.09",
            longMV: "0",
            shortMV: "0"
        )
        let normalizedUnsettled = PortfolioEquitySeriesNormalizer.normalize(
            history: flatZeroOneMonth,
            account: unsettledAccount,
            range: .oneMonth,
            now: nov25Overnight
        )
        XCTAssertEqual(normalizedUnsettled.count, 4)
        XCTAssertEqual(normalizedUnsettled[2].equity, 0, accuracy: 0.01)
        XCTAssertEqual(normalizedUnsettled[3].equity, 5183.09, accuracy: 0.01)
    }

    func testOneWeekFutureBarUpdatesInPlaceAndPreservesStrictAscendingDates() {
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let bar1 = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 23, minute: 0))!
        let bar2AheadOfNow = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 1, minute: 0))!
        let nowSlightlyBehindServer = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 0, minute: 30))!

        let account = makeAccount(
            equity: "5183.09",
            lastEquity: "5000.00",
            cash: "183.09",
            buyingPower: "183.09",
            longMV: "5000.00",
            shortMV: "0"
        )
        let history = [
            PortfolioHistoryPoint(date: bar1, equity: 0, profitLoss: 0, profitLossPercent: nil),
            PortfolioHistoryPoint(date: bar2AheadOfNow, equity: 0, profitLoss: 0, profitLossPercent: nil)
        ]

        let normalized = PortfolioEquitySeriesNormalizer.normalize(
            history: history,
            account: account,
            range: .oneWeek,
            now: nowSlightlyBehindServer
        )

        XCTAssertEqual(normalized.count, 2)
        XCTAssertLessThan(normalized[0].date, normalized[1].date)
        XCTAssertEqual(normalized[1].equity, 5183.09, accuracy: 0.01)
    }

    func testIntradayBaselineOffsetDoesNotFalselyShiftWhenLastEquityIsNonZeroWithoutProfitLoss() {
        let account = makeAccount(
            equity: "5000.00",
            lastEquity: "0",
            cash: "5000.00",
            buyingPower: "5000.00",
            longMV: "0",
            shortMV: "0"
        )
        let history = [
            PortfolioHistoryPoint(date: Date(timeIntervalSince1970: 1_700_000_000), equity: 0, profitLoss: nil, profitLossPercent: nil),
            PortfolioHistoryPoint(date: Date(timeIntervalSince1970: 1_700_000_300), equity: 2000, profitLoss: nil, profitLossPercent: nil)
        ]

        let offset = PortfolioEquitySeriesNormalizer.inferredIntradayBaselineOffset(
            history: history,
            liveEquity: 5000.00
        )
        XCTAssertEqual(offset, 0, accuracy: 0.001)

        let normalized = PortfolioEquitySeriesNormalizer.normalize(history: history, account: account, range: .oneDay)
        XCTAssertEqual(normalized[0].equity, 0, accuracy: 0.01)
        XCTAssertEqual(normalized[1].equity, 2000, accuracy: 0.01)
    }

    func testAssetChartYTDStartDateUsesNewYorkYearAndDailyFormattersAlignTimezone() {
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        // Dec 31, 2026 20:00 EST == Jan 1, 2027 01:00 UTC (Jan 1 09:00 Beijing)
        let dec31EveningEST = nyCalendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 20, minute: 0))!
        let ytdStart = AssetChartRange.yearToDate.startDate(now: dec31EveningEST)
        XCTAssertEqual(nyCalendar.component(.year, from: ytdStart), 2026)
        XCTAssertEqual(nyCalendar.component(.month, from: ytdStart), 1)
        XCTAssertEqual(nyCalendar.component(.day, from: ytdStart), 1)

        // Nov 24, 2026 20:00 EST == Nov 25, 2026 09:00 Beijing
        let nov24EveningEST = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 20, minute: 0))!
        XCTAssertEqual(AssetChartDateLabelFormatter.string(from: nov24EveningEST, range: .oneMonth), "Nov 24, 2026")
        XCTAssertEqual(AssetChartDateLabelFormatter.axisTick(from: nov24EveningEST, range: .oneMonth), "11/24")
        XCTAssertEqual(AssetChartDateLabelFormatter.string(from: nov24EveningEST, range: .threeMonths), "Nov 24, 2026")
        XCTAssertEqual(AssetChartDateLabelFormatter.axisTick(from: nov24EveningEST, range: .threeMonths), "11/24")
    }

    func testMonthlyAxisTicksAndCalendarDomainForOneYearAndYTD() {
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let nov25 = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12, minute: 0))!
        let may15 = nyCalendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 12, minute: 0))!

        let ytdNovLabels = PortfolioChartTimeline.axisLabels(for: .yearToDate, dates: [], now: nov25, locale: enLocale)
        XCTAssertEqual(ytdNovLabels.first, "Jan")
        XCTAssertEqual(ytdNovLabels.last, "Nov")
        XCTAssertEqual(ytdNovLabels.count, 6)

        let ytdMayLabels = PortfolioChartTimeline.axisLabels(for: .yearToDate, dates: [], now: may15, locale: enLocale)
        XCTAssertEqual(ytdMayLabels, ["Jan", "Feb", "Mar", "Apr", "May"])

        let oneYearNovLabels = PortfolioChartTimeline.axisLabels(for: .oneYear, dates: [], now: nov25, locale: enLocale)
        XCTAssertEqual(oneYearNovLabels.first, "25/12")
        XCTAssertEqual(oneYearNovLabels.last, "26/11")
        XCTAssertEqual(oneYearNovLabels.count, 6)

        let ytdZhLabels = PortfolioChartTimeline.axisLabels(for: .yearToDate, dates: [], now: may15, locale: zhLocale)
        XCTAssertEqual(ytdZhLabels, ["1月", "2月", "3月", "4月", "5月"])

        // Multi-day all-zero history stopping at Jun 11 must stay flat at $0 until yesterday,
        // NOT ramp diagonally from Jun 11 to Nov 25!
        let account = makeAccount(equity: "5178.61", cash: "34.29", buyingPower: "26.20", longMV: "5144.32", shortMV: "0")
        let jan3 = nyCalendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        let jun11 = nyCalendar.date(from: DateComponents(year: 2026, month: 6, day: 11))!
        let sep1 = nyCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let flatZeroYTD = [
            PortfolioHistoryPoint(date: jan3, equity: 0, profitLoss: 0, profitLossPercent: nil),
            PortfolioHistoryPoint(date: jun11, equity: 0, profitLoss: 0, profitLossPercent: nil)
        ]
        let normalizedYTD = PortfolioEquitySeriesNormalizer.normalize(
            history: flatZeroYTD,
            account: account,
            range: .yearToDate,
            now: nov25
        )
        XCTAssertEqual(normalizedYTD.first?.equity ?? -1, 0, accuracy: 0.01)
        let sepPoint = normalizedYTD.last(where: { $0.date <= sep1 })
        XCTAssertEqual(sepPoint?.equity ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(normalizedYTD.last?.equity ?? -1, 5178.61, accuracy: 0.01)
        XCTAssertGreaterThan(normalizedYTD.count, 10)

        let oct1 = nyCalendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let ytdDomain = PortfolioChartTimeline.xDomain(for: .yearToDate, dates: [oct1, nov25], now: nov25)
        let jan1 = nyCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 0))!
        XCTAssertEqual(ytdDomain.lowerBound, jan1.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(ytdDomain.upperBound, nov25.timeIntervalSince1970, accuracy: 1.0)
    }

    func testPortfolioStateIsolatesHistoryAcrossRanges() {
        var state = PortfolioState()
        let dayPoint = PortfolioHistoryPoint(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            equity: 5_000,
            profitLoss: 10,
            profitLossPercent: 0.002
        )
        state.applyHistory([dayPoint], for: .oneDay)
        XCTAssertEqual(state.displayedHistory(for: .oneDay).count, 1)
        XCTAssertTrue(state.displayedHistory(for: .yearToDate).isEmpty)

        state.selectHistoryRange(.yearToDate)
        XCTAssertTrue(state.displayedHistory(for: .yearToDate).isEmpty)
        XCTAssertEqual(state.displayedHistory(for: .oneDay).count, 1)
    }

    func testLateSameDayWeeklyBarKeepsBrokerProfitLoss() {
        let account = makeAccount(equity: "10200", lastEquity: "10000", cash: "200", buyingPower: "200", longMV: "10000", shortMV: "0")
        let now = ISO8601DateFormatter().date(from: "2026-11-24T23:00:00Z")!
        let bar = PortfolioHistoryPoint(date: now.addingTimeInterval(-8 * 3600), equity: 10_100, profitLoss: 100, profitLossPercent: 0.01)
        let series = PortfolioEquitySeriesNormalizer.normalize(history: [bar], account: account, range: .oneWeek, now: now)
        XCTAssertEqual(series.last?.equity, 10_200)
        XCTAssertEqual(series.last?.profitLoss, 100)
        XCTAssertEqual(series.last?.profitLossPercent, 0.01)
    }

    func testCashTransferWithMissingProfitLossStaysUnknown() {
        let now = Date()
        let bars = [10_000.0, 15_000.0].enumerated().map { index, equity in
            PortfolioHistoryPoint(date: now.addingTimeInterval(Double(index - 1) * 86_400), equity: equity, profitLoss: nil, profitLossPercent: nil)
        }
        let series = PortfolioEquitySeriesNormalizer.normalize(history: bars, account: nil, range: .oneMonth, now: now)
        XCTAssertNil(series.last?.profitLoss)
        XCTAssertNil(series.last?.profitLossPercent)
    }

    func testWipeoutPreservesFullDrawdownAndMarginRisk() async {
        var state = PortfolioState()
        state.account = makeAccount(equity: "0", cash: "6000", buyingPower: "0", longMV: "0", shortMV: "-6000")
        state.positions = [makePosition(symbol: "NVDA", marketValue: "-6000", unrealizedPL: "-1000", unrealizedPLPC: "-0.2", side: "short")]
        state.applyHistory([
            PortfolioHistoryPoint(date: Date().addingTimeInterval(-3600), equity: 1_000, profitLoss: 0, profitLossPercent: 0),
            PortfolioHistoryPoint(date: Date(), equity: 0, profitLoss: -1_000, profitLossPercent: -1)
        ])
        let snapshot = await service.analyze(portfolio: state, environment: .paper, locale: enLocale)
        XCTAssertEqual(snapshot.health.maxDrawdown, 1)
        XCTAssertEqual(snapshot.health.leverageRatio, .infinity)
        XCTAssertTrue(snapshot.actions.contains { $0.kind == .marginPressure && $0.severity == .critical })
    }

    func testRebalanceChipUsesClosingSideAndPostSaleWeight() async throws {
        let cases: [(String, String, String, PortfolioAIActionDestination)] = [
            ("NVDA", "us_equity", "short", .trade(symbol: "NVDA", side: .buy)),
            ("NVDA261218C00140000", "us_option", "long", .closeOption(symbol: "NVDA261218C00140000", intent: .sellToClose)),
            ("NVDA261218C00140000", "us_option", "short", .closeOption(symbol: "NVDA261218C00140000", intent: .buyToClose))
        ]
        for (symbol, assetClass, side, destination) in cases {
            var state = PortfolioState()
            state.positions = [
                makePosition(symbol: symbol, marketValue: side == "short" ? "-6000" : "6000", unrealizedPL: "1000", unrealizedPLPC: "0.2", assetClass: assetClass, side: side),
                makePosition(symbol: "SPY", marketValue: "4000", unrealizedPL: "0", unrealizedPLPC: "0")
            ]
            let snapshot = await service.analyze(portfolio: state, environment: .paper, locale: enLocale)
            let chip = try XCTUnwrap(snapshot.suggestedPrompts.first { $0.id == "rebalance-top" })
            let reply = await service.respond(to: chip.prompt, portfolio: state, snapshot: snapshot, environment: .paper, locale: enLocale)
            XCTAssertEqual(reply.destination, destination)
            // Selling 4,666.67 leaves 1,333.33 out of 5,333.33 invested.
            XCTAssertTrue(reply.text.contains(AppFormatter.compactMoney(4_666.67, currencyCode: "USD")), reply.text)
            XCTAssertEqual(snapshot.actions.first { $0.kind == .takeProfit }?.destination, destination)
        }
    }

    // MARK: - Fixtures

    private func makeAccount(
        equity: String,
        lastEquity: String? = nil,
        cash: String,
        buyingPower: String,
        longMV: String,
        shortMV: String
    ) -> AlpacaAccount {
        AlpacaAccount(
            id: "acct-1",
            accountNumber: "PA123456",
            createdAt: nil,
            status: "ACTIVE",
            currency: "USD",
            buyingPower: buyingPower,
            regtBuyingPower: buyingPower,
            daytradingBuyingPower: buyingPower,
            effectiveBuyingPower: buyingPower,
            nonMarginableBuyingPower: buyingPower,
            optionsBuyingPower: buyingPower,
            bodDtbp: nil,
            cash: cash,
            accruedFees: nil,
            portfolioValue: equity,
            patternDayTrader: false,
            tradingBlocked: false,
            transfersBlocked: false,
            accountBlocked: false,
            tradeSuspendedByUser: false,
            multiplier: "2",
            shortingEnabled: true,
            equity: equity,
            lastEquity: lastEquity ?? equity,
            longMarketValue: longMV,
            shortMarketValue: shortMV,
            positionMarketValue: longMV,
            initialMargin: nil,
            maintenanceMargin: nil,
            lastMaintenanceMargin: nil,
            sma: nil,
            daytradeCount: 0,
            balanceAsOf: nil,
            cryptoStatus: nil,
            optionsApprovedLevel: 2,
            optionsTradingLevel: 2,
            cryptoTier: nil,
            intradayAdjustments: nil,
            pendingRegTAFFees: nil
        )
    }

    private func makePosition(
        symbol: String,
        marketValue: String,
        unrealizedPL: String,
        unrealizedPLPC: String,
        assetClass: String = "us_equity",
        side: String = "long"
    ) -> AlpacaPosition {
        AlpacaPosition(
            assetID: "asset-\(symbol)",
            symbol: symbol,
            exchange: "NASDAQ",
            assetClass: assetClass,
            assetMarginable: true,
            quantity: "100",
            quantityAvailable: "100",
            averageEntryPrice: "100",
            side: side,
            marketValue: marketValue,
            costBasis: "10000",
            unrealizedPL: unrealizedPL,
            unrealizedPLPC: unrealizedPLPC,
            unrealizedIntradayPL: unrealizedPL,
            unrealizedIntradayPLPC: unrealizedPLPC,
            currentPrice: "120",
            lastDayPrice: "118",
            changeToday: "0.016"
        )
    }

    func testPortfolioPerformanceSeriesResolvesPercentAndImpliedFallback() {
        XCTAssertEqual(PortfolioChartMode.allCases, [.value, .performance])

        let explicitPoint = NormalizedPortfolioHistoryPoint(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            equity: 5_523.15,
            profitLoss: 399.54,
            profitLossPercent: 0.0778
        )
        XCTAssertEqual(PortfolioPerformanceSeries.ratio(for: explicitPoint) ?? -1, 0.0778, accuracy: 0.0001)

        let impliedPoint = NormalizedPortfolioHistoryPoint(
            date: Date(timeIntervalSince1970: 1_700_000_300),
            equity: 5_500.0,
            profitLoss: 500.0,
            profitLossPercent: nil
        )
        XCTAssertEqual(PortfolioPerformanceSeries.ratio(for: impliedPoint) ?? -1, 0.10, accuracy: 0.0001)

        let zeroPreFundingPoint = NormalizedPortfolioHistoryPoint(
            date: Date(timeIntervalSince1970: 1_700_000_600),
            equity: 0.0,
            profitLoss: 0.0,
            profitLossPercent: nil
        )
        XCTAssertEqual(PortfolioPerformanceSeries.ratio(for: zeroPreFundingPoint) ?? -1, 0.0, accuracy: 0.0001)

        let unknownPoint = NormalizedPortfolioHistoryPoint(
            date: Date(timeIntervalSince1970: 1_700_000_900),
            equity: 5_500.0,
            profitLoss: nil,
            profitLossPercent: nil
        )
        XCTAssertNil(PortfolioPerformanceSeries.ratio(for: unknownPoint))

        let points = [
            FinancialChartPoint(date: Date(timeIntervalSince1970: 1_700_000_000), x: 0, value: 0.0),
            FinancialChartPoint(date: Date(timeIntervalSince1970: 1_700_000_300), x: 300, value: 0.0778)
        ]
        let solution = FinancialChartYAxisSolver.solve(
            points: points,
            kind: .area,
            baselinePolicy: .softInclude(value: 0, maxExpansionRatio: 0.60, showsReferenceLine: true),
            config: .portfolioPerformance
        )
        XCTAssertLessThan(solution.domain.upperBound - solution.domain.lowerBound, 0.15)
        XCTAssertEqual(solution.baselinePlacement, .inPlot(value: 0))
    }
}
