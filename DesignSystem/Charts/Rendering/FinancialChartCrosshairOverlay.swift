import SwiftUI

/// High-frequency interactive overlay layer rendered independently above `FinancialChartBaseCanvas`.
/// Handles OKX-style dashed crosshair, ringed white-core anchor dot, clamped timestamp label,
/// and live endpoint pulse.
struct FinancialChartCrosshairOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: FinancialChartKind
    let latestPoint: FinancialChartPoint?
    let selection: FinancialChartSelection?
    let selectionLabel: String?
    let coordinateSystem: FinancialChartCoordinateSystem
    let style: FinancialChartStyle
    let showsEndpointPulse: Bool

    private static let labelHorizontalInset: CGFloat = 68

    var body: some View {
        let plotRect = coordinateSystem.plotRect
        let totalBottomY = coordinateSystem.volumeRect?.maxY ?? plotRect.maxY
        let isDarkMode = colorScheme == .dark

        ZStack(alignment: .topLeading) {
            if let selection {
                let pointPosition = coordinateSystem.point(
                    forX: selection.point.x,
                    price: selection.point.close
                )

                Canvas { context, _ in
                    var verticalRule = Path()
                    verticalRule.move(to: CGPoint(x: pointPosition.x, y: plotRect.minY))
                    verticalRule.addLine(to: CGPoint(x: pointPosition.x, y: totalBottomY))
                    context.stroke(
                        verticalRule,
                        with: .color(style.crosshairColor),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3])
                    )

                    if kind == .candles {
                        var horizontalRule = Path()
                        horizontalRule.move(to: CGPoint(x: plotRect.minX, y: pointPosition.y))
                        horizontalRule.addLine(to: CGPoint(x: plotRect.maxX, y: pointPosition.y))
                        context.stroke(
                            horizontalRule,
                            with: .color(style.crosshairColor.opacity(0.65)),
                            style: StrokeStyle(lineWidth: 0.85, lineCap: .round, dash: [3, 3])
                        )
                    }

                    let dotColor = kind == .candles
                        ? (selection.point.isBullish ? style.positiveColor : style.negativeColor)
                        : style.lineColor
                    let haloRect = CGRect(
                        x: pointPosition.x - 8,
                        y: pointPosition.y - 8,
                        width: 16,
                        height: 16
                    )
                    let ringRect = CGRect(
                        x: pointPosition.x - 4.5,
                        y: pointPosition.y - 4.5,
                        width: 9,
                        height: 9
                    )
                    let coreRect = CGRect(
                        x: pointPosition.x - 2.3,
                        y: pointPosition.y - 2.3,
                        width: 4.6,
                        height: 4.6
                    )

                    context.fill(Path(ellipseIn: haloRect), with: .color(dotColor.opacity(isDarkMode ? 0.30 : 0.22)))
                    context.fill(Path(ellipseIn: ringRect), with: .color(dotColor))
                    context.fill(
                        Path(ellipseIn: coreRect),
                        with: .color(isDarkMode ? Color.white : Color(.systemBackground))
                    )
                }

                if let selectionLabel, !selectionLabel.isEmpty {
                    let clampedX = clampedLabelX(pointPosition.x, canvasWidth: coordinateSystem.canvasSize.width)
                    let labelY = max(coordinateSystem.insets.top * 0.44, 10)

                    Text(selectionLabel)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: clampedX, y: labelY)
                }
            } else if showsEndpointPulse,
                      style.showsEndpointPulse,
                      kind != .candles,
                      let latestPoint {
                let latestPosition = coordinateSystem.point(forX: latestPoint.x, price: latestPoint.close)
                if latestPosition.x >= plotRect.minX - 2 && latestPosition.x <= plotRect.maxX + 2 {
                    FinancialChartEndpointPulse(tint: style.lineColor)
                        .position(latestPosition)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func clampedLabelX(_ x: CGFloat, canvasWidth: CGFloat) -> CGFloat {
        let inset = Self.labelHorizontalInset
        guard canvasWidth > inset * 2 else {
            return canvasWidth * 0.5
        }
        return min(max(x, inset), canvasWidth - inset)
    }
}

/// Evenly distributed X-axis timestamp strip shown smoothly in place of the range picker while scrubbing.
struct FinancialChartTimeAxisStrip: View {
    let labels: [String]
    let height: CGFloat

    init(labels: [String], height: CGFloat = 32) {
        self.labels = labels
        self.height = height
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FinancialChartEndpointPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tint: Color
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(tint.opacity(isAnimating ? 0 : 0.28))
                    .frame(width: 18, height: 18)
                    .scaleEffect(isAnimating ? 1.55 : 0.85)
            }

            Circle()
                .fill(tint.opacity(0.24))
                .frame(width: 15, height: 15)

            Circle()
                .fill(tint)
                .frame(width: 6.5, height: 6.5)
        }
        .frame(width: 28, height: 28)
        .onAppear {
            startPulseIfAllowed()
        }
        .onChange(of: reduceMotion) { _, _ in
            startPulseIfAllowed()
        }
        .onDisappear {
            resetPulseWithoutAnimation()
        }
    }

    private func startPulseIfAllowed() {
        guard !reduceMotion else {
            resetPulseWithoutAnimation()
            return
        }
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            isAnimating = true
        }
    }

    private func resetPulseWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isAnimating = false
        }
    }
}
