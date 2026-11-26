import RxSwift
import XCTest
@testable import vicu

@MainActor
final class AssetDetailStoreTests: XCTestCase {
    // MARK: - AssetDetailBarSeries

    func testBarSeriesNormalizesSortsMergesAndCapsChronologically() {
        let bar1 = makeBar(timestamp: "2026-06-17T14:00:00Z", close: 100)
        let bar2 = makeBar(timestamp: "2026-06-17T14:02:00Z", close: 102)
        let bar3 = makeBar(timestamp: "2026-06-17T14:01:00Z", close: 101)

        var series = AssetDetailBarSeries.normalized(from: [bar2, bar3, bar1], maxCount: 3)
        XCTAssertEqual(series.entries.map(\.bar.timestamp), [
            "2026-06-17T14:00:00Z",
            "2026-06-17T14:01:00Z",
            "2026-06-17T14:02:00Z"
        ])

        // Duplicate latest bar returns false
        XCTAssertFalse(series.merge(bar2, maxCount: 3))

        // Updated latest bar replaces in-place
        let updatedBar2 = makeBar(timestamp: "2026-06-17T14:02:00Z", close: 102.5)
        XCTAssertTrue(series.merge(updatedBar2, maxCount: 3))
        XCTAssertEqual(series.latestClose, 102.5)

        // Newer bar appends and trims oldest when capped at 3
        let bar4 = makeBar(timestamp: "2026-06-17T14:03:00Z", close: 104)
        XCTAssertTrue(series.merge(bar4, maxCount: 3))
        XCTAssertEqual(series.entries.map(\.bar.timestamp), [
            "2026-06-17T14:01:00Z",
            "2026-06-17T14:02:00Z",
            "2026-06-17T14:03:00Z"
        ])

        // Out-of-order historical bar inserts via binary search
        let midBar = makeBar(timestamp: "2026-06-17T14:01:30Z", close: 101.5)
        XCTAssertTrue(series.merge(midBar, maxCount: 5))
        XCTAssertEqual(series.entries.map(\.bar.timestamp), [
            "2026-06-17T14:01:00Z",
            "2026-06-17T14:01:30Z",
            "2026-06-17T14:02:00Z",
            "2026-06-17T14:03:00Z"
        ])
    }

    func testBarSeriesOvernightSupplementDeduplicatesByMinuteAndKeepsNewest() {
        var series = AssetDetailBarSeries()
        let first = makeBar(timestamp: "2026-06-17T02:05:10Z", close: 200)
        let newerSameMinute = makeBar(timestamp: "2026-06-17T02:05:45Z", close: 201)
        let olderSameMinute = makeBar(timestamp: "2026-06-17T02:05:20Z", close: 199)
        let nextMinute = makeBar(timestamp: "2026-06-17T02:06:00Z", close: 202)

        XCTAssertTrue(series.mergeOvernightSupplementBar(first))
        XCTAssertTrue(series.mergeOvernightSupplementBar(newerSameMinute))
        XCTAssertFalse(series.mergeOvernightSupplementBar(olderSameMinute))
        XCTAssertTrue(series.mergeOvernightSupplementBar(nextMinute))

        XCTAssertEqual(series.overnightSupplementEntries.count, 2)
        XCTAssertEqual(series.overnightSupplementEntries[0].bar.close, 201)
        XCTAssertEqual(series.overnightSupplementEntries[1].bar.close, 202)
    }

    // MARK: - AssetRealtimeBatch Ordering

    func testRealtimeBatchPreservesArrivalOrderForBars() {
        let events: [AssetRealtimeEvent] = [
            .minuteBar(AlpacaRealtimeBar(symbol: "AAPL", open: 100, high: 101, low: 99, close: 100, volume: 10, vwap: 100, tradeCount: 1, timestamp: "2026-06-17T14:00:00Z")),
            .minuteBar(AlpacaRealtimeBar(symbol: "AAPL", open: 101, high: 102, low: 100, close: 101, volume: 10, vwap: 101, tradeCount: 1, timestamp: "2026-06-17T14:01:00Z")),
            .minuteBar(AlpacaRealtimeBar(symbol: "AAPL", open: 102, high: 103, low: 101, close: 102, volume: 10, vwap: 102, tradeCount: 1, timestamp: "2026-06-17T14:02:00Z")),
            .updatedBar(AlpacaRealtimeBar(symbol: "AAPL", open: 101, high: 103, low: 100, close: 102.5, volume: 20, vwap: 101.5, tradeCount: 2, timestamp: "2026-06-17T14:01:00Z"))
        ]

        let batch = AssetRealtimeBatch(events: events, symbol: "AAPL")
        XCTAssertEqual(batch?.bars.map(\.timestamp), [
            "2026-06-17T14:00:00Z",
            "2026-06-17T14:01:00Z",
            "2026-06-17T14:02:00Z"
        ])
        XCTAssertEqual(batch?.bars[1].close, 102.5)
    }

    // MARK: - AssetDetailStore Behavior & Race Condition Regression Tests

    func testSelectCachedRangeCancelsInFlightRangeAndNeverOverwrites() async {
        let service = MockAssetDetailService()
        service.detailSnapshots[.oneDay] = makeSnapshot(range: .oneDay, closePrices: [100, 101])
        service.detailSnapshots[.oneWeek] = makeSnapshot(range: .oneWeek, closePrices: [90, 95, 100])
        service.detailSnapshots[.oneMonth] = makeSnapshot(range: .oneMonth, closePrices: [80, 85, 100])

        let store = AssetDetailStore(symbol: "AAPL")
        store.start(service: service)
        await waitUntil { !store.isLoading && !store.isLoadingChart }

        // Load & cache 1W
        store.selectRange(.oneWeek)
        await waitUntil { store.selectedRange == .oneWeek && !store.isLoadingChart && store.chartRenderModels.line.points.count == 3 }

        // Delay 1M request so we can switch back to cached 1W while 1M is in flight
        service.delayedRanges[.oneMonth] = 150_000_000 // 150ms
        store.selectRange(.oneMonth)
        XCTAssertEqual(store.selectedRange, .oneMonth)
        XCTAssertTrue(store.isLoadingChart)

        // Immediately switch back to cached 1W
        store.selectRange(.oneWeek)
        XCTAssertEqual(store.selectedRange, .oneWeek)
        XCTAssertFalse(store.isLoadingChart)
        XCTAssertEqual(store.chartRenderModels.line.points.count, 3)

        // Wait longer than 1M's delay and assert 1M did NOT overwrite 1W
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(store.selectedRange, .oneWeek)
        XCTAssertEqual(store.chartRenderModels.line.points.first?.close, 90)

        store.stop()
    }

    func testSelectChartModeIsInstantAndSharesPrecomputedPoints() async {
        let service = MockAssetDetailService()
        service.detailSnapshots[.oneDay] = makeSnapshot(range: .oneDay, closePrices: [100, 102])
        service.detailSnapshots[.oneMonth] = makeSnapshot(range: .oneMonth, closePrices: [95, 100, 105])

        let store = AssetDetailStore(symbol: "AAPL")
        store.start(service: service)
        await waitUntil { !store.isLoading && !store.isLoadingChart }

        store.selectRange(.oneMonth)
        await waitUntil { !store.isLoadingChart && store.chartRenderModels.line.points.count == 3 }

        XCTAssertEqual(store.effectiveChartMode, .line)
        let lineDigest = store.chartRenderModels.line.pointsDigest

        store.selectChartMode(.candles)
        XCTAssertEqual(store.effectiveChartMode, .candles)
        XCTAssertFalse(store.isLoadingChart)
        XCTAssertEqual(store.chartRenderModels.candles.points.count, 3)
        XCTAssertEqual(store.chartRenderModels.candles.pointsDigest, lineDigest)

        store.stop()
    }

    func testPositionPreservedOnTransientErrorAndClearedOnNil404() async {
        let service = MockAssetDetailService()
        service.detailSnapshots[.oneDay] = makeSnapshot(range: .oneDay, closePrices: [100, 101])
        service.positionResult = .success(makePosition(symbol: "AAPL", qty: "10"))

        let store = AssetDetailStore(symbol: "AAPL")
        store.start(service: service)
        await waitUntil { store.position?.quantity == "10" }

        // Transient network error on refresh should NOT wipe existing position
        service.positionResult = .failure(URLError(.timedOut))
        await store.refresh(service: service)
        XCTAssertEqual(store.position?.quantity, "10")

        // Explicit nil (HTTP 404 from AlpacaClient) should clear position
        service.positionResult = .success(nil)
        await store.refresh(service: service)
        XCTAssertNil(store.position)

        store.stop()
    }

    func testStartAfterStopResumesWithoutWipingLoadedAsset() async {
        let service = MockAssetDetailService()
        service.detailSnapshots[.oneDay] = makeSnapshot(range: .oneDay, closePrices: [100, 101])

        let store = AssetDetailStore(symbol: "AAPL")
        store.start(service: service)
        await waitUntil { store.asset != nil && !store.isLoadingChart }
        let initialDetailFetches = service.detailFetchCount

        // Simulate push to TradeView -> pop back to AssetDetailView
        store.stop()
        store.start(service: service)

        XCTAssertNotNil(store.asset)
        XCTAssertFalse(store.isLoading)
        // Should not trigger another full blocking AssetDetailSnapshot fetch on re-appear
        XCTAssertEqual(service.detailFetchCount, initialDetailFetches)

        store.stop()
    }

    // MARK: - AssetNewsHTMLDecoder

    func testNewsHTMLDecoderHandlesNamedAndNumericEntities() {
        XCTAssertEqual(
            AssetNewsHTMLDecoder.decode("AT&amp;T&#39;s Q4 &ldquo;Beat&rdquo; &mdash; &gt;10% &amp; &#x20AC;5M"),
            "AT&T's Q4 “Beat” — >10% & €5M"
        )
        XCTAssertEqual(
            AssetNewsHTMLDecoder.decode("Plain headline without entities"),
            "Plain headline without entities"
        )
        XCTAssertEqual(
            AssetNewsHTMLDecoder.decode("Keep &unknown; intact"),
            "Keep &unknown; intact"
        )
    }

    // MARK: - Helpers

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }

    private func makeBar(timestamp: String, close: Double) -> AlpacaMarketBar {
        AlpacaMarketBar(
            symbol: "AAPL",
            open: close,
            high: close + 1,
            low: close - 1,
            close: close,
            volume: 100,
            vwap: close,
            tradeCount: 5,
            timestamp: timestamp
        )
    }

    private func makeSnapshot(range: AssetChartRange, closePrices: [Double]) -> AssetDetailSnapshot {
        let bars = closePrices.enumerated().map { index, price in
            makeBar(
                timestamp: String(format: "2026-06-17T14:%02d:00Z", index),
                close: price
            )
        }
        let asset = AlpacaAsset(
            id: "asset-aapl",
            assetClass: "us_equity",
            exchange: "NASDAQ",
            symbol: "AAPL",
            name: "Apple Inc. Common Stock",
            status: "active",
            tradable: true,
            marginable: true,
            maintenanceMarginRequirement: nil,
            marginRequirementLong: nil,
            marginRequirementShort: nil,
            shortable: true,
            easyToBorrow: true,
            borrowStatus: nil,
            fractionable: true,
            attributes: ["has_options"]
        )
        return AssetDetailSnapshot(
            asset: asset,
            stockSnapshot: nil,
            bars: bars,
            chartBaseline: closePrices.first,
            range: range,
            feed: .iex,
            sessionProgress: nil,
            latestBar: nil
        )
    }

    private func makePosition(symbol: String, qty: String) -> AlpacaPosition {
        AlpacaPosition(
            assetID: "asset-1",
            symbol: symbol,
            exchange: "NASDAQ",
            assetClass: "us_equity",
            assetMarginable: true,
            quantity: qty,
            quantityAvailable: qty,
            averageEntryPrice: "100",
            side: "long",
            marketValue: "1050",
            costBasis: "1000",
            unrealizedPL: "50",
            unrealizedPLPC: "0.05",
            unrealizedIntradayPL: "10",
            unrealizedIntradayPLPC: "0.01",
            currentPrice: "105",
            lastDayPrice: "104",
            changeToday: "0.01"
        )
    }

    func testTradeMarkersLoadLazilyOnlyForNonIntradayAndClearWhenDisabled() async {
        let service = MockAssetDetailService()
        service.detailSnapshots[.oneDay] = makeSnapshot(range: .oneDay, closePrices: [100, 101])
        service.detailSnapshots[.oneMonth] = AssetDetailSnapshot(
            asset: makeSnapshot(range: .oneMonth, closePrices: [100]).asset,
            stockSnapshot: nil,
            bars: [
                makeBar(timestamp: "2026-06-15T04:00:00Z", close: 100),
                makeBar(timestamp: "2026-06-16T04:00:00Z", close: 105)
            ],
            chartBaseline: 100,
            range: .oneMonth,
            feed: .iex,
            sessionProgress: nil,
            latestBar: nil
        )
        service.symbolOrders = [
            AlpacaOrder(
                id: "ord-1",
                clientOrderID: nil,
                createdAt: nil,
                updatedAt: nil,
                submittedAt: nil,
                filledAt: "2026-06-16T15:00:00Z",
                expiredAt: nil,
                canceledAt: nil,
                failedAt: nil,
                replacedAt: nil,
                replacedBy: nil,
                replaces: nil,
                assetID: nil,
                symbol: "AAPL",
                assetClass: "us_equity",
                quantity: "10",
                filledQuantity: "10",
                filledAveragePrice: "104.5",
                notional: nil,
                orderClass: nil,
                orderType: "market",
                side: "buy",
                type: "market",
                positionIntent: nil,
                timeInForce: "day",
                limitPrice: nil,
                stopPrice: nil,
                status: "filled",
                extendedHours: false,
                legs: nil,
                trailPercent: nil,
                trailPrice: nil,
                highWaterMark: nil,
                subtag: nil,
                source: nil,
                expiresAt: nil
            )
        ]

        let store = AssetDetailStore(symbol: "AAPL")
        store.start(service: service)
        await waitUntil { !store.isLoading && !store.isLoadingChart }

        // Intraday (1D) must NOT fetch symbol orders or display markers
        XCTAssertEqual(service.symbolOrdersFetchCount, 0)
        XCTAssertTrue(store.chartTradeMarkers.isEmpty)

        // Switching to non-intraday (1M) lazily fetches once and maps markers
        store.selectRange(.oneMonth)
        await waitUntil { !store.isLoadingChart && !store.chartTradeMarkers.isEmpty }
        XCTAssertEqual(service.symbolOrdersFetchCount, 1)
        XCTAssertEqual(store.chartTradeMarkers.markers.count, 1)
        XCTAssertEqual(store.chartTradeMarkers.markers[0].side, .buy)

        // Toggling off clears markers immediately without refetching
        store.setShowsTradeMarkers(false)
        XCTAssertTrue(store.chartTradeMarkers.isEmpty)

        // Toggling back on restores from cached executions without another network call
        store.setShowsTradeMarkers(true)
        XCTAssertEqual(store.chartTradeMarkers.markers.count, 1)
        XCTAssertEqual(service.symbolOrdersFetchCount, 1)

        // Switching back to 1D clears markers
        store.selectRange(.oneDay)
        XCTAssertTrue(store.chartTradeMarkers.isEmpty)

        store.stop()
    }
}

@MainActor
private final class MockAssetDetailService: AssetDetailServicing {
    var detailSnapshots: [AssetChartRange: AssetDetailSnapshot] = [:]
    var delayedRanges: [AssetChartRange: UInt64] = [:]
    var positionResult: Result<AlpacaPosition?, Error> = .success(nil)
    var symbolOrders: [AlpacaOrder] = []
    var detailFetchCount = 0
    var symbolOrdersFetchCount = 0
    let streamSubject = PublishSubject<AssetRealtimeEvent>()

    var preferredLocale: Locale { Locale(identifier: "en_US") }

    func fetchAssetDetailSnapshot(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed
    ) async throws -> AssetDetailSnapshot {
        detailFetchCount += 1
        if let delay = delayedRanges[range] {
            try await Task.sleep(nanoseconds: delay)
        }
        try Task.checkCancellation()
        guard let snapshot = detailSnapshots[range] else {
            throw URLError(.resourceUnavailable)
        }
        return snapshot
    }

    func fetchAssetSnapshot(symbol: String, feed: AlpacaMarketDataFeed) async throws -> AlpacaStockSnapshot? {
        nil
    }

    func fetchResolvedAssetSnapshot(symbol: String, feed: AlpacaMarketDataFeed) async throws -> AlpacaResolvedStockSnapshot {
        AlpacaResolvedStockSnapshot(snapshot: nil, feed: feed, activeSession: nil, latestBar: nil)
    }

    func fetchLatestStockBar(symbol: String, feed: AlpacaMarketDataFeed) async throws -> AlpacaMarketBar? {
        nil
    }

    func fetchOpenPosition(symbol: String) async throws -> AlpacaPosition? {
        try positionResult.get()
    }

    func fetchSymbolOrders(symbol: String, after: Date?, forceRefresh: Bool) async throws -> [AlpacaOrder] {
        symbolOrdersFetchCount += 1
        return symbolOrders
    }

    func streamAssetMarketData(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        channels: Set<AlpacaRealtimeChannel>
    ) throws -> Observable<AssetRealtimeEvent> {
        streamSubject.asObservable()
    }
}
