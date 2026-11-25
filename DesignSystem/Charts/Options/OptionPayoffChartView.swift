import SwiftUI
import UIKit

/// High-performance, US-equity-standard Options Expiration P&L (Payoff) Diagram.
/// Uses exact O(1) piecewise-linear geometry rendered on SwiftUI `Canvas` with an
/// isolated crosshair layer so scrubbing runs smoothly at 120fps without recomputing the curve.
struct OptionPayoffChartCard: View {
    let spec: OptionPayoffSpec
    let underlyingSymbol: String

    @Environment(\.locale) private var locale
    @State private var scrubSample: OptionPayoffScrubSample?

    var body: some View {
        let metrics = OptionPayoffEngine.computeMetrics(for: spec)

        VStack(alignment: .leading, spacing: 14) {
            headerSection(metrics: metrics)

            OptionPayoffCanvasPlot(
                spec: spec,
                metrics: metrics,
                scrubSample: $scrubSample
            )
            .frame(height: 176)

            metricsFooter(metrics: metrics)
        }
        .padding(16)
        .background(
            AppTheme.ColorToken.groupedSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.14), lineWidth: 0.75)
        }
    }

    private func headerSection(metrics: OptionPayoffMetrics) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L10n.Trade.optionPayoffTitle(locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if spec.isSimulatedPreview {
                        Text(L10n.Trade.optionPayoffPreviewBadge(locale: locale))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }

                if let sample = scrubSample {
                    Text(L10n.Trade.optionPayoffAtExpiryPrice(
                        symbol: underlyingSymbol,
                        price: OptionPayoffFormat.price(sample.underlyingPrice, currencyCode: spec.currencyCode),
                        locale: locale
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else {
                    Text(L10n.Trade.optionPayoffScrubHint(locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let sample = scrubSample {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(OptionPayoffFormat.signedMoney(sample.expirationPnL, currencyCode: spec.currencyCode))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(pnlTint(for: sample.expirationPnL))
                        .lineLimit(1)

                    if let ret = sample.returnFraction, ret.isFinite {
                        Text(AppFormatter.signedPercent(ret, fractionLength: 1))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(pnlTint(for: sample.expirationPnL))
                            .lineLimit(1)
                    }
                }
            } else if let spotPnL = metrics.spotPnL {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(OptionPayoffFormat.signedMoney(spotPnL, currencyCode: spec.currencyCode))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(pnlTint(for: spotPnL))
                        .lineLimit(1)

                    Text(L10n.Trade.optionPayoffAtCurrentSpot(locale: locale))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(minHeight: 36, alignment: .top)
    }

    private func metricsFooter(metrics: OptionPayoffMetrics) -> some View {
        HStack(spacing: 0) {
            OptionPayoffMetricColumn(
                title: L10n.Trade.optionPayoffMaxProfit(locale: locale),
                value: OptionPayoffFormat.bound(metrics.maxProfit, currencyCode: spec.currencyCode, locale: locale),
                tint: AppTheme.ColorToken.positive,
                alignment: .leading
            )

            OptionPayoffMetricColumn(
                title: L10n.Trade.optionPayoffBreakeven(locale: locale),
                value: metrics.breakeven.map {
                    OptionPayoffFormat.price($0, currencyCode: spec.currencyCode)
                } ?? AppFormatter.placeholder,
                tint: .primary,
                alignment: .center
            )

            OptionPayoffMetricColumn(
                title: L10n.Trade.optionPayoffMaxLoss(locale: locale),
                value: OptionPayoffFormat.bound(metrics.maxLoss, currencyCode: spec.currencyCode, locale: locale),
                tint: AppTheme.ColorToken.negative,
                alignment: .trailing
            )
        }
        .padding(.top, 2)
    }

    private func pnlTint(for value: Double) -> Color {
        if abs(value) < 0.005 {
            return .secondary
        }
        return value > 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }
}

private struct OptionPayoffMetricColumn: View {
    let title: String
    let value: String
    let tint: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

// MARK: - High-Performance Canvas & Isolated Scrub Layer

private struct OptionPayoffCanvasPlot: View {
    let spec: OptionPayoffSpec
    let metrics: OptionPayoffMetrics
    @Binding var scrubSample: OptionPayoffScrubSample?

    @State private var lastSnappedAnchor: OptionPayoffAnchor?

    private let plotInsets = EdgeInsets(top: 14, leading: 6, bottom: 26, trailing: 6)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plotRect = CGRect(
                x: plotInsets.leading,
                y: plotInsets.top,
                width: max(1, size.width - plotInsets.leading - plotInsets.trailing),
                height: max(1, size.height - plotInsets.top - plotInsets.bottom)
            )

            ZStack {
                OptionPayoffBaseCanvas(
                    spec: spec,
                    metrics: metrics,
                    plotRect: plotRect
                )

                if let sample = scrubSample {
                    OptionPayoffCrosshairLayer(
                        metrics: metrics,
                        sample: sample,
                        plotRect: plotRect
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let normX = (value.location.x - plotRect.minX) / plotRect.width
                        let sample = OptionPayoffEngine.scrubSample(
                            spec: spec,
                            metrics: metrics,
                            normalizedX: normX
                        )
                        if sample.snappedAnchor != nil, sample.snappedAnchor != lastSnappedAnchor {
                            OptionPayoffHaptics.snap()
                        }
                        lastSnappedAnchor = sample.snappedAnchor
                        if scrubSample != sample {
                            scrubSample = sample
                        }
                    }
                    .onEnded { _ in
                        lastSnappedAnchor = nil
                        scrubSample = nil
                    }
            )
        }
    }
}

/// Static base curve layer — only redraws when `spec`, `metrics`, or `plotRect` changes
/// (NEVER redraws during interactive crosshair scrubbing).
private struct OptionPayoffBaseCanvas: View, Equatable {
    let spec: OptionPayoffSpec
    let metrics: OptionPayoffMetrics
    let plotRect: CGRect

    nonisolated static func == (lhs: OptionPayoffBaseCanvas, rhs: OptionPayoffBaseCanvas) -> Bool {
        lhs.spec == rhs.spec && lhs.metrics == rhs.metrics && lhs.plotRect == rhs.plotRect
    }

    var body: some View {
        Canvas { context, size in
            let vertices = OptionPayoffEngine.exactVertices(spec: spec, metrics: metrics)
            guard vertices.count >= 2 else { return }

            let points = vertices.map { vertex in
                CGPoint(
                    x: xPosition(for: vertex.price),
                    y: yPosition(for: vertex.pnl)
                )
            }
            let zeroY = yPosition(for: 0)

            // 1. Subtle horizontal $0 breakeven reference line
            var zeroLine = Path()
            zeroLine.move(to: CGPoint(x: plotRect.minX, y: zeroY))
            zeroLine.addLine(to: CGPoint(x: plotRect.maxX, y: zeroY))
            context.stroke(
                zeroLine,
                with: .color(Color(.separator).opacity(0.42)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )

            // 2. Profit (green) & Loss (red) clipped area fills and segmented strokes
            drawPayoffSegments(in: &context, vertices: vertices, points: points, zeroY: zeroY)

            // 3. Strike vertical hairline
            if spec.strike > metrics.priceMin && spec.strike < metrics.priceMax {
                let strikeX = xPosition(for: spec.strike)
                var strikeLine = Path()
                strikeLine.move(to: CGPoint(x: strikeX, y: plotRect.minY))
                strikeLine.addLine(to: CGPoint(x: strikeX, y: plotRect.maxY))
                context.stroke(
                    strikeLine,
                    with: .color(Color(.separator).opacity(0.26)),
                    style: StrokeStyle(lineWidth: 0.8, dash: [2, 3])
                )
            }

            // 4. Current underlying spot marker (if available and in range)
            if let spot = spec.underlyingPrice, spot >= metrics.priceMin, spot <= metrics.priceMax {
                let spotX = xPosition(for: spot)
                let spotY = yPosition(for: OptionPayoffEngine.expirationPnL(spec: spec, at: spot))
                var spotLine = Path()
                spotLine.move(to: CGPoint(x: spotX, y: plotRect.minY))
                spotLine.addLine(to: CGPoint(x: spotX, y: plotRect.maxY))
                context.stroke(
                    spotLine,
                    with: .color(Color.primary.opacity(0.28)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )

                let dotRect = CGRect(x: spotX - 4, y: spotY - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dotRect), with: .color(.primary))
                context.stroke(Path(ellipseIn: dotRect.insetBy(dx: -1.5, dy: -1.5)), with: .color(AppTheme.ColorToken.groupedSurface), lineWidth: 2)
            }

            // 5. Breakeven marker dot on $0 line
            if let be = metrics.breakeven, be >= metrics.priceMin, be <= metrics.priceMax {
                let beX = xPosition(for: be)
                let outer = CGRect(x: beX - 5, y: zeroY - 5, width: 10, height: 10)
                let inner = CGRect(x: beX - 2.8, y: zeroY - 2.8, width: 5.6, height: 5.6)
                context.fill(Path(ellipseIn: outer), with: .color(AppTheme.ColorToken.groupedSurface))
                context.stroke(Path(ellipseIn: outer), with: .color(Color.primary.opacity(0.65)), lineWidth: 1.5)
                context.fill(Path(ellipseIn: inner), with: .color(.primary))
            }

            // 6. Crisp X-axis price ticks (Min / Strike or BE / Max)
            drawAxisLabels(in: &context, size: size)
        }
    }

    private func drawPayoffSegments(
        in context: inout GraphicsContext,
        vertices: [(price: Double, pnl: Double)],
        points: [CGPoint],
        zeroY: CGFloat
    ) {
        let profitColor = AppTheme.ColorToken.positive
        let lossColor = AppTheme.ColorToken.negative

        for index in 0..<(points.count - 1) {
            let p0 = points[index]
            let p1 = points[index + 1]
            let v0 = vertices[index].pnl
            let v1 = vertices[index + 1].pnl
            let isProfit = (v0 + v1) >= 0
            let color = isProfit ? profitColor : lossColor

            var fillPath = Path()
            fillPath.move(to: CGPoint(x: p0.x, y: zeroY))
            fillPath.addLine(to: p0)
            fillPath.addLine(to: p1)
            fillPath.addLine(to: CGPoint(x: p1.x, y: zeroY))
            fillPath.closeSubpath()

            let gradientStart = isProfit
                ? CGPoint(x: 0, y: plotRect.minY)
                : CGPoint(x: 0, y: zeroY)
            let gradientEnd = isProfit
                ? CGPoint(x: 0, y: zeroY)
                : CGPoint(x: 0, y: plotRect.maxY)
            let gradient = Gradient(colors: isProfit
                ? [color.opacity(0.24), color.opacity(0.03)]
                : [color.opacity(0.03), color.opacity(0.24)]
            )
            context.fill(
                fillPath,
                with: .linearGradient(gradient, startPoint: gradientStart, endPoint: gradientEnd)
            )

            var linePath = Path()
            linePath.move(to: p0)
            linePath.addLine(to: p1)
            context.stroke(
                linePath,
                with: .color(color),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawAxisLabels(in context: inout GraphicsContext, size: CGSize) {
        let labelY = size.height - 8
        let font = Font.caption2.monospacedDigit()
        let color = Color.secondary

        let minText = context.resolve(
            Text(OptionPayoffFormat.compactPrice(metrics.priceMin))
                .font(font)
                .foregroundStyle(color)
        )
        context.draw(minText, at: CGPoint(x: plotRect.minX, y: labelY), anchor: .leading)

        let maxText = context.resolve(
            Text(OptionPayoffFormat.compactPrice(metrics.priceMax))
                .font(font)
                .foregroundStyle(color)
        )
        context.draw(maxText, at: CGPoint(x: plotRect.maxX, y: labelY), anchor: .trailing)

        let centerAnchorPrice = metrics.breakeven ?? spec.strike
        if centerAnchorPrice > metrics.priceMin && centerAnchorPrice < metrics.priceMax {
            let centerX = xPosition(for: centerAnchorPrice)
            let minSafeX = plotRect.minX + 56
            let maxSafeX = plotRect.maxX - 56
            if centerX >= minSafeX && centerX <= maxSafeX {
                let prefix = metrics.breakeven != nil ? "BE " : "K "
                let centerText = context.resolve(
                    Text("\(prefix)\(OptionPayoffFormat.compactPrice(centerAnchorPrice))")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.75))
                )
                context.draw(centerText, at: CGPoint(x: centerX, y: labelY), anchor: .center)
            }
        }
    }

    private func xPosition(for price: Double) -> CGFloat {
        let span = max(metrics.priceMax - metrics.priceMin, 0.01)
        let norm = (price - metrics.priceMin) / span
        return plotRect.minX + CGFloat(min(max(norm, 0), 1)) * plotRect.width
    }

    private func yPosition(for pnl: Double) -> CGFloat {
        let span = max(metrics.pnlMax - metrics.pnlMin, 0.01)
        let norm = (pnl - metrics.pnlMin) / span
        return plotRect.maxY - CGFloat(min(max(norm, 0), 1)) * plotRect.height
    }
}

/// Lightweight overlay redrawn only while scrubbing.
private struct OptionPayoffCrosshairLayer: View {
    let metrics: OptionPayoffMetrics
    let sample: OptionPayoffScrubSample
    let plotRect: CGRect

    var body: some View {
        Canvas { context, _ in
            let x = plotRect.minX + sample.normalizedX * plotRect.width
            let span = max(metrics.pnlMax - metrics.pnlMin, 0.01)
            let normY = (sample.expirationPnL - metrics.pnlMin) / span
            let y = plotRect.maxY - CGFloat(min(max(normY, 0), 1)) * plotRect.height

            let accent: Color = abs(sample.expirationPnL) < 0.005
                ? .primary
                : (sample.expirationPnL > 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative)

            var guide = Path()
            guide.move(to: CGPoint(x: x, y: plotRect.minY))
            guide.addLine(to: CGPoint(x: x, y: plotRect.maxY))
            context.stroke(
                guide,
                with: .color(accent.opacity(0.45)),
                style: StrokeStyle(lineWidth: 1.1)
            )

            let halo = CGRect(x: x - 9, y: y - 9, width: 18, height: 18)
            context.fill(Path(ellipseIn: halo), with: .color(accent.opacity(0.18)))

            let dot = CGRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9)
            context.fill(Path(ellipseIn: dot), with: .color(accent))
            context.stroke(Path(ellipseIn: dot), with: .color(AppTheme.ColorToken.groupedSurface), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

@MainActor
private enum OptionPayoffHaptics {
    private static let generator: UISelectionFeedbackGenerator = {
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        return gen
    }()

    static func snap() {
        generator.selectionChanged()
    }
}

private enum OptionPayoffFormat {
    static func price(_ value: Double, currencyCode: String) -> String {
        let fractionLength = abs(value) > 0 && abs(value) < 1 ? 4 : 2
        return AppFormatter.money(value, currencyCode: currencyCode, fractionLength: fractionLength)
    }

    static func compactPrice(_ value: Double) -> String {
        if value >= 1000 {
            return AppFormatter.money(value, fractionLength: 0)
        }
        return AppFormatter.money(value, fractionLength: value < 1 ? 3 : 2)
    }

    static func signedMoney(_ value: Double, currencyCode: String) -> String {
        if abs(value) < 0.005 {
            return AppFormatter.money(0.0, currencyCode: currencyCode)
        }
        return AppFormatter.signedCompactMoney(value, currencyCode: currencyCode, threshold: 100_000)
    }

    static func bound(_ bound: OptionPayoffBound, currencyCode: String, locale: Locale) -> String {
        switch bound {
        case .unlimited:
            return L10n.Trade.optionPayoffUnlimited(locale: locale)
        case .finite(let value):
            if value > 0 {
                return "+\(AppFormatter.compactMoney(value, currencyCode: currencyCode, threshold: 100_000))"
            }
            return AppFormatter.compactMoney(value, currencyCode: currencyCode, threshold: 100_000)
        }
    }
}
