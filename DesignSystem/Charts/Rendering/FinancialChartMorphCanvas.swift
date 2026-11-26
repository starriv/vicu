import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Normalized (u, v) vertex inside a chart's plot rectangle (`u, v in [0, 1]`).
struct FinancialChartMorphSample: Equatable, Sendable {
    let u: CGFloat
    let v: CGFloat
}

/// Fixed-topology resampled curve enabling silky 120fps geometric morphing between
/// any two chart periods (even across differing point counts and 1D partial-width sessions).
struct FinancialChartMorphCurve: Equatable, Sendable {
    static let defaultSampleCount = 128

    let samples: [FinancialChartMorphSample]

    /// Projects `points` directly into normalized `(u, v)` vertices without resampling or clipping peaks.
    static func exact(
        from points: [FinancialChartPoint],
        coordinateSystem: FinancialChartCoordinateSystem
    ) -> FinancialChartMorphCurve {
        let plotRect = coordinateSystem.plotRect
        guard points.count >= 2, plotRect.width > 0, plotRect.height > 0 else {
            return flat(yFraction: 0.5, sampleCount: 2)
        }

        let projected = points.map { point in
            let sx = coordinateSystem.x(for: point.x)
            let sy = coordinateSystem.y(for: point.close)
            return FinancialChartMorphSample(
                u: (sx - plotRect.minX) / plotRect.width,
                v: (sy - plotRect.minY) / plotRect.height
            )
        }
        return FinancialChartMorphCurve(samples: projected)
    }

    /// Resamples this curve at the relative horizontal `u` profile of `target` so every vertex
    /// maps 1:1 onto `target` with zero horizontal clumping and zero end-of-morph pixel pop.
    func resampled(toMatch target: FinancialChartMorphCurve) -> FinancialChartMorphCurve {
        let targetCount = target.samples.count
        guard samples.count >= 2, targetCount >= 2 else {
            return self
        }

        let targetFirstU = target.samples[0].u
        let targetUSpan = target.samples[targetCount - 1].u - targetFirstU
        let relativePositions: [CGFloat] = (0..<targetCount).map { index in
            if targetUSpan > 1e-6 {
                return min(max((target.samples[index].u - targetFirstU) / targetUSpan, 0), 1)
            }
            return CGFloat(index) / CGFloat(targetCount - 1)
        }
        return resampled(atRelativeU: relativePositions)
    }

    func resampled(toCount targetCount: Int) -> FinancialChartMorphCurve {
        guard samples.count >= 2, targetCount >= 2 else {
            return self
        }
        let relativePositions = (0..<targetCount).map { index in
            CGFloat(index) / CGFloat(targetCount - 1)
        }
        return resampled(atRelativeU: relativePositions)
    }

    private func resampled(atRelativeU relativePositions: [CGFloat]) -> FinancialChartMorphCurve {
        let targetCount = relativePositions.count
        guard samples.count >= 2, targetCount >= 2 else {
            return self
        }

        let firstU = samples[0].u
        let lastU = samples[samples.count - 1].u
        let uSpan = lastU - firstU
        var output: [FinancialChartMorphSample] = []
        output.reserveCapacity(targetCount)

        if uSpan > 1e-6 {
            var segmentIndex = 0
            let maxSegmentStart = samples.count - 2

            for relU in relativePositions {
                let targetU = firstU + uSpan * relU

                while segmentIndex < maxSegmentStart && samples[segmentIndex + 1].u < targetU {
                    segmentIndex += 1
                }

                let p0 = samples[segmentIndex]
                let p1 = samples[segmentIndex + 1]
                let segU = p1.u - p0.u
                let v: CGFloat
                if segU > 1e-6 {
                    let localT = min(max((targetU - p0.u) / segU, 0), 1)
                    v = p0.v + (p1.v - p0.v) * localT
                } else {
                    v = p1.v
                }

                output.append(FinancialChartMorphSample(u: targetU, v: v))
            }
        } else {
            let lastSourceIndex = samples.count - 1
            for index in 0..<targetCount {
                let t = Double(index) / Double(targetCount - 1)
                let scaled = t * Double(lastSourceIndex)
                let lowIndex = min(Int(floor(scaled)), lastSourceIndex)
                let highIndex = min(lowIndex + 1, lastSourceIndex)
                let fraction = CGFloat(scaled - Double(lowIndex))

                let p0 = samples[lowIndex]
                let p1 = samples[highIndex]
                output.append(
                    FinancialChartMorphSample(
                        u: p0.u + (p1.u - p0.u) * fraction,
                        v: p0.v + (p1.v - p0.v) * fraction
                    )
                )
            }
        }

        return FinancialChartMorphCurve(samples: output)
    }

    /// Builds an aligned `(from, to)` morph pair where `to` is bit-for-bit identical to
    /// `targetPoints` projected through `coordinateSystem`, guaranteeing zero pixel shift at `t = 1.0`.
    static func alignedPair(
        from sourceCurve: FinancialChartMorphCurve,
        to targetPoints: [FinancialChartPoint],
        coordinateSystem: FinancialChartCoordinateSystem
    ) -> (from: FinancialChartMorphCurve, to: FinancialChartMorphCurve) {
        let exactTarget = exact(from: targetPoints, coordinateSystem: coordinateSystem)
        let alignedSource = sourceCurve.resampled(toMatch: exactTarget)
        return (from: alignedSource, to: exactTarget)
    }

    /// Resamples `points` projected through `coordinateSystem` into `sampleCount` vertices
    /// distributed uniformly across horizontal screen coordinate `u` (`firstU ... lastU`) so
    /// sparse carry-forward gaps never clump vertices or cause end-of-morph jumps.
    static func sample(
        from points: [FinancialChartPoint],
        coordinateSystem: FinancialChartCoordinateSystem,
        sampleCount: Int = defaultSampleCount
    ) -> FinancialChartMorphCurve {
        exact(from: points, coordinateSystem: coordinateSystem)
            .resampled(toCount: max(sampleCount, 2))
    }

    /// Generates a calm, organic flowing ambient wave for cold-start loading in the same dot-matrix style.
    static func loadingWave(
        phase: Double,
        sampleCount: Int = defaultSampleCount
    ) -> FinancialChartMorphCurve {
        let count = max(sampleCount, 2)
        var samples: [FinancialChartMorphSample] = []
        samples.reserveCapacity(count)

        for index in 0..<count {
            let u = Double(index) / Double(count - 1)
            let primary = sin(u * .pi * 2.4 - phase) * 0.13
            let secondary = sin(u * .pi * 5.2 + phase * 0.65) * 0.055
            let tertiary = cos(u * .pi * 1.15 - phase * 0.35) * 0.045
            let v = min(max(0.50 + primary + secondary + tertiary, 0.16), 0.84)
            samples.append(FinancialChartMorphSample(u: CGFloat(u), v: CGFloat(v)))
        }

        return FinancialChartMorphCurve(samples: samples)
    }

    static func flat(
        yFraction: CGFloat = 0.5,
        sampleCount: Int = defaultSampleCount
    ) -> FinancialChartMorphCurve {
        let count = max(sampleCount, 2)
        let samples = (0..<count).map { index in
            FinancialChartMorphSample(
                u: CGFloat(index) / CGFloat(count - 1),
                v: yFraction
            )
        }
        return FinancialChartMorphCurve(samples: samples)
    }

    static func interpolate(
        from lhs: FinancialChartMorphCurve,
        to rhs: FinancialChartMorphCurve,
        progress: CGFloat
    ) -> FinancialChartMorphCurve {
        let t = min(max(progress, 0), 1)
        let count = min(lhs.samples.count, rhs.samples.count)
        guard count >= 2 else {
            return rhs
        }

        var blended: [FinancialChartMorphSample] = []
        blended.reserveCapacity(count)

        for index in 0..<count {
            let a = lhs.samples[index]
            let b = rhs.samples[index]
            blended.append(
                FinancialChartMorphSample(
                    u: a.u + (b.u - a.u) * t,
                    v: a.v + (b.v - a.v) * t
                )
            )
        }

        return FinancialChartMorphCurve(samples: blended)
    }

    /// Directly interpolates `lhs -> rhs` and projects into `plotRect` in a single pass,
    /// avoiding intermediate `[FinancialChartMorphSample]` allocations on every 120Hz animation frame.
    static func interpolatedScreenPoints(
        from lhs: FinancialChartMorphCurve,
        to rhs: FinancialChartMorphCurve,
        progress: CGFloat,
        in plotRect: CGRect
    ) -> [CGPoint] {
        let t = min(max(progress, 0), 1)
        let count = min(lhs.samples.count, rhs.samples.count)
        guard count >= 2 else {
            return rhs.screenPoints(in: plotRect)
        }

        var result: [CGPoint] = []
        result.reserveCapacity(count)

        let originX = plotRect.minX
        let originY = plotRect.minY
        let width = plotRect.width
        let height = plotRect.height

        for index in 0..<count {
            let a = lhs.samples[index]
            let b = rhs.samples[index]
            let u = a.u + (b.u - a.u) * t
            let v = a.v + (b.v - a.v) * t
            result.append(CGPoint(x: originX + u * width, y: originY + v * height))
        }

        return result
    }

    func screenPoints(in plotRect: CGRect) -> [CGPoint] {
        samples.map { sample in
            CGPoint(
                x: plotRect.minX + sample.u * plotRect.width,
                y: plotRect.minY + sample.v * plotRect.height
            )
        }
    }

    /// Evaluates the ease-out curve used by morph animations so interrupting a running morph
    /// starts smoothly from the exact current visual curve.
    static func approximateEaseOutProgress(elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 1 }
        let x = min(max(elapsed / duration, 0), 1)
        let inv = 1.0 - x
        return CGFloat(1.0 - inv * inv * inv)
    }
}

/// Pre-resolved sRGBA color components so 120Hz morph frames blend with zero `UITraitCollection` / `UIColor` allocations.
struct FinancialChartRGBAColor: Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    @MainActor
    static func resolve(_ color: Color, isDarkMode: Bool) -> FinancialChartRGBAColor? {
        let traits = UITraitCollection(userInterfaceStyle: isDarkMode ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return nil
        }
        return FinancialChartRGBAColor(red: r, green: g, blue: b, alpha: a)
    }

    func interpolated(to other: FinancialChartRGBAColor, progress: CGFloat) -> Color {
        let t = min(max(progress, 0), 1)
        return Color(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            opacity: alpha + (other.alpha - alpha) * t
        )
    }
}

/// Smooth RGBA color blender for transitioning between red/green/brand curves during morphing.
@MainActor
enum FinancialChartColorBlender {
    static func blend(
        from startColor: Color,
        to endColor: Color,
        fromRGBA: FinancialChartRGBAColor? = nil,
        toRGBA: FinancialChartRGBAColor? = nil,
        progress: CGFloat,
        isDarkMode: Bool
    ) -> Color {
        let t = min(max(progress, 0), 1)
        if t <= 0.001 { return startColor }
        if t >= 0.999 { return endColor }

        if let c1 = fromRGBA ?? FinancialChartRGBAColor.resolve(startColor, isDarkMode: isDarkMode),
           let c2 = toRGBA ?? FinancialChartRGBAColor.resolve(endColor, isDarkMode: isDarkMode) {
            return c1.interpolated(to: c2, progress: t)
        }
        return t < 0.5 ? startColor : endColor
    }
}

/// Animatable Canvas that fluidly morphs from `fromCurve` to `toCurve` across `progress` (0 -> 1)
/// using the exact same dot-matrix + glow renderer as the settled `FinancialChartBaseCanvas`.
struct FinancialChartMorphingCanvas: View, Animatable {
    let fromCurve: FinancialChartMorphCurve
    let toCurve: FinancialChartMorphCurve
    let fromColor: Color
    let toColor: Color
    let fromRGBA: FinancialChartRGBAColor?
    let toRGBA: FinancialChartRGBAColor?
    let fromReferenceY: CGFloat?
    let toReferenceY: CGFloat?
    let plotRect: CGRect
    let areaBaselineY: CGFloat
    let style: FinancialChartStyle
    let fillsArea: Bool
    let showsEndpointDot: Bool
    let toTradeMarkers: [FinancialChartPlacedTradeMarker]
    let isDarkMode: Bool
    let baseStep: CGFloat
    var animatedStep: CGFloat

    nonisolated var animatableData: CGFloat {
        get { animatedStep }
        set { animatedStep = newValue }
    }

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 1, size.height > 1 else {
                return
            }

            let t = min(max(animatedStep - baseStep, 0), 1)
            let screenPoints = FinancialChartMorphCurve.interpolatedScreenPoints(
                from: fromCurve,
                to: toCurve,
                progress: t,
                in: plotRect
            )
            let blendedColor = FinancialChartColorBlender.blend(
                from: fromColor,
                to: toColor,
                fromRGBA: fromRGBA,
                toRGBA: toRGBA,
                progress: t,
                isDarkMode: isDarkMode
            )

            // Smoothly fade or slide the previous-close dashed reference line during transitions
            drawMorphingReferenceLine(context: &context, t: t)

            FinancialChartAreaRenderer.drawLineAndArea(
                context: &context,
                size: size,
                screenPoints: screenPoints,
                plotRect: plotRect,
                areaBaselineY: areaBaselineY,
                style: style,
                lineColorOverride: blendedColor,
                fillsArea: fillsArea,
                isDarkMode: isDarkMode
            )

            // Keep the endpoint dot gliding cleanly along the morphing curve tip so it never pops in/out
            if showsEndpointDot, let tip = screenPoints.last {
                let haloRect = CGRect(x: tip.x - 7.5, y: tip.y - 7.5, width: 15, height: 15)
                let coreRect = CGRect(x: tip.x - 3.25, y: tip.y - 3.25, width: 6.5, height: 6.5)
                context.fill(Path(ellipseIn: haloRect), with: .color(blendedColor.opacity(0.24)))
                context.fill(Path(ellipseIn: coreRect), with: .color(blendedColor))
            }

            // Gently fade settled trade markers in during the tail of the morph so handoff to BaseCanvas is seamless
            if !toTradeMarkers.isEmpty, t > 0.70 {
                let markerAlpha = Double((t - 0.70) / 0.30)
                FinancialChartTradeMarkerRenderer.draw(
                    context: &context,
                    markers: toTradeMarkers,
                    kind: fillsArea ? .area : .line,
                    style: style,
                    isDarkMode: isDarkMode,
                    opacity: markerAlpha
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func drawMorphingReferenceLine(context: inout GraphicsContext, t: CGFloat) {
        let resolvedY: CGFloat
        let opacityFactor: Double

        switch (fromReferenceY, toReferenceY) {
        case (let y1?, let y2?):
            resolvedY = y1 + (y2 - y1) * t
            opacityFactor = 1.0
        case (nil, let y2?):
            resolvedY = y2
            opacityFactor = Double(t)
        case (let y1?, nil):
            resolvedY = y1
            opacityFactor = Double(1.0 - t)
        case (nil, nil):
            return
        }

        guard opacityFactor > 0.01, resolvedY >= plotRect.minY, resolvedY <= plotRect.maxY else {
            return
        }

        var path = Path()
        path.move(to: CGPoint(x: plotRect.minX, y: resolvedY))
        path.addLine(to: CGPoint(x: plotRect.maxX, y: resolvedY))
        context.stroke(
            path,
            with: .color(style.referenceLineColor.opacity(opacityFactor)),
            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 4])
        )
    }
}

/// Flowing dot-matrix ambient wave displayed on cold load (before any real series is available)
/// instead of a jarring static rectangle skeleton.
struct FinancialChartLoadingWaveView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tint: Color
    let insets: FinancialChartInsets

    var body: some View {
        let isDarkMode = colorScheme == .dark
        let waveColor = tint.opacity(isDarkMode ? 0.55 : 0.48)
        let waveStyle = FinancialChartStyle(
            lineColor: waveColor,
            areaFillStyle: .dotMatrix(spacing: 4.5, dotDiameter: 1.5),
            areaTopOpacity: 0.14,
            areaBottomOpacity: 0.0,
            lineWidth: 2.0,
            glowRadius: 5.0,
            glowOpacity: 0.35,
            showsGrid: false,
            showsVolume: false,
            showsEndpointPulse: false,
            interpolation: .monotone
        )

        Group {
            if reduceMotion {
                waveCanvas(phase: 0.9, style: waveStyle, isDarkMode: isDarkMode)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate * 2.15
                    waveCanvas(phase: phase, style: waveStyle, isDarkMode: isDarkMode)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func waveCanvas(
        phase: Double,
        style: FinancialChartStyle,
        isDarkMode: Bool
    ) -> some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 1, size.height > 1 else {
                return
            }

            let plotRect = CGRect(
                x: insets.leading,
                y: insets.top,
                width: max(size.width - insets.leading - insets.trailing, 1),
                height: max(size.height - insets.top - insets.bottom, 1)
            )
            let wave = FinancialChartMorphCurve.loadingWave(phase: phase)
            let screenPoints = wave.screenPoints(in: plotRect)

            FinancialChartAreaRenderer.drawLineAndArea(
                context: &context,
                size: size,
                screenPoints: screenPoints,
                plotRect: plotRect,
                areaBaselineY: plotRect.maxY,
                style: style,
                fillsArea: true,
                isDarkMode: isDarkMode
            )
        }
    }
}

/// Subtle horizontal light-sweep opacity mask played over the held previous curve while
/// fetching a newly selected period over the network (zero harsh skeleton flash).
struct FinancialChartLoadingSweepMask: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool

    var body: some View {
        if isActive {
            if reduceMotion {
                Color.white.opacity(0.62)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.25) / 1.25
                    let sweepCenter = CGFloat(cycle * 1.6 - 0.3)

                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.46), location: max(0, sweepCenter - 0.28)),
                            .init(color: Color.white.opacity(0.95), location: min(max(sweepCenter, 0), 1)),
                            .init(color: Color.white.opacity(0.46), location: min(1, sweepCenter + 0.28))
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        } else {
            Color.white
        }
    }
}
