import SwiftUI
import UIKit

/// High-performance, modular native financial chart supporting Line, Area, and Candlestick modes.
///
/// Key architectural traits:
/// - Layered rendering: `FinancialChartBaseCanvas` (Equatable) is decoupled from high-frequency crosshair scrubbing.
/// - Liquid period-switch transitions: 120fps geometric curve morphing (`FinancialChartMorphingCanvas`),
///   flowing dot-matrix wave on cold load, and subtle light-sweep shimmer while fetching—no harsh skeleton boxes.
/// - Zero-redraw GPU split-highlight mask during scrubbing.
/// - Pixel-accurate vertical proportions via `FinancialChartYAxisSolver` + `FinancialChartCoordinateSystem`.
struct FinancialChartView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let series: FinancialChartSeries
    let style: FinancialChartStyle
    let insets: FinancialChartInsets
    let isLoading: Bool
    let transitionKey: String
    let selectionLabel: (FinancialChartPoint) -> String
    @Binding var selection: FinancialChartSelection?
    @Binding var isScrubbing: Bool

    @State private var viewport: FinancialChartViewport
    @State private var lastHapticPointID: TimeInterval?
    @State private var scrubSplitX: CGFloat = 0
    @State private var trailingDimOpacity: Double = 1.0
    @State private var scrubAxisDates: [Date?] = []

    // Liquid transition, morphing & O(1) scrub snapshot cache
    @State private var heldSnapshot: FinancialChartRenderSnapshot?
    @State private var cachedSnapshotKey: SnapshotCacheKey?
    @State private var lastSettledKey: String = ""
    @State private var lastSettledCurve: FinancialChartMorphCurve?
    @State private var lastSettledColor: Color?
    @State private var lastSettledReferenceY: CGFloat?
    @State private var morphFromCurve: FinancialChartMorphCurve?
    @State private var morphToCurve: FinancialChartMorphCurve?
    @State private var morphFromColor: Color?
    @State private var morphToColor: Color?
    @State private var morphFromRGBA: FinancialChartRGBAColor?
    @State private var morphToRGBA: FinancialChartRGBAColor?
    @State private var morphFromReferenceY: CGFloat?
    @State private var morphToReferenceY: CGFloat?
    @State private var morphStartedAt: TimeInterval = 0
    @State private var morphBaseStep: CGFloat = 0
    @State private var morphAnimatedStep: CGFloat = 0
    @State private var isMorphing = false
    @State private var morphGeneration = 0
    @State private var morphFinishTask: Task<Void, Never>?

    private static let feedbackGenerator = UISelectionFeedbackGenerator()
    private static let scrubbedTrailingOpacityDark: Double = 0.24
    private static let scrubbedTrailingOpacityLight: Double = 0.22
    private static let morphDuration: Double = 0.44

    init(
        series: FinancialChartSeries,
        style: FinancialChartStyle,
        insets: FinancialChartInsets = .standard,
        isLoading: Bool = false,
        transitionKey: String = "",
        selection: Binding<FinancialChartSelection?>,
        isScrubbing: Binding<Bool>,
        selectionLabel: @escaping (FinancialChartPoint) -> String
    ) {
        self.series = series
        self.style = style
        self.insets = insets
        self.isLoading = isLoading
        self.transitionKey = transitionKey
        self._selection = selection
        self._isScrubbing = isScrubbing
        self.selectionLabel = selectionLabel
        self._viewport = State(initialValue: FinancialChartViewport(fullDomain: series.xDomain))
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let hasLiveSeries = series.points.count >= 2 || (series.kind == .candles && !series.points.isEmpty)
            let styleFingerprint = Self.styleFingerprint(style)
            let currentSnapshotKey = SnapshotCacheKey(
                seriesID: series.id,
                visibleXLower: resolvedVisibleXDomain.lowerBound,
                visibleXUpper: resolvedVisibleXDomain.upperBound,
                widthTenths: Int((size.width * 10).rounded()),
                heightTenths: Int((size.height * 10).rounded()),
                isDarkMode: colorScheme == .dark,
                styleFingerprint: styleFingerprint
            )
            // O(1) cache hit during 120Hz scrubbing: skips LTTB downsampling & Y-axis solving completely.
            let liveSnapshot: FinancialChartRenderSnapshot? = if !hasLiveSeries {
                nil
            } else if cachedSnapshotKey == currentSnapshotKey, let heldSnapshot {
                heldSnapshot
            } else {
                makeSnapshot(in: size, styleFingerprint: styleFingerprint)
            }
            let activeSnapshot: FinancialChartRenderSnapshot? = isLoading
                ? (heldSnapshot ?? liveSnapshot)
                : liveSnapshot
            let activeCoords = activeSnapshot?.coordinateSystem
            let activeScrubX = selection.flatMap { sel in
                activeCoords?.x(for: sel.point.x)
            } ?? scrubSplitX
            let splitX = min(max(activeScrubX, 0), size.width)
            let syncToken = RenderSyncToken(
                transitionKey: transitionKey,
                seriesID: series.id,
                kind: series.kind,
                isLoading: isLoading,
                hasData: hasLiveSeries,
                widthBucket: Int(size.width.rounded()),
                heightBucket: Int(size.height.rounded()),
                styleFingerprint: styleFingerprint,
                isDarkMode: colorScheme == .dark
            )

            ZStack(alignment: .topLeading) {
                if let activeSnapshot {
                    let isShowingMorph = isMorphing &&
                        activeSnapshot.kind != .candles &&
                        !isLoading &&
                        !isScrubbing &&
                        morphFromCurve != nil &&
                        morphToCurve != nil

                    Group {
                        if isShowingMorph,
                           let fromCurve = morphFromCurve,
                           let toCurve = morphToCurve {
                            FinancialChartMorphingCanvas(
                                fromCurve: fromCurve,
                                toCurve: toCurve,
                                fromColor: morphFromColor ?? activeSnapshot.style.lineColor,
                                toColor: morphToColor ?? activeSnapshot.style.lineColor,
                                fromRGBA: morphFromRGBA,
                                toRGBA: morphToRGBA,
                                fromReferenceY: morphFromReferenceY,
                                toReferenceY: morphToReferenceY,
                                plotRect: activeSnapshot.coordinateSystem.plotRect,
                                areaBaselineY: activeSnapshot.areaBaselineY,
                                style: activeSnapshot.style,
                                fillsArea: activeSnapshot.kind == .area,
                                showsEndpointDot: activeSnapshot.style.showsEndpointPulse && !viewport.isZoomed,
                                toTradeMarkers: activeSnapshot.placedTradeMarkers,
                                isDarkMode: activeSnapshot.isDarkMode,
                                baseStep: morphBaseStep,
                                animatedStep: morphAnimatedStep
                            )
                        } else {
                            FinancialChartBaseCanvas(snapshot: activeSnapshot)
                                .equatable()
                        }
                    }
                    .mask {
                        if isLoading {
                            FinancialChartLoadingSweepMask(isActive: true)
                        } else {
                            // Pure GPU compositing mask: dims the trailing half to the right of the crosshair
                            // at 120Hz with zero Canvas redraws of the underlying dot-matrix/line layer.
                            HStack(spacing: 0) {
                                Color.white
                                    .frame(width: splitX)
                                    .transaction { transaction in
                                        transaction.animation = nil
                                    }
                                Color.white
                                    .opacity(trailingDimOpacity)
                                    .frame(maxWidth: .infinity)
                                    .animation(.easeOut(duration: 0.16), value: trailingDimOpacity)
                            }
                        }
                    }

                    FinancialChartCrosshairOverlay(
                        kind: activeSnapshot.kind,
                        latestPoint: activeSnapshot.displayPoints.last,
                        selection: selection,
                        selectionLabel: selection.map { selectionLabel($0.point) },
                        coordinateSystem: activeSnapshot.coordinateSystem,
                        style: activeSnapshot.style,
                        showsEndpointPulse: !isLoading && !isMorphing && !viewport.isZoomed
                    )

                    if !isLoading {
                        FinancialChartGestureOverlay(
                            allowsZoomAndPan: series.allowsZoomAndPan && series.points.count >= 8,
                            isZoomed: viewport.isZoomed,
                            onScrubChanged: { location in
                                handleScrub(
                                    at: location,
                                    coordinateSystem: activeSnapshot.coordinateSystem,
                                    activePoints: activeSnapshot.displayPoints
                                )
                            },
                            onScrubEnded: {
                                clearSelection()
                            },
                            onPinchChanged: { factor, anchorFraction in
                                guard series.allowsZoomAndPan else { return }
                                viewport.zoom(by: factor, anchorFraction: anchorFraction)
                            },
                            onPanChanged: { deltaFraction in
                                guard series.allowsZoomAndPan else { return }
                                viewport.pan(byFraction: deltaFraction)
                            },
                            onDoubleTapReset: {
                                withAnimation(.snappy(duration: 0.2)) {
                                    viewport.reset(to: series.xDomain)
                                }
                            }
                        )
                    }
                } else if isLoading {
                    FinancialChartLoadingWaveView(
                        tint: style.lineColor,
                        insets: insets
                    )
                } else {
                    Text(AppFormatter.placeholder)
                        .font(AppTypography.detail)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: size.width, height: size.height)
            .onAppear {
                syncRenderState(liveSnapshot: liveSnapshot, cacheKey: currentSnapshotKey)
            }
            .onChange(of: syncToken) { _, _ in
                syncRenderState(liveSnapshot: liveSnapshot, cacheKey: currentSnapshotKey)
            }
            .onChange(of: viewport.visibleDomain) { _, _ in
                if !isLoading, let liveSnapshot {
                    heldSnapshot = liveSnapshot
                    cachedSnapshotKey = currentSnapshotKey
                }
            }
        }
        .onChange(of: series.xDomain) { _, newDomain in
            viewport.reset(to: newDomain)
        }
        .onChange(of: series.kind) { _, _ in
            viewport.reset(to: series.xDomain)
            clearSelection()
        }
        .onDisappear {
            morphFinishTask?.cancel()
            morphFinishTask = nil
        }
    }

    private func makeSnapshot(in size: CGSize, styleFingerprint: Int) -> FinancialChartRenderSnapshot {
        let activeXDomain = resolvedVisibleXDomain
        let visibleSlice = FinancialChartDownsampler.visibleSlice(
            in: series.points,
            xDomain: activeXDomain
        )
        let displayPoints = Self.prepareDisplayPoints(
            from: visibleSlice,
            kind: series.kind,
            plotWidth: max(size.width - insets.leading - insets.trailing, 1)
        )
        let ySolution = FinancialChartYAxisSolver.solve(
            points: visibleSlice,
            kind: series.kind,
            baselinePolicy: series.baselinePolicy,
            config: series.yScaleConfig
        )
        let showsVolume = style.showsVolume && hasVolumeData(in: displayPoints)
        let coordinateSystem = FinancialChartCoordinateSystem(
            canvasSize: size,
            insets: insets,
            xDomain: activeXDomain,
            yDomain: ySolution.domain,
            showsVolume: showsVolume
        )
        let visibleBarCount = max(displayPoints.count, 1)
        let candleWidth = coordinateSystem.candleWidth(visibleCount: visibleBarCount)
        let wickWidth = coordinateSystem.wickWidth(forCandleWidth: candleWidth)
        let maxVolume = showsVolume ? (displayPoints.map(\.volume).max() ?? 0) : 0
        let areaBaselineY = resolvedAreaBaselineY(
            coordinateSystem: coordinateSystem,
            ySolution: ySolution
        )
        let placedTradeMarkers = FinancialChartTradeMarkerLayout.place(
            markers: series.tradeMarkers,
            displayPoints: displayPoints,
            kind: series.kind,
            coordinateSystem: coordinateSystem
        )

        return FinancialChartRenderSnapshot(
            seriesID: series.id,
            kind: series.kind,
            displayPoints: displayPoints,
            placedTradeMarkers: placedTradeMarkers,
            coordinateSystem: coordinateSystem,
            ySolution: ySolution,
            maxVolume: maxVolume,
            candleWidth: candleWidth,
            wickWidth: wickWidth,
            areaBaselineY: areaBaselineY,
            isDarkMode: colorScheme == .dark,
            styleFingerprint: styleFingerprint,
            style: style
        )
    }

    private func syncRenderState(liveSnapshot: FinancialChartRenderSnapshot?, cacheKey: SnapshotCacheKey) {
        // While fetching a newly requested range, hold the previous settled chart steady
        // so the horizontal shimmer sweeps cleanly across it instead of flashing blank.
        guard !isLoading else {
            return
        }

        guard let liveSnapshot else {
            heldSnapshot = nil
            cachedSnapshotKey = nil
            lastSettledCurve = nil
            lastSettledReferenceY = nil
            isMorphing = false
            return
        }

        let targetCurve = FinancialChartMorphCurve.exact(
            from: liveSnapshot.displayPoints,
            coordinateSystem: liveSnapshot.coordinateSystem
        )
        let targetReferenceY = referenceLineY(for: liveSnapshot)
        let keyChanged = !transitionKey.isEmpty && transitionKey != lastSettledKey
        let wasColdStart = heldSnapshot == nil && lastSettledCurve == nil
        let canMorph = !reduceMotion && liveSnapshot.kind != .candles && !isScrubbing && (keyChanged || wasColdStart)

        if canMorph {
            let now = Date().timeIntervalSinceReferenceDate
            let rawStartCurve: FinancialChartMorphCurve
            let startColor: Color
            let startReferenceY: CGFloat?

            if isMorphing,
               let activeFrom = morphFromCurve,
               let activeTo = morphToCurve {
                // Smoothly capture mid-flight visual state when user switches periods rapidly!
                let liveT = FinancialChartMorphCurve.approximateEaseOutProgress(
                    elapsed: now - morphStartedAt,
                    duration: Self.morphDuration
                )
                rawStartCurve = FinancialChartMorphCurve.interpolate(from: activeFrom, to: activeTo, progress: liveT)
                startColor = FinancialChartColorBlender.blend(
                    from: morphFromColor ?? liveSnapshot.style.lineColor,
                    to: morphToColor ?? liveSnapshot.style.lineColor,
                    fromRGBA: morphFromRGBA,
                    toRGBA: morphToRGBA,
                    progress: liveT,
                    isDarkMode: liveSnapshot.isDarkMode
                )
                if let r1 = morphFromReferenceY, let r2 = morphToReferenceY {
                    startReferenceY = r1 + (r2 - r1) * liveT
                } else {
                    startReferenceY = liveT < 0.5 ? morphFromReferenceY : morphToReferenceY
                }
            } else if let existingCurve = lastSettledCurve {
                rawStartCurve = existingCurve
                startColor = lastSettledColor ?? liveSnapshot.style.lineColor
                startReferenceY = lastSettledReferenceY
            } else {
                // Morph organically from the live ambient loading wave into the real price series.
                rawStartCurve = FinancialChartMorphCurve.loadingWave(
                    phase: now * 2.15,
                    sampleCount: max(targetCurve.samples.count, 2)
                )
                startColor = liveSnapshot.style.lineColor.opacity(0.55)
                startReferenceY = nil
            }

            // Align source vertices 1:1 with exact target displayPoints so t == 1.0 matches
            // FinancialChartBaseCanvas pixel-for-pixel with zero end-of-morph peak pop.
            let alignedFrom = rawStartCurve.resampled(toMatch: targetCurve)

            morphFinishTask?.cancel()
            morphGeneration += 1
            let generation = morphGeneration

            morphFromCurve = alignedFrom
            morphToCurve = targetCurve
            morphFromColor = startColor
            morphToColor = liveSnapshot.style.lineColor
            morphFromRGBA = FinancialChartRGBAColor.resolve(startColor, isDarkMode: liveSnapshot.isDarkMode)
            morphToRGBA = FinancialChartRGBAColor.resolve(liveSnapshot.style.lineColor, isDarkMode: liveSnapshot.isDarkMode)
            morphFromReferenceY = startReferenceY
            morphToReferenceY = targetReferenceY
            morphStartedAt = now
            isMorphing = true

            // Monotonically advance step (N -> N + 1) so SwiftUI never coalesces a 1->0->1 reset.
            let nextBase = morphAnimatedStep
            morphBaseStep = nextBase
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: Self.morphDuration)) {
                morphAnimatedStep = nextBase + 1.0
            }

            morphFinishTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(Int(Self.morphDuration * 1000) + 40))
                } catch {
                    return
                }
                guard !Task.isCancelled, morphGeneration == generation else {
                    return
                }
                isMorphing = false
            }
        } else if !isMorphing {
            morphToCurve = targetCurve
        }

        heldSnapshot = liveSnapshot
        cachedSnapshotKey = cacheKey
        lastSettledKey = transitionKey
        lastSettledCurve = targetCurve
        lastSettledColor = liveSnapshot.style.lineColor
        lastSettledReferenceY = targetReferenceY
    }

    private func referenceLineY(for snapshot: FinancialChartRenderSnapshot) -> CGFloat? {
        guard case .inPlot(let value) = snapshot.ySolution.baselinePlacement else {
            return nil
        }
        return snapshot.coordinateSystem.y(for: value)
    }

    private var resolvedVisibleXDomain: ClosedRange<Double> {
        let baseDomain = series.allowsZoomAndPan ? viewport.visibleDomain : series.xDomain
        let lower = baseDomain.lowerBound
        let upper = baseDomain.upperBound
        let span = upper - lower
        guard span.isFinite, span > 0 else {
            return baseDomain
        }

        if series.kind == .candles {
            let count = max(Double(series.points.count), 2)
            let halfStep = max(span / (count * 2.0), span * 0.015)
            return (lower - halfStep)...(upper + halfStep)
        }

        return baseDomain
    }

    private func resolvedAreaBaselineY(
        coordinateSystem: FinancialChartCoordinateSystem,
        ySolution: FinancialChartYAxisSolution
    ) -> CGFloat {
        // Dot-matrix area fill always anchors strictly to the bottom of the plot,
        // matching OKX/Coinbase even when price trades below the previous-close reference line.
        if case .dotMatrix = style.areaFillStyle {
            return coordinateSystem.plotRect.maxY
        }
        if let reference = series.baselinePolicy.referenceValue,
           case .inPlot = ySolution.baselinePlacement {
            return min(max(coordinateSystem.y(for: reference), coordinateSystem.plotRect.minY), coordinateSystem.plotRect.maxY)
        }
        return coordinateSystem.plotRect.maxY
    }

    private func hasVolumeData(in points: [FinancialChartPoint]) -> Bool {
        points.contains { $0.volume > 0 }
    }

    private func handleScrub(
        at location: CGPoint,
        coordinateSystem: FinancialChartCoordinateSystem,
        activePoints: [FinancialChartPoint]
    ) {
        let lookupPoints = series.kind == .candles ? activePoints : series.points
        guard !lookupPoints.isEmpty else {
            return
        }

        if isMorphing {
            morphFinishTask?.cancel()
            isMorphing = false
            morphBaseStep = morphAnimatedStep
        }

        if !isScrubbing {
            isScrubbing = true
            scrubAxisDates = coordinateSystem.axisDates(in: lookupPoints, count: 5)
            Self.feedbackGenerator.prepare()
            let targetDimOpacity = colorScheme == .dark
                ? Self.scrubbedTrailingOpacityDark
                : Self.scrubbedTrailingOpacityLight
            withAnimation(.easeOut(duration: 0.14)) {
                trailingDimOpacity = targetDimOpacity
            }
        } else if scrubAxisDates.isEmpty {
            scrubAxisDates = coordinateSystem.axisDates(in: lookupPoints, count: 5)
        }

        let targetX = coordinateSystem.dataX(for: location.x)
        guard let index = FinancialChartDownsampler.nearestIndex(in: lookupPoints, toX: targetX) else {
            return
        }

        let nearest = lookupPoints[index]
        scrubSplitX = coordinateSystem.x(for: nearest.x)
        guard selection?.point.id != nearest.id else {
            return
        }

        if lastHapticPointID != nearest.id {
            Self.feedbackGenerator.selectionChanged()
            lastHapticPointID = nearest.id
        }

        selection = FinancialChartSelection(point: nearest, index: index, axisDates: scrubAxisDates)
    }

    private func clearSelection() {
        selection = nil
        isScrubbing = false
        lastHapticPointID = nil
        scrubAxisDates = []
        withAnimation(.easeOut(duration: 0.18)) {
            trailingDimOpacity = 1.0
        }
    }

    private static func prepareDisplayPoints(
        from slice: ArraySlice<FinancialChartPoint>,
        kind: FinancialChartKind,
        plotWidth: CGFloat
    ) -> [FinancialChartPoint] {
        switch kind {
        case .line, .area:
            // Match morph curve sampling density (~1 vertex per 3pt) so curves stay consistently
            // smooth & rounded before, during, and after period transitions without snapping sharp.
            let maxVertices = min(max(Int(plotWidth / 3.0), 96), 128)
            return FinancialChartDownsampler.lttb(slice, targetCount: maxVertices)
        case .candles:
            let maxCandles = max(Int(plotWidth / 3.2), 45)
            return FinancialChartDownsampler.aggregateCandles(slice, maxCount: min(maxCandles, 160))
        }
    }

    private static func styleFingerprint(_ style: FinancialChartStyle) -> Int {
        var hasher = Hasher()
        hasher.combine(style.lineColor)
        hasher.combine(style.positiveColor)
        hasher.combine(style.negativeColor)
        hasher.combine(style.areaFillStyle)
        hasher.combine(style.areaTopOpacity)
        hasher.combine(style.areaBottomOpacity)
        hasher.combine(style.lineWidth)
        hasher.combine(style.glowRadius)
        hasher.combine(style.glowOpacity)
        hasher.combine(style.lineHighlightColor)
        hasher.combine(style.lineHighlightWidth)
        hasher.combine(style.gridColor)
        hasher.combine(style.referenceLineColor)
        hasher.combine(style.volumeOpacity)
        hasher.combine(style.showsGrid)
        hasher.combine(style.showsVolume)
        hasher.combine(style.showsHighLowCallouts)
        hasher.combine(style.interpolation)
        return hasher.finalize()
    }
}

private struct SnapshotCacheKey: Equatable {
    let seriesID: Int
    let visibleXLower: Double
    let visibleXUpper: Double
    let widthTenths: Int
    let heightTenths: Int
    let isDarkMode: Bool
    let styleFingerprint: Int
}

private struct RenderSyncToken: Equatable {
    let transitionKey: String
    let seriesID: Int
    let kind: FinancialChartKind
    let isLoading: Bool
    let hasData: Bool
    let widthBucket: Int
    let heightBucket: Int
    let styleFingerprint: Int
    let isDarkMode: Bool
}

/// Non-interactive static sparkline chart built on the exact same `VicuCharts` engine.
/// Safe for offscreen `ImageRenderer` snapshots (share cards) and compact inline metrics.
struct StaticSparklineChartView: View {
    @Environment(\.colorScheme) private var colorScheme
    let series: FinancialChartSeries
    let style: FinancialChartStyle
    let insets: FinancialChartInsets
    let showsEndpointDot: Bool
    let maxPointCount: Int

    init(
        series: FinancialChartSeries,
        style: FinancialChartStyle,
        insets: FinancialChartInsets = .sparkline,
        showsEndpointDot: Bool = true,
        maxPointCount: Int = 180
    ) {
        self.series = series
        self.style = style
        self.insets = insets
        self.showsEndpointDot = showsEndpointDot
        self.maxPointCount = maxPointCount
    }

    var body: some View {
        let isDarkMode = colorScheme == .dark

        Canvas { context, size in
            guard size.width > 1, size.height > 1 else {
                return
            }

            let ySolution = FinancialChartYAxisSolver.solve(
                points: series.points,
                kind: series.kind,
                baselinePolicy: series.baselinePolicy,
                config: series.yScaleConfig
            )
            let coords = FinancialChartCoordinateSystem(
                canvasSize: size,
                insets: insets,
                xDomain: series.xDomain,
                yDomain: ySolution.domain,
                showsVolume: false
            )

            if style.showsGrid {
                drawGrid(context: &context, size: size, color: style.gridColor)
            }

            let sampled = FinancialChartDownsampler.lttb(series.points[...], targetCount: maxPointCount)
            guard sampled.count >= 2 else {
                drawEmptyLine(context: &context, size: size)
                return
            }

            let screenPoints = sampled.map { coords.point(forX: $0.x, price: $0.close) }
            guard let last = screenPoints.last else { return }

            FinancialChartAreaRenderer.drawLineAndArea(
                context: &context,
                size: size,
                screenPoints: screenPoints,
                plotRect: coords.plotRect,
                areaBaselineY: coords.plotRect.maxY,
                style: style,
                fillsArea: series.kind == .area,
                isDarkMode: isDarkMode
            )

            if showsEndpointDot {
                context.fill(
                    Path(ellipseIn: CGRect(x: last.x - 6, y: last.y - 6, width: 12, height: 12)),
                    with: .color(style.lineColor)
                )
                context.stroke(
                    Path(ellipseIn: CGRect(x: last.x - 9, y: last.y - 9, width: 18, height: 18)),
                    with: .color(style.lineColor.opacity(0.30)),
                    lineWidth: 3
                )
            }
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize, color: Color) {
        var gridPath = Path()
        for index in 1..<4 {
            let y = size.height * CGFloat(index) / 4.0
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
        }
        for index in 1..<5 {
            let x = size.width * CGFloat(index) / 5.0
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
        }
        context.stroke(gridPath, with: .color(color), lineWidth: 1)
    }

    private func drawEmptyLine(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height * 0.58))
        path.addLine(to: CGPoint(x: size.width, y: size.height * 0.42))
        context.stroke(
            path,
            with: .color(style.lineColor.opacity(0.35)),
            style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round)
        )
    }
}
