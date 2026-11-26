import SwiftUI
import UIKit

struct FinancialChartRenderSnapshot: Equatable, Sendable {
    let seriesID: Int
    let kind: FinancialChartKind
    let displayPoints: [FinancialChartPoint]
    let placedTradeMarkers: [FinancialChartPlacedTradeMarker]
    let coordinateSystem: FinancialChartCoordinateSystem
    let ySolution: FinancialChartYAxisSolution
    let maxVolume: Double
    let candleWidth: CGFloat
    let wickWidth: CGFloat
    let areaBaselineY: CGFloat
    let isDarkMode: Bool
    let styleFingerprint: Int
    let style: FinancialChartStyle

    static func == (lhs: FinancialChartRenderSnapshot, rhs: FinancialChartRenderSnapshot) -> Bool {
        lhs.seriesID == rhs.seriesID &&
            lhs.kind == rhs.kind &&
            lhs.coordinateSystem == rhs.coordinateSystem &&
            lhs.ySolution == rhs.ySolution &&
            lhs.maxVolume == rhs.maxVolume &&
            lhs.candleWidth == rhs.candleWidth &&
            lhs.wickWidth == rhs.wickWidth &&
            lhs.areaBaselineY == rhs.areaBaselineY &&
            lhs.isDarkMode == rhs.isDarkMode &&
            lhs.styleFingerprint == rhs.styleFingerprint &&
            lhs.displayPoints.count == rhs.displayPoints.count &&
            lhs.displayPoints.first == rhs.displayPoints.first &&
            lhs.displayPoints.last == rhs.displayPoints.last &&
            lhs.placedTradeMarkers == rhs.placedTradeMarkers
    }
}

/// Hardware-accelerated static/data layer Canvas.
/// Isolated via `Equatable` so high-frequency crosshair scrubbing never triggers a redraw of the main plot.
struct FinancialChartBaseCanvas: View, Equatable {
    let snapshot: FinancialChartRenderSnapshot

    nonisolated static func == (lhs: FinancialChartBaseCanvas, rhs: FinancialChartBaseCanvas) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        let isDarkMode = snapshot.isDarkMode

        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 1, size.height > 1 else {
                return
            }

            let coords = snapshot.coordinateSystem
            let style = snapshot.style

            if style.showsGrid {
                drawGrid(context: &context, size: size, plotRect: coords.plotRect, color: style.gridColor)
            }

            if case .inPlot(let referenceValue) = snapshot.ySolution.baselinePlacement {
                drawReferenceLine(
                    context: &context,
                    y: coords.y(for: referenceValue),
                    plotRect: coords.plotRect,
                    color: style.referenceLineColor
                )
            }

            if coords.volumeRect != nil, snapshot.maxVolume > 0 {
                drawVolumeBars(context: &context, coords: coords, style: style)
            }

            guard snapshot.displayPoints.count >= 2 || (snapshot.kind == .candles && !snapshot.displayPoints.isEmpty) else {
                return
            }

            switch snapshot.kind {
            case .line:
                let screenPoints = snapshot.displayPoints.map { coords.point(forX: $0.x, price: $0.close) }
                FinancialChartAreaRenderer.drawLineAndArea(
                    context: &context,
                    size: size,
                    screenPoints: screenPoints,
                    plotRect: coords.plotRect,
                    areaBaselineY: snapshot.areaBaselineY,
                    style: style,
                    fillsArea: false,
                    isDarkMode: isDarkMode
                )
            case .area:
                let screenPoints = snapshot.displayPoints.map { coords.point(forX: $0.x, price: $0.close) }
                FinancialChartAreaRenderer.drawLineAndArea(
                    context: &context,
                    size: size,
                    screenPoints: screenPoints,
                    plotRect: coords.plotRect,
                    areaBaselineY: snapshot.areaBaselineY,
                    style: style,
                    fillsArea: true,
                    isDarkMode: isDarkMode
                )
            case .candles:
                drawCandles(context: &context, coords: coords, style: style)
                if style.showsHighLowCallouts {
                    drawCandleExtremaLabels(context: &context, coords: coords)
                }
            }

            if !snapshot.placedTradeMarkers.isEmpty {
                FinancialChartTradeMarkerRenderer.draw(
                    context: &context,
                    markers: snapshot.placedTradeMarkers,
                    kind: snapshot.kind,
                    style: style,
                    isDarkMode: isDarkMode
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize,
        plotRect: CGRect,
        color: Color
    ) {
        var gridPath = Path()
        for index in 1..<4 {
            let y = plotRect.minY + plotRect.height * CGFloat(index) / 4.0
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

    private func drawReferenceLine(
        context: inout GraphicsContext,
        y: CGFloat,
        plotRect: CGRect,
        color: Color
    ) {
        guard y >= plotRect.minY && y <= plotRect.maxY else {
            return
        }

        var path = Path()
        path.move(to: CGPoint(x: plotRect.minX, y: y))
        path.addLine(to: CGPoint(x: plotRect.maxX, y: y))

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 4])
        )
    }

    private func drawCandles(
        context: inout GraphicsContext,
        coords: FinancialChartCoordinateSystem,
        style: FinancialChartStyle
    ) {
        let candleWidth = snapshot.candleWidth
        let wickWidth = snapshot.wickWidth
        let cornerRadius = min(candleWidth * 0.28, 1.8)

        var bullishWicks = Path()
        var bearishWicks = Path()
        var bullishBodies = Path()
        var bearishBodies = Path()

        for point in snapshot.displayPoints {
            let centerX = coords.x(for: point.x)
            let highY = coords.y(for: point.high)
            let lowY = coords.y(for: point.low)
            let bodyRect = coords.candleBodyRect(for: point, width: candleWidth, minBodyHeight: 1.5)
            let bodyPath = Path(roundedRect: bodyRect, cornerRadius: cornerRadius, style: .continuous)

            if point.isBullish {
                bullishWicks.move(to: CGPoint(x: centerX, y: highY))
                bullishWicks.addLine(to: CGPoint(x: centerX, y: lowY))
                bullishBodies.addPath(bodyPath)
            } else {
                bearishWicks.move(to: CGPoint(x: centerX, y: highY))
                bearishWicks.addLine(to: CGPoint(x: centerX, y: lowY))
                bearishBodies.addPath(bodyPath)
            }
        }

        let wickStyle = StrokeStyle(lineWidth: wickWidth, lineCap: .round)
        context.stroke(bullishWicks, with: .color(style.positiveColor), style: wickStyle)
        context.stroke(bearishWicks, with: .color(style.negativeColor), style: wickStyle)
        context.fill(bullishBodies, with: .color(style.positiveColor))
        context.fill(bearishBodies, with: .color(style.negativeColor))
    }

    private func drawCandleExtremaLabels(
        context: inout GraphicsContext,
        coords: FinancialChartCoordinateSystem
    ) {
        guard let highest = snapshot.displayPoints.max(by: { $0.high < $1.high }),
              let lowest = snapshot.displayPoints.min(by: { $0.low < $1.low }),
              highest.high > lowest.low else {
            return
        }

        let plotRect = coords.plotRect
        let labelFont = Font.system(size: 10, weight: .semibold).monospacedDigit()
        let labelColor = Color(.secondaryLabel)

        let highText = context.resolve(
            Text(Self.formatExtremaPrice(highest.high)).font(labelFont).foregroundStyle(labelColor)
        )
        let highSize = highText.measure(in: plotRect.size)
        var highX = min(
            max(coords.x(for: highest.x), plotRect.minX + highSize.width * 0.5 + 2),
            plotRect.maxX - highSize.width * 0.5 - 2
        )
        let highY = max(coords.y(for: highest.high) - highSize.height * 0.5 - 3, plotRect.minY - 8)
        highX = adjustedExtremaX(
            centerX: highX,
            centerY: highY,
            labelSize: highSize,
            plotRect: plotRect,
            side: .sell
        )
        context.draw(highText, at: CGPoint(x: highX, y: highY), anchor: .center)

        let lowText = context.resolve(
            Text(Self.formatExtremaPrice(lowest.low)).font(labelFont).foregroundStyle(labelColor)
        )
        let lowSize = lowText.measure(in: plotRect.size)
        var lowX = min(
            max(coords.x(for: lowest.x), plotRect.minX + lowSize.width * 0.5 + 2),
            plotRect.maxX - lowSize.width * 0.5 - 2
        )
        let lowY = min(coords.y(for: lowest.low) + lowSize.height * 0.5 + 3, plotRect.maxY + 6)
        lowX = adjustedExtremaX(
            centerX: lowX,
            centerY: lowY,
            labelSize: lowSize,
            plotRect: plotRect,
            side: .buy
        )
        context.draw(lowText, at: CGPoint(x: lowX, y: lowY), anchor: .center)
    }

    private func adjustedExtremaX(
        centerX: CGFloat,
        centerY: CGFloat,
        labelSize: CGSize,
        plotRect: CGRect,
        side: FinancialChartTradeSide
    ) -> CGFloat {
        guard !snapshot.placedTradeMarkers.isEmpty else {
            return centerX
        }
        let labelRect = CGRect(
            x: centerX - labelSize.width * 0.5 - 2,
            y: centerY - labelSize.height * 0.5 - 2,
            width: labelSize.width + 4,
            height: labelSize.height + 4
        )
        let badgeRadius = FinancialChartTradeMarkerLayout.badgeDiameter * 0.5 + 2
        guard let colliding = snapshot.placedTradeMarkers.first(where: { marker in
            guard marker.side == side else { return false }
            let badgeRect = CGRect(
                x: marker.badgeCenter.x - badgeRadius,
                y: marker.badgeCenter.y - badgeRadius,
                width: badgeRadius * 2,
                height: badgeRadius * 2
            )
            return labelRect.intersects(badgeRect)
        }) else {
            return centerX
        }

        let offset = labelSize.width * 0.5 + badgeRadius + 4
        let rightCandidate = colliding.badgeCenter.x + offset
        let leftCandidate = colliding.badgeCenter.x - offset
        let minX = plotRect.minX + labelSize.width * 0.5 + 2
        let maxX = plotRect.maxX - labelSize.width * 0.5 - 2

        if rightCandidate <= maxX {
            return rightCandidate
        }
        if leftCandidate >= minX {
            return leftCandidate
        }
        return centerX
    }

    /// Adaptive precision for candlestick High/Low callouts so sub-dollar options
    /// preserve meaningful differences instead of rounding both tags to identical 2-decimal prices.
    static func formatExtremaPrice(_ value: Double) -> String {
        let absValue = abs(value)
        let fractionLength: Int
        if absValue > 0 && absValue < 0.1 {
            fractionLength = 4
        } else if absValue > 0 && absValue < 1.0 {
            fractionLength = 3
        } else {
            fractionLength = 2
        }
        return AppFormatter.money(value, fractionLength: fractionLength)
    }

    private func drawVolumeBars(
        context: inout GraphicsContext,
        coords: FinancialChartCoordinateSystem,
        style: FinancialChartStyle
    ) {
        let barWidth = max(snapshot.candleWidth * 0.78, 1.5)
        let cornerRadius = min(barWidth * 0.25, 1.2)
        var bullishPath = Path()
        var bearishPath = Path()

        for point in snapshot.displayPoints {
            guard let rect = coords.volumeBarRect(
                for: point,
                maxVolume: snapshot.maxVolume,
                barWidth: barWidth
            ) else {
                continue
            }

            let barPath = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
            if point.isBullish {
                bullishPath.addPath(barPath)
            } else {
                bearishPath.addPath(barPath)
            }
        }

        context.fill(bullishPath, with: .color(style.positiveColor.opacity(style.volumeOpacity)))
        context.fill(bearishPath, with: .color(style.negativeColor.opacity(style.volumeOpacity)))
    }
}

/// Shared single-GPU-call line, glow, and dot-matrix/gradient area renderer used by
/// `FinancialChartBaseCanvas`, `FinancialChartMorphingLayer`, and `FinancialChartLoadingWaveView`.
@MainActor
enum FinancialChartAreaRenderer {
    static func drawLineAndArea(
        context: inout GraphicsContext,
        size: CGSize,
        screenPoints: [CGPoint],
        plotRect: CGRect,
        areaBaselineY: CGFloat,
        style: FinancialChartStyle,
        lineColorOverride: Color? = nil,
        fillsArea: Bool,
        isDarkMode: Bool
    ) {
        guard screenPoints.count >= 2 else {
            return
        }

        let lineColor = lineColorOverride ?? style.lineColor
        let linePath = FinancialChartPathBuilder.linePath(
            through: screenPoints,
            interpolation: style.interpolation
        )

        if fillsArea {
            let areaPath = FinancialChartPathBuilder.areaPath(
                linePath: linePath,
                points: screenPoints,
                baselineY: areaBaselineY
            )
            var minScreenY = screenPoints[0].y
            for point in screenPoints.dropFirst() where point.y < minScreenY {
                minScreenY = point.y
            }
            drawAreaFill(
                context: &context,
                size: size,
                areaPath: areaPath,
                minLineY: minScreenY,
                plotRect: plotRect,
                lineColor: lineColor,
                style: style,
                isDarkMode: isDarkMode
            )
        }

        let strokeStyle = StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round)

        if style.glowRadius > 0 && style.glowOpacity > 0 {
            let resolvedGlowOpacity = isDarkMode ? style.glowOpacity : style.glowOpacity * 0.45
            context.drawLayer { glowLayer in
                glowLayer.addFilter(
                    .shadow(
                        color: lineColor.opacity(resolvedGlowOpacity),
                        radius: style.glowRadius,
                        x: 0,
                        y: 0
                    )
                )
                glowLayer.stroke(
                    linePath,
                    with: .color(lineColor),
                    style: strokeStyle
                )
            }
        }

        context.stroke(
            linePath,
            with: .color(lineColor),
            style: strokeStyle
        )

        if let highlightColor = style.lineHighlightColor, style.lineHighlightWidth > 0 {
            context.stroke(
                linePath,
                with: .color(highlightColor),
                style: StrokeStyle(lineWidth: style.lineHighlightWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private static func drawAreaFill(
        context: inout GraphicsContext,
        size: CGSize,
        areaPath: Path,
        minLineY: CGFloat,
        plotRect: CGRect,
        lineColor: Color,
        style: FinancialChartStyle,
        isDarkMode: Bool
    ) {
        switch style.areaFillStyle {
        case .none:
            break
        case .gradient:
            context.fill(
                areaPath,
                with: .linearGradient(
                    Gradient(colors: [
                        lineColor.opacity(style.areaTopOpacity),
                        lineColor.opacity(style.areaBottomOpacity)
                    ]),
                    startPoint: CGPoint(x: plotRect.midX, y: plotRect.minY),
                    endPoint: CGPoint(x: plotRect.midX, y: plotRect.maxY)
                )
            )
        case .dotMatrix(let spacing, let dotDiameter):
            let fullRect = CGRect(origin: .zero, size: size)
            let fadeStartY = min(minLineY, plotRect.maxY - 1)
            let fadeEndY = max(plotRect.maxY, fadeStartY + 1)

            // 1) Whisper-soft ambient curve wash so the dot matrix stays crisp and uncluttered
            let ambientTopOpacity = isDarkMode ? style.areaTopOpacity * 0.28 : style.areaTopOpacity * 0.20
            if ambientTopOpacity > 0.005 {
                context.fill(
                    areaPath,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: lineColor.opacity(ambientTopOpacity), location: 0.0),
                            .init(color: lineColor.opacity(0.0), location: 0.36)
                        ]),
                        startPoint: CGPoint(x: plotRect.midX, y: fadeStartY),
                        endPoint: CGPoint(x: plotRect.midX, y: fadeEndY)
                    )
                )
            }

            // 2) Single-GPU-call crisp tiled dot matrix masked by areaPath with smooth bottom feather
            let tileImage = FinancialChartDotMatrixTileCache.tileImage(
                spacing: spacing,
                dotDiameter: dotDiameter
            )
            let topDotOpacity = isDarkMode ? 0.90 : 0.62
            let midDotOpacity = isDarkMode ? 0.60 : 0.36
            let lowerDotOpacity = isDarkMode ? 0.22 : 0.12
            let bottomDotOpacity = isDarkMode ? 0.02 : 0.01

            context.drawLayer { layer in
                layer.clip(to: areaPath)
                layer.fill(
                    Path(fullRect),
                    with: .tiledImage(
                        tileImage,
                        origin: CGPoint(x: plotRect.minX, y: plotRect.minY)
                    )
                )
                layer.blendMode = .sourceIn
                layer.fill(
                    Path(fullRect),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: lineColor.opacity(topDotOpacity), location: 0.0),
                            .init(color: lineColor.opacity(midDotOpacity), location: 0.68),
                            .init(color: lineColor.opacity(lowerDotOpacity), location: 0.92),
                            .init(color: lineColor.opacity(bottomDotOpacity), location: 1.0)
                        ]),
                        startPoint: CGPoint(x: plotRect.midX, y: fadeStartY),
                        endPoint: CGPoint(x: plotRect.midX, y: fadeEndY)
                    )
                )
            }
        }
    }
}

/// Renders and caches tiny @3x dot tiles so `.dotMatrix` area fills execute in 1 GPU draw call.
@MainActor
private enum FinancialChartDotMatrixTileCache {
    private struct Key: Hashable {
        let spacingTenths: Int
        let diameterTenths: Int
    }

    private static var cache: [Key: Image] = [:]

    static func tileImage(spacing: CGFloat, dotDiameter: CGFloat) -> Image {
        let clampedSpacing = max(spacing, 3.0)
        let clampedDiameter = min(max(dotDiameter, 1.0), clampedSpacing - 1.0)
        let key = Key(
            spacingTenths: Int((clampedSpacing * 10).rounded()),
            diameterTenths: Int((clampedDiameter * 10).rounded())
        )
        if let cached = cache[key] {
            return cached
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: clampedSpacing, height: clampedSpacing),
            format: format
        )
        let uiImage = renderer.image { ctx in
            let offset = (clampedSpacing - clampedDiameter) * 0.5
            let dotRect = CGRect(x: offset, y: offset, width: clampedDiameter, height: clampedDiameter)
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: dotRect)
        }
        let image = Image(uiImage: uiImage)
        cache[key] = image
        return image
    }
}
