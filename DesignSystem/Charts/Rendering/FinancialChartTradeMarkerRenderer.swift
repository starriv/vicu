import SwiftUI
import UIKit

/// High-performance trade marker renderer using pre-baked `@3x` badge sprites and batched `Path` draws.
///
/// Performance guarantees:
/// - Zero CoreText layout or glyph rasterization during `Canvas` drawing (all badges come from a tiny
///   8-entry `@3x` image cache, matching `FinancialChartDotMatrixTileCache`).
/// - All stems, anchor dots, and candle pointers are batched by side into 2-4 draw calls total.
/// - Rendered inside `FinancialChartBaseCanvas` (Equatable), so 120Hz scrubbing triggers zero redraws.
@MainActor
enum FinancialChartTradeMarkerRenderer {
    static func draw(
        context: inout GraphicsContext,
        markers: [FinancialChartPlacedTradeMarker],
        kind: FinancialChartKind,
        style: FinancialChartStyle,
        isDarkMode: Bool,
        opacity: Double = 1.0
    ) {
        guard !markers.isEmpty, opacity > 0.01 else {
            return
        }

        let drawBody: (inout GraphicsContext) -> Void = { ctx in
            let bgCutoutColor = isDarkMode ? Color.black : Color.white

            switch kind {
            case .line, .area:
                var buyStems = Path()
                var sellStems = Path()
                var anchorCutouts = Path()
                var buyDots = Path()
                var sellDots = Path()

                for marker in markers {
                    let dx = marker.badgeCenter.x - marker.anchorPoint.x
                    let dy = marker.badgeCenter.y - marker.anchorPoint.y
                    let dist = hypot(dx, dy)
                    if dist > 4.0 {
                        var stem = Path()
                        stem.move(to: marker.anchorPoint)
                        stem.addLine(to: marker.badgeCenter)
                        if marker.side == .buy {
                            buyStems.addPath(stem)
                        } else {
                            sellStems.addPath(stem)
                        }
                    }

                    let cutoutRect = CGRect(
                        x: marker.anchorPoint.x - 3.3,
                        y: marker.anchorPoint.y - 3.3,
                        width: 6.6,
                        height: 6.6
                    )
                    anchorCutouts.addEllipse(in: cutoutRect)

                    let dotRect = CGRect(
                        x: marker.anchorPoint.x - 2.15,
                        y: marker.anchorPoint.y - 2.15,
                        width: 4.3,
                        height: 4.3
                    )
                    if marker.side == .buy {
                        buyDots.addEllipse(in: dotRect)
                    } else {
                        sellDots.addEllipse(in: dotRect)
                    }
                }

                let stemStyle = StrokeStyle(lineWidth: 1.0, lineCap: .round)
                if !buyStems.isEmpty {
                    ctx.stroke(buyStems, with: .color(style.positiveColor.opacity(isDarkMode ? 0.62 : 0.52)), style: stemStyle)
                }
                if !sellStems.isEmpty {
                    ctx.stroke(sellStems, with: .color(style.negativeColor.opacity(isDarkMode ? 0.62 : 0.52)), style: stemStyle)
                }
                if !anchorCutouts.isEmpty {
                    ctx.fill(anchorCutouts, with: .color(bgCutoutColor))
                }
                if !buyDots.isEmpty {
                    ctx.fill(buyDots, with: .color(style.positiveColor))
                }
                if !sellDots.isEmpty {
                    ctx.fill(sellDots, with: .color(style.negativeColor))
                }

            case .candles:
                var buyPointers = Path()
                var sellPointers = Path()
                let badgeRadius = FinancialChartTradeMarkerLayout.badgeDiameter * 0.5

                for marker in markers {
                    let tipX = marker.anchorPoint.x
                    let tipY = marker.anchorPoint.y
                    let baseHalfWidth: CGFloat = 2.6

                    if marker.isBelowAnchor {
                        let baseY = min(marker.badgeCenter.y - badgeRadius + 1.5, tipY + 5.5)
                        if baseY > tipY + 1.0 {
                            buyPointers.move(to: CGPoint(x: tipX, y: tipY))
                            buyPointers.addLine(to: CGPoint(x: tipX - baseHalfWidth, y: baseY))
                            buyPointers.addLine(to: CGPoint(x: tipX + baseHalfWidth, y: baseY))
                            buyPointers.closeSubpath()
                        }
                    } else {
                        let baseY = max(marker.badgeCenter.y + badgeRadius - 1.5, tipY - 5.5)
                        if baseY < tipY - 1.0 {
                            sellPointers.move(to: CGPoint(x: tipX, y: tipY))
                            sellPointers.addLine(to: CGPoint(x: tipX - baseHalfWidth, y: baseY))
                            sellPointers.addLine(to: CGPoint(x: tipX + baseHalfWidth, y: baseY))
                            sellPointers.closeSubpath()
                        }
                    }
                }

                if !buyPointers.isEmpty {
                    ctx.fill(buyPointers, with: .color(style.positiveColor.opacity(0.92)))
                }
                if !sellPointers.isEmpty {
                    ctx.fill(sellPointers, with: .color(style.negativeColor.opacity(0.92)))
                }
            }

            // Blit pre-cached @3x badge sprites (zero CoreText cost per draw).
            for marker in markers {
                let image = FinancialChartTradeMarkerImageCache.badgeImage(
                    side: marker.side,
                    isDarkMode: isDarkMode,
                    isCluster: marker.clusterCount > 1
                )
                ctx.draw(image, at: marker.badgeCenter, anchor: .center)
            }
        }

        if opacity < 0.999 {
            context.drawLayer { layer in
                layer.opacity = opacity
                drawBody(&layer)
            }
        } else {
            drawBody(&context)
        }
    }
}

/// Pre-renders and caches tiny `@3x` trade marker badge sprites (`B` / `S`) with cutout rings
/// so rendering dozens of markers executes as fast GPU texture blits.
@MainActor
private enum FinancialChartTradeMarkerImageCache {
    private struct Key: Hashable {
        let side: FinancialChartTradeSide
        let isDarkMode: Bool
        let isCluster: Bool
    }

    private static var cache: [Key: Image] = [:]
    private static let canvasSize = CGSize(width: 22, height: 22)

    static func badgeImage(
        side: FinancialChartTradeSide,
        isDarkMode: Bool,
        isCluster: Bool
    ) -> Image {
        let key = Key(side: side, isDarkMode: isDarkMode, isCluster: isCluster)
        if let cached = cache[key] {
            return cached
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        let traits = UITraitCollection(userInterfaceStyle: isDarkMode ? .dark : .light)
        let semanticColor: UIColor = (side == .buy ? UIColor.systemGreen : UIColor.systemRed).resolvedColor(with: traits)
        let cutoutColor = UIColor.systemBackground.resolvedColor(with: traits)
        let glyph = side == .buy ? "B" : "S"

        let uiImage = renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)

            // 1) Soft ambient glow (dark) or subtle elevation shadow (light) matching chart aesthetic
            if isDarkMode {
                let haloDiameter: CGFloat = 19.6
                let haloRect = CGRect(
                    x: center.x - haloDiameter * 0.5,
                    y: center.y - haloDiameter * 0.5,
                    width: haloDiameter,
                    height: haloDiameter
                )
                cg.setFillColor(semanticColor.withAlphaComponent(0.22).cgColor)
                cg.fillEllipse(in: haloRect)
            } else {
                cg.saveGState()
                cg.setShadow(
                    offset: CGSize(width: 0, height: 1.0),
                    blur: 2.2,
                    color: UIColor.black.withAlphaComponent(0.14).cgColor
                )
            }

            // 2) Crisp cutout ring separating badge from dot-matrix / candles
            let ringDiameter: CGFloat = 17.6
            let ringRect = CGRect(
                x: center.x - ringDiameter * 0.5,
                y: center.y - ringDiameter * 0.5,
                width: ringDiameter,
                height: ringDiameter
            )
            cg.setFillColor(cutoutColor.cgColor)
            cg.fillEllipse(in: ringRect)

            if !isDarkMode {
                cg.restoreGState()
            }

            // 3) Solid semantic circular badge
            let badgeDiameter: CGFloat = FinancialChartTradeMarkerLayout.badgeDiameter
            let badgeRect = CGRect(
                x: center.x - badgeDiameter * 0.5,
                y: center.y - badgeDiameter * 0.5,
                width: badgeDiameter,
                height: badgeDiameter
            )
            cg.setFillColor(semanticColor.cgColor)
            cg.fillEllipse(in: badgeRect)

            // 4) Crisp heavy rounded glyph ("B" / "S")
            let baseFont = UIFont.systemFont(ofSize: 8.6, weight: .heavy)
            let roundedFont: UIFont
            if let descriptor = baseFont.fontDescriptor.withDesign(.rounded) {
                roundedFont = UIFont(descriptor: descriptor, size: 8.6)
            } else {
                roundedFont = baseFont
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: roundedFont,
                .foregroundColor: UIColor.white
            ]
            let attributed = NSAttributedString(string: glyph, attributes: attributes)
            let textSize = attributed.size()
            let textOrigin = CGPoint(
                x: center.x - textSize.width * 0.5,
                y: center.y - textSize.height * 0.5 + 0.15
            )
            attributed.draw(at: textOrigin)

            // 5) Subtle multi-fill indicator pip on top-trailing rim when multiple fills merged
            if isCluster {
                let pipCenter = CGPoint(x: center.x + 5.7, y: center.y - 5.5)
                let pipOuter = CGRect(x: pipCenter.x - 2.6, y: pipCenter.y - 2.6, width: 5.2, height: 5.2)
                let pipInner = CGRect(x: pipCenter.x - 1.65, y: pipCenter.y - 1.65, width: 3.3, height: 3.3)
                cg.setFillColor(cutoutColor.cgColor)
                cg.fillEllipse(in: pipOuter)
                cg.setFillColor(semanticColor.cgColor)
                cg.fillEllipse(in: pipInner)
            }
        }

        let image = Image(uiImage: uiImage)
        cache[key] = image
        return image
    }
}
