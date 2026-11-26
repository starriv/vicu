import CoreGraphics
import XCTest
@testable import vicu

final class FinancialChartEngineTests: XCTestCase {
    // MARK: - Y-Axis Proportion & Solver Tests

    func testLineModeIgnoresExtremeOHLCWickOutliers() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [FinancialChartPoint] = [
            FinancialChartPoint(date: baseDate, x: 0, open: 100, high: 101, low: 99, close: 100.0),
            // Extreme wick spike that used to squash the entire line chart
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 1, open: 100.5, high: 185.0, low: 40.0, close: 100.8),
            FinancialChartPoint(date: baseDate.addingTimeInterval(120), x: 2, open: 100.8, high: 102, low: 100, close: 101.5),
            FinancialChartPoint(date: baseDate.addingTimeInterval(180), x: 3, open: 101.5, high: 102.2, low: 101, close: 102.0)
        ]

        let lineSolution = FinancialChartYAxisSolver.solve(
            points: points,
            kind: .line,
            baselinePolicy: .none,
            config: .financialPrice
        )
        let candleSolution = FinancialChartYAxisSolver.solve(
            points: points,
            kind: .candles,
            baselinePolicy: .none,
            config: .financialPrice
        )

        XCTAssertEqual(lineSolution.dataMin, 100.0, accuracy: 1e-6)
        XCTAssertEqual(lineSolution.dataMax, 102.0, accuracy: 1e-6)
        XCTAssertLessThan(lineSolution.domain.upperBound - lineSolution.domain.lowerBound, 3.0)

        XCTAssertEqual(candleSolution.dataMin, 40.0, accuracy: 1e-6)
        XCTAssertEqual(candleSolution.dataMax, 185.0, accuracy: 1e-6)
    }

    func testSoftBaselineIncludesNearbyBaselineAndRejectsFarGapBaseline() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [FinancialChartPoint] = [
            FinancialChartPoint(date: baseDate, x: 0, value: 110.0),
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 1, value: 112.0),
            FinancialChartPoint(date: baseDate.addingTimeInterval(120), x: 2, value: 114.0)
        ]

        let nearby = FinancialChartYAxisSolver.solve(
            points: points,
            kind: .line,
            baselinePolicy: .softInclude(value: 109.0, maxExpansionRatio: 0.55, showsReferenceLine: true),
            config: .financialPrice
        )
        XCTAssertEqual(nearby.baselinePlacement, .inPlot(value: 109.0))
        XCTAssertLessThanOrEqual(nearby.domain.lowerBound, 109.0)

        // Large overnight gap up from $95 should NOT squash the $110..$114 intraday move
        let farGap = FinancialChartYAxisSolver.solve(
            points: points,
            kind: .line,
            baselinePolicy: .softInclude(value: 95.0, maxExpansionRatio: 0.55, showsReferenceLine: true),
            config: .financialPrice
        )
        XCTAssertEqual(farGap.baselinePlacement, .belowPlot(value: 95.0))
        XCTAssertGreaterThan(farGap.domain.lowerBound, 108.0)
    }

    func testMinimumVisualSpanPreventsFlatNoiseAmplification() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let flatPoints: [FinancialChartPoint] = [
            FinancialChartPoint(date: baseDate, x: 0, value: 200.00),
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 1, value: 200.01)
        ]

        let solution = FinancialChartYAxisSolver.solve(
            points: flatPoints,
            kind: .line,
            baselinePolicy: .none,
            config: .financialPrice
        )
        let span = solution.domain.upperBound - solution.domain.lowerBound
        // 0.25% of 200 = 0.50 plus 12% breathing padding -> ~0.56
        XCTAssertGreaterThanOrEqual(span, 0.50)
    }

    func testLowPricedOptionUsesAdaptiveTickFloorWithoutDistortion() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let optionPoints: [FinancialChartPoint] = [
            FinancialChartPoint(date: baseDate, x: 0, open: 0.05, high: 0.06, low: 0.04, close: 0.05),
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 1, open: 0.05, high: 0.06, low: 0.04, close: 0.05)
        ]

        let solution = FinancialChartYAxisSolver.solve(
            points: optionPoints,
            kind: .candles,
            baselinePolicy: .none,
            config: .financialPrice
        )
        let span = solution.domain.upperBound - solution.domain.lowerBound
        XCTAssertGreaterThan(span, 0.02)
        XCTAssertLessThan(span, 0.03)
    }

    func testNonNegativeMetricClampsLowerBoundAtZero() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let spreadPoints: [FinancialChartPoint] = [
            FinancialChartPoint(date: baseDate, x: 0, value: 0.0),
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 1, value: 0.02),
            FinancialChartPoint(date: baseDate.addingTimeInterval(120), x: 2, value: 0.0)
        ]

        let solution = FinancialChartYAxisSolver.solve(
            points: spreadPoints,
            kind: .line,
            baselinePolicy: .none,
            config: .nonNegativeMetric
        )
        XCTAssertGreaterThanOrEqual(solution.domain.lowerBound, 0.0)
    }

    // MARK: - Coordinate System & Pixel-Space Doji Tests

    func testPixelSpaceDojiHeightIsIdenticalForPennyOptionAndHighPricedStock() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let size = CGSize(width: 350, height: 250)

        let optionDoji = FinancialChartPoint(date: date, x: 0.5, open: 0.05, high: 0.06, low: 0.04, close: 0.05)
        let optionCoords = FinancialChartCoordinateSystem(
            canvasSize: size,
            insets: .standard,
            xDomain: 0...1,
            yDomain: 0.038...0.062
        )
        let optionBody = optionCoords.candleBodyRect(for: optionDoji, width: 6, minBodyHeight: 1.5)

        let stockDoji = FinancialChartPoint(date: date, x: 0.5, open: 730.0, high: 735.0, low: 725.0, close: 730.0)
        let stockCoords = FinancialChartCoordinateSystem(
            canvasSize: size,
            insets: .standard,
            xDomain: 0...1,
            yDomain: 724.0...736.0
        )
        let stockBody = stockCoords.candleBodyRect(for: stockDoji, width: 6, minBodyHeight: 1.5)

        XCTAssertEqual(optionBody.height, 1.5, accuracy: 1e-4)
        XCTAssertEqual(stockBody.height, 1.5, accuracy: 1e-4)
    }

    func testCoordinateSystemRoundTripAndVolumePartition() {
        let coords = FinancialChartCoordinateSystem(
            canvasSize: CGSize(width: 360, height: 276),
            insets: .standard,
            xDomain: 10...110,
            yDomain: 50...150,
            showsVolume: true
        )

        guard let volumeRect = coords.volumeRect else {
            return XCTFail("Expected non-nil volumeRect when showsVolume is true")
        }

        XCTAssertLessThan(coords.plotRect.maxY, volumeRect.minY)
        XCTAssertEqual(coords.dataX(for: coords.x(for: 42.5)), 42.5, accuracy: 1e-4)
        XCTAssertEqual(coords.price(for: coords.y(for: 123.4)), 123.4, accuracy: 1e-4)

        XCTAssertEqual(coords.candleWidth(visibleCount: 20), 11.4, accuracy: 0.5)
        XCTAssertEqual(coords.candleWidth(visibleCount: 500), 1.8, accuracy: 1e-4)
        XCTAssertEqual(coords.candleWidth(visibleCount: 5), 12.0, accuracy: 1e-4)
    }

    // MARK: - Downsampling, Aggregation & Viewport Tests

    func testLTTBPreservesEndpointsAndExtrema() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var points: [FinancialChartPoint] = []
        for i in 0..<400 {
            let value = i == 150 ? 250.0 : (i == 275 ? 50.0 : 100.0 + sin(Double(i) * 0.1) * 5.0)
            points.append(
                FinancialChartPoint(
                    date: baseDate.addingTimeInterval(Double(i) * 60),
                    x: Double(i),
                    value: value
                )
            )
        }

        let sampled = FinancialChartDownsampler.lttb(points[...], targetCount: 60)

        XCTAssertEqual(sampled.count, 60)
        XCTAssertEqual(sampled.first?.x, 0)
        XCTAssertEqual(sampled.last?.x, 399)
        XCTAssertTrue(sampled.contains(where: { $0.close == 250.0 }))
        XCTAssertTrue(sampled.contains(where: { $0.close == 50.0 }))
    }

    func testCandleAggregationPreservesOHLCVInvariants() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [FinancialChartPoint] = [
            FinancialChartPoint(date: baseDate, x: 0, open: 10, high: 12, low: 9, close: 11, volume: 100),
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 1, open: 11, high: 15, low: 10, close: 14, volume: 250),
            FinancialChartPoint(date: baseDate.addingTimeInterval(120), x: 2, open: 14, high: 14, low: 8, close: 9, volume: 300),
            FinancialChartPoint(date: baseDate.addingTimeInterval(180), x: 3, open: 9, high: 13, low: 9, close: 12, volume: 150)
        ]

        let aggregated = FinancialChartDownsampler.aggregateCandles(points[...], maxCount: 2)

        XCTAssertEqual(aggregated.count, 2)
        XCTAssertEqual(aggregated[0].open, 10)
        XCTAssertEqual(aggregated[0].high, 15)
        XCTAssertEqual(aggregated[0].low, 9)
        XCTAssertEqual(aggregated[0].close, 14)
        XCTAssertEqual(aggregated[0].volume, 350)

        XCTAssertEqual(aggregated[1].open, 14)
        XCTAssertEqual(aggregated[1].high, 14)
        XCTAssertEqual(aggregated[1].low, 8)
        XCTAssertEqual(aggregated[1].close, 12)
        XCTAssertEqual(aggregated[1].volume, 450)
    }

    func testViewportZoomAndPanRespectFullBounds() {
        var viewport = FinancialChartViewport(fullDomain: 0...100, maxZoomScale: 5.0)
        XCTAssertFalse(viewport.isZoomed)

        viewport.zoom(by: 2.0, anchorFraction: 0.5)
        XCTAssertTrue(viewport.isZoomed)
        XCTAssertEqual(viewport.visibleDomain.lowerBound, 25, accuracy: 1e-4)
        XCTAssertEqual(viewport.visibleDomain.upperBound, 75, accuracy: 1e-4)

        // Pan far past left boundary should clamp cleanly to 0...50
        viewport.pan(byFraction: 2.0)
        XCTAssertEqual(viewport.visibleDomain.lowerBound, 0, accuracy: 1e-4)
        XCTAssertEqual(viewport.visibleDomain.upperBound, 50, accuracy: 1e-4)

        // Zoom out past 1x should clamp cleanly to fullDomain
        viewport.zoom(by: 0.1, anchorFraction: 0.5)
        XCTAssertEqual(viewport.visibleDomain.lowerBound, 0, accuracy: 1e-4)
        XCTAssertEqual(viewport.visibleDomain.upperBound, 100, accuracy: 1e-4)
        XCTAssertFalse(viewport.isZoomed)
    }

    func testMonotonePathHasZeroOvershootOnSharpStepJump() {
        let stepPoints: [CGPoint] = [
            CGPoint(x: 0, y: 200),
            CGPoint(x: 50, y: 200),
            CGPoint(x: 100, y: 200),
            CGPoint(x: 105, y: 40),
            CGPoint(x: 150, y: 40),
            CGPoint(x: 200, y: 40)
        ]

        let path = FinancialChartPathBuilder.linePath(through: stepPoints, interpolation: .monotone)
        let bounds = path.boundingRect

        // Must never overshoot above y=40 or below y=200
        XCTAssertGreaterThanOrEqual(bounds.minY, 39.99)
        XCTAssertLessThanOrEqual(bounds.maxY, 200.01)
    }

    func testIntradaySessionMapperSortsAndCapsBars() {
        let barLate = AlpacaMarketBar(symbol: "AAPL", open: 102, high: 103, low: 101, close: 102, volume: 10, vwap: nil, tradeCount: nil, timestamp: "2026-06-17T14:05:00Z")
        let barEarly = AlpacaMarketBar(symbol: "AAPL", open: 100, high: 101, low: 99, close: 100, volume: 10, vwap: nil, tradeCount: nil, timestamp: "2026-06-17T14:00:00Z")
        let barMid = AlpacaMarketBar(symbol: "AAPL", open: 101, high: 102, low: 100, close: 101, volume: 10, vwap: nil, tradeCount: nil, timestamp: "2026-06-17T14:02:00Z")

        let sorted = AssetIntradaySessionMapper.normalizedBars([barLate, barEarly, barMid], maxCount: 2)

        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0].timestamp, barMid.timestamp)
        XCTAssertEqual(sorted[1].timestamp, barLate.timestamp)
    }

    // MARK: - Curve Morphing & Loading Wave Tests

    func testMorphCurveResamplingAndInterpolationAcrossDifferentLengths() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let coords = FinancialChartCoordinateSystem(
            canvasSize: CGSize(width: 320, height: 200),
            insets: .okxSimple,
            xDomain: 0...10,
            yDomain: 0...100
        )

        // Short partial-width 1D curve (x: 0...5, flat at y=20)
        let partialPoints = [
            FinancialChartPoint(date: baseDate, x: 0, value: 20),
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 5, value: 20)
        ]
        // Full-width 1W curve (x: 0...10, flat at y=80)
        let fullPoints = [
            FinancialChartPoint(date: baseDate, x: 0, value: 80),
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 5, value: 80),
            FinancialChartPoint(date: baseDate.addingTimeInterval(120), x: 10, value: 80)
        ]

        let fromCurve = FinancialChartMorphCurve.sample(from: partialPoints, coordinateSystem: coords, sampleCount: 32)
        let toCurve = FinancialChartMorphCurve.sample(from: fullPoints, coordinateSystem: coords, sampleCount: 32)
        let midCurve = FinancialChartMorphCurve.interpolate(from: fromCurve, to: toCurve, progress: 0.5)

        XCTAssertEqual(fromCurve.samples.count, 32)
        XCTAssertEqual(toCurve.samples.count, 32)
        XCTAssertEqual(fromCurve.samples.last?.u ?? -1, 0.5, accuracy: 1e-4)
        XCTAssertEqual(toCurve.samples.last?.u ?? -1, 1.0, accuracy: 1e-4)
        // Midpoint stretches smoothly to 0.75 width and 0.5 vertical center
        XCTAssertEqual(midCurve.samples.last?.u ?? -1, 0.75, accuracy: 1e-4)
        XCTAssertEqual(midCurve.samples.last?.v ?? -1, 0.5, accuracy: 1e-4)
    }

    func testMorphCurveResamplesUniformlyByHorizontalCoordinateAcrossSparseGaps() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let coords = FinancialChartCoordinateSystem(
            canvasSize: CGSize(width: 320, height: 200),
            insets: .okxSimple,
            xDomain: 0...100,
            yDomain: 0...100
        )

        // 50 dense points in [0, 20] followed by a sparse gap to x = 100
        var points: [FinancialChartPoint] = (0..<50).map { i in
            let x = Double(i) * (20.0 / 49.0)
            return FinancialChartPoint(date: baseDate.addingTimeInterval(x), x: x, value: 0)
        }
        points.append(FinancialChartPoint(date: baseDate.addingTimeInterval(99), x: 99, value: 0))
        points.append(FinancialChartPoint(date: baseDate.addingTimeInterval(100), x: 100, value: 100))

        let curve = FinancialChartMorphCurve.sample(from: points, coordinateSystem: coords, sampleCount: 51)
        XCTAssertEqual(curve.samples.count, 51)
        // Middle sample (index 25) must sit at u = 0.50 (NOT clumped inside u <= 0.20)
        XCTAssertEqual(curve.samples[25].u, 0.50, accuracy: 1e-4)
        XCTAssertEqual(curve.samples[25].v, 1.0, accuracy: 1e-4)
        XCTAssertEqual(curve.samples.last?.u ?? -1, 1.0, accuracy: 1e-4)
        XCTAssertEqual(curve.samples.last?.v ?? -1, 0.0, accuracy: 1e-4)
    }

    func testLoadingWaveStaysWithinSafePlotBounds() {
        let wave = FinancialChartMorphCurve.loadingWave(phase: 1.23, sampleCount: 64)
        XCTAssertEqual(wave.samples.count, 64)
        XCTAssertEqual(wave.samples.first?.u ?? -1, 0.0, accuracy: 1e-4)
        XCTAssertEqual(wave.samples.last?.u ?? -1, 1.0, accuracy: 1e-4)
        for sample in wave.samples {
            XCTAssertGreaterThanOrEqual(sample.v, 0.15)
            XCTAssertLessThanOrEqual(sample.v, 0.85)
        }
    }
    func testSeriesIdentityIncludesInteriorAndLatestCandleWicks() {
        let points = (0..<100).map { FinancialChartPoint(date: Date(timeIntervalSince1970: Double($0)), x: Double($0), value: 100) }
        let initial = FinancialChartSeries(kind: .candles, points: points)
        for index in [7, 99] {
            var updated = points
            updated[index] = FinancialChartPoint(date: points[index].date, x: Double(index), open: 100, high: 115, low: 100, close: 100)
            XCTAssertNotEqual(initial.id, FinancialChartSeries(kind: .candles, points: updated).id)
        }
    }

    func testAxisDatesUseVisibleDomainAndLeaveFutureSlotsBlank() {
        let coords = FinancialChartCoordinateSystem(canvasSize: CGSize(width: 500, height: 200),
                                                   insets: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
                                                   xDomain: 20...70, yDomain: 0...100)
        let points = (0...50).map { FinancialChartPoint(date: Date(timeIntervalSince1970: Double($0)), x: Double($0), value: 20) }
        XCTAssertEqual(coords.axisDates(in: points, count: 5).map { $0?.timeIntervalSince1970 }, [25, 35, 45, nil, nil])
    }

    func testAlignedPairMatchesExactTargetVerticesWithZeroEndPop() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let coords = FinancialChartCoordinateSystem(
            canvasSize: CGSize(width: 340, height: 220),
            insets: .okxSimple,
            xDomain: 0...10,
            yDomain: 0...100
        )
        let targetPoints = [
            FinancialChartPoint(date: baseDate, x: 0.0, value: 25),
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 3.17, value: 94.5),
            FinancialChartPoint(date: baseDate.addingTimeInterval(120), x: 3.42, value: 18.0),
            FinancialChartPoint(date: baseDate.addingTimeInterval(180), x: 10.0, value: 72.0)
        ]

        let sourceWave = FinancialChartMorphCurve.loadingWave(phase: 0.5, sampleCount: 64)
        let pair = FinancialChartMorphCurve.alignedPair(
            from: sourceWave,
            to: targetPoints,
            coordinateSystem: coords
        )
        let settledAtOne = FinancialChartMorphCurve.interpolate(from: pair.from, to: pair.to, progress: 1.0)
        let screenPoints = settledAtOne.screenPoints(in: coords.plotRect)

        XCTAssertEqual(pair.from.samples.count, targetPoints.count)
        XCTAssertEqual(screenPoints.count, targetPoints.count)
        for (index, point) in targetPoints.enumerated() {
            let expected = coords.point(forX: point.x, price: point.close)
            XCTAssertEqual(screenPoints[index].x, expected.x, accuracy: 1e-4)
            XCTAssertEqual(screenPoints[index].y, expected.y, accuracy: 1e-4)
        }
    }

    func testBaselineDomainInclusionDecoupledFromReferenceLineVisibility() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [FinancialChartPoint] = [
            FinancialChartPoint(date: baseDate, x: 0, value: 110.0),
            FinancialChartPoint(date: baseDate.addingTimeInterval(60), x: 1, value: 114.0)
        ]

        let alwaysHiddenLine = FinancialChartYAxisSolver.solve(
            points: points,
            kind: .line,
            baselinePolicy: .alwaysInclude(value: 100.0, showsReferenceLine: false),
            config: .financialPrice
        )
        XCTAssertLessThanOrEqual(alwaysHiddenLine.domain.lowerBound, 100.0)
        XCTAssertEqual(alwaysHiddenLine.baselinePlacement, .hidden)

        let softHiddenLine = FinancialChartYAxisSolver.solve(
            points: points,
            kind: .line,
            baselinePolicy: .softInclude(value: 109.0, maxExpansionRatio: 0.55, showsReferenceLine: false),
            config: .financialPrice
        )
        XCTAssertLessThanOrEqual(softHiddenLine.domain.lowerBound, 109.0)
        XCTAssertEqual(softHiddenLine.baselinePlacement, .hidden)
    }

    func testInterpolatedScreenPointsMatchesInterpolateAndProject() {
        let plotRect = CGRect(x: 10, y: 20, width: 300, height: 180)
        let fromCurve = FinancialChartMorphCurve.loadingWave(phase: 0.25, sampleCount: 32)
        let toCurve = FinancialChartMorphCurve.loadingWave(phase: 1.75, sampleCount: 32)

        for progress: CGFloat in [0.0, 0.37, 1.0] {
            let direct = FinancialChartMorphCurve.interpolatedScreenPoints(
                from: fromCurve,
                to: toCurve,
                progress: progress,
                in: plotRect
            )
            let reference = FinancialChartMorphCurve.interpolate(
                from: fromCurve,
                to: toCurve,
                progress: progress
            ).screenPoints(in: plotRect)

            XCTAssertEqual(direct.count, reference.count)
            for (lhs, rhs) in zip(direct, reference) {
                XCTAssertEqual(lhs.x, rhs.x, accuracy: 1e-4)
                XCTAssertEqual(lhs.y, rhs.y, accuracy: 1e-4)
            }
        }
    }

    func testPrecomputedPointsDigestMatchesFullSeriesDigest() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var points: [FinancialChartPoint] = []
        points.reserveCapacity(40)
        for i in 0..<40 {
            let offset = Double(i)
            points.append(
                FinancialChartPoint(
                    date: baseDate.addingTimeInterval(offset * 60),
                    x: offset,
                    open: 100 + offset,
                    high: 102 + offset,
                    low: 99 + offset,
                    close: 101 + offset,
                    volume: offset * 10
                )
            )
        }

        let digest = FinancialChartSeries.pointsDigest(for: points)
        let direct = FinancialChartSeries(kind: .area, points: points, xDomain: 0...40, baselinePolicy: .none)
        let cached = FinancialChartSeries(pointsDigest: digest, kind: .area, points: points, xDomain: 0...40, baselinePolicy: .none)

        XCTAssertEqual(direct.id, cached.id)
    }

    func testCandleExtremaPriceFormattingPreservesSubDollarPrecision() {
        XCTAssertEqual(FinancialChartBaseCanvas.formatExtremaPrice(0.0425), "$0.0425")
        XCTAssertEqual(FinancialChartBaseCanvas.formatExtremaPrice(0.425), "$0.425")
        XCTAssertEqual(FinancialChartBaseCanvas.formatExtremaPrice(182.45), "$182.45")
    }

    // MARK: - Non-Intraday Trade Marker Mapping & Layout Tests

    func testTradeMarkerMapperIgnoresIntradayRange() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            FinancialChartPoint(date: base, x: 0, value: 100),
            FinancialChartPoint(date: base.addingTimeInterval(300), x: 1, value: 101)
        ]
        let executions = [
            AssetTradeExecution(id: "1", symbol: "AAPL", side: .buy, executedAt: base.addingTimeInterval(60), quantity: 10, price: 100.5)
        ]

        let intradayResult = AssetTradeMarkerMapper.map(executions: executions, onto: points, range: .oneDay)
        XCTAssertTrue(intradayResult.isEmpty)
    }

    func testTradeMarkerMapperAggregatesSameDayFillsAndSeparatesSides() {
        let formatter = ISO8601DateFormatter()
        let day1Bar = formatter.date(from: "2026-10-12T04:00:00Z")!
        let day2Bar = formatter.date(from: "2026-10-13T04:00:00Z")!
        let day3Bar = formatter.date(from: "2026-10-14T04:00:00Z")!

        let points = [
            FinancialChartPoint(date: day1Bar, x: 0, open: 100, high: 105, low: 98, close: 104),
            FinancialChartPoint(date: day2Bar, x: 1, open: 104, high: 112, low: 103, close: 110),
            FinancialChartPoint(date: day3Bar, x: 2, open: 110, high: 115, low: 108, close: 112)
        ]

        let executions = [
            // Two buys on Day 1: 10 @ 100 + 30 @ 104 => 40 @ 103
            AssetTradeExecution(id: "b1", symbol: "AAPL", side: .buy, executedAt: formatter.date(from: "2026-10-12T14:30:00Z")!, quantity: 10, price: 100),
            AssetTradeExecution(id: "b2", symbol: "AAPL", side: .buy, executedAt: formatter.date(from: "2026-10-12T18:00:00Z")!, quantity: 30, price: 104),
            // Same-day sell on Day 1
            AssetTradeExecution(id: "s1", symbol: "AAPL", side: .sell, executedAt: formatter.date(from: "2026-10-12T19:30:00Z")!, quantity: 5, price: 105),
            // Execution outside range should be excluded
            AssetTradeExecution(id: "old", symbol: "AAPL", side: .buy, executedAt: formatter.date(from: "2026-09-01T15:00:00Z")!, quantity: 20, price: 90)
        ]

        let result = AssetTradeMarkerMapper.map(executions: executions, onto: points, range: .oneMonth)
        XCTAssertEqual(result.markers.count, 2)
        XCTAssertEqual(result.markers[0].side, .buy)
        XCTAssertEqual(result.markers[0].x, 0)
        XCTAssertEqual(result.markers[0].totalQuantity, 40, accuracy: 1e-6)
        XCTAssertEqual(result.markers[0].averagePrice, 103.0, accuracy: 1e-6)
        XCTAssertEqual(result.markers[0].fillCount, 2)

        XCTAssertEqual(result.markers[1].side, .sell)
        XCTAssertEqual(result.markers[1].x, 0)
        XCTAssertEqual(result.markers[1].totalQuantity, 5, accuracy: 1e-6)
        XCTAssertEqual(result.markers[1].averagePrice, 105.0, accuracy: 1e-6)
        XCTAssertEqual(result.markers[1].fillCount, 1)

        // O(1) scrubbing lookup finds both buy and sell on day 1
        let lookedUp = result.markers(for: AssetChartPoint(financialPoint: points[0]))
        XCTAssertEqual(lookedUp.count, 2)
    }

    func testTradeMarkerLayoutClustersNearbyMarkersAndSeparatesTracks() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<100).map { idx in
            FinancialChartPoint(
                date: baseDate.addingTimeInterval(Double(idx) * 86_400),
                x: Double(idx),
                open: 100,
                high: 105,
                low: 95,
                close: 100
            )
        }

        let coords = FinancialChartCoordinateSystem(
            canvasSize: CGSize(width: 340, height: 228),
            insets: .okxSimple,
            xDomain: 0...99,
            yDomain: 90...110
        )

        // Two buys 1 bar apart (~3.2pt apart < 18pt min spacing) should cluster into 1 visual badge,
        // while a sell on the exact same bar remains on its separate upper track.
        let markers = [
            FinancialChartTradeMarker(id: "b1", side: .buy, x: 50, barDate: points[50].date, averagePrice: 99, totalQuantity: 10, fillCount: 1, barClose: 100, barHigh: 105, barLow: 95),
            FinancialChartTradeMarker(id: "s1", side: .sell, x: 50, barDate: points[50].date, averagePrice: 103, totalQuantity: 5, fillCount: 1, barClose: 100, barHigh: 105, barLow: 95),
            FinancialChartTradeMarker(id: "b2", side: .buy, x: 51, barDate: points[51].date, averagePrice: 98, totalQuantity: 20, fillCount: 2, barClose: 100, barHigh: 105, barLow: 95)
        ]

        let placed = FinancialChartTradeMarkerLayout.place(
            markers: markers,
            displayPoints: points,
            kind: .area,
            coordinateSystem: coords
        )

        let placedBuys = placed.filter { $0.side == .buy }
        let placedSells = placed.filter { $0.side == .sell }
        XCTAssertEqual(placedBuys.count, 1)
        XCTAssertEqual(placedBuys[0].clusterCount, 3)
        XCTAssertTrue(placedBuys[0].isBelowAnchor)
        XCTAssertEqual(placedSells.count, 1)
        XCTAssertFalse(placedSells[0].isBelowAnchor)
        XCTAssertLessThan(placedSells[0].badgeCenter.y, placedBuys[0].badgeCenter.y)
    }

    func testTradeMarkerSeriesDigestChangesWhenMarkersToggle() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            FinancialChartPoint(date: baseDate, x: 0, value: 100),
            FinancialChartPoint(date: baseDate.addingTimeInterval(86_400), x: 1, value: 105)
        ]
        let marker = FinancialChartTradeMarker(
            id: "0-buy",
            side: .buy,
            x: 0,
            barDate: baseDate,
            averagePrice: 100,
            totalQuantity: 10,
            fillCount: 1,
            barClose: 100,
            barHigh: 101,
            barLow: 99
        )

        let withoutMarkers = FinancialChartSeries(kind: .area, points: points)
        let withMarkers = FinancialChartSeries(kind: .area, points: points, tradeMarkers: [marker])
        XCTAssertNotEqual(withoutMarkers.id, withMarkers.id)
    }
}
