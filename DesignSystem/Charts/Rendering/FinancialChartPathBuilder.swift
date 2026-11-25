import CoreGraphics
import Foundation
import SwiftUI

enum FinancialChartPathBuilder {
    /// Builds a line path in screen coordinates using either linear segments or
    /// Fritsch-Carlson monotone cubic Hermite interpolation (strictly overshoot-free).
    static func linePath(
        through points: [CGPoint],
        interpolation: FinancialChartInterpolation
    ) -> Path {
        var path = Path()
        guard let first = points.first else {
            return path
        }

        path.move(to: first)
        guard points.count > 1 else {
            return path
        }

        switch interpolation {
        case .linear:
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        case .monotone:
            appendMonotoneCubicPath(to: &path, points: points)
        }

        return path
    }

    static func areaPath(
        linePath: Path,
        points: [CGPoint],
        baselineY: CGFloat
    ) -> Path {
        guard let first = points.first, let last = points.last, points.count > 1 else {
            return Path()
        }

        var path = linePath
        path.addLine(to: CGPoint(x: last.x, y: baselineY))
        path.addLine(to: CGPoint(x: first.x, y: baselineY))
        path.closeSubpath()
        return path
    }

    /// Fritsch-Carlson monotone cubic Hermite spline.
    /// Mathematically guarantees the curve never overshoots local extrema between adjacent points.
    private static func appendMonotoneCubicPath(to path: inout Path, points: [CGPoint]) {
        let count = points.count
        guard count > 2 else {
            path.addLine(to: points[1])
            return
        }

        var dx = [CGFloat](repeating: 0, count: count - 1)
        var dy = [CGFloat](repeating: 0, count: count - 1)
        var secant = [CGFloat](repeating: 0, count: count - 1)

        for i in 0..<(count - 1) {
            dx[i] = points[i + 1].x - points[i].x
            dy[i] = points[i + 1].y - points[i].y
            secant[i] = abs(dx[i]) > 1e-6 ? dy[i] / dx[i] : 0
        }

        var tangent = [CGFloat](repeating: 0, count: count)
        tangent[0] = secant[0]
        tangent[count - 1] = secant[count - 2]

        for i in 1..<(count - 1) {
            if secant[i - 1] * secant[i] <= 0 {
                tangent[i] = 0
            } else {
                tangent[i] = (secant[i - 1] + secant[i]) * 0.5
            }
        }

        for i in 0..<(count - 1) {
            if abs(secant[i]) < 1e-6 {
                tangent[i] = 0
                tangent[i + 1] = 0
            } else {
                let alpha = tangent[i] / secant[i]
                let beta = tangent[i + 1] / secant[i]
                let sumSquares = alpha * alpha + beta * beta
                if sumSquares > 9.0 {
                    let scale = 3.0 / sqrt(sumSquares)
                    tangent[i] = scale * alpha * secant[i]
                    tangent[i + 1] = scale * beta * secant[i]
                }
            }
        }

        for i in 0..<(count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let stepX = dx[i]
            if stepX <= 1e-6 {
                path.addLine(to: p1)
                continue
            }

            let control1 = CGPoint(
                x: p0.x + stepX / 3.0,
                y: p0.y + tangent[i] * stepX / 3.0
            )
            let control2 = CGPoint(
                x: p1.x - stepX / 3.0,
                y: p1.y - tangent[i + 1] * stepX / 3.0
            )
            path.addCurve(to: p1, control1: control1, control2: control2)
        }
    }
}
