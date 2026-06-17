import SwiftUI

struct OptionsChainSkeleton: View {
    let rowCount: Int

    init(rowCount: Int = 6) {
        self.rowCount = rowCount
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { index in
                    OptionsChainSkeletonRow(index: index)

                    if index < rowCount - 1 {
                        Divider()
                    }
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AssetPeriodChartSkeleton: View {
    let mode: AssetChartMode
    let tint: Color
    let showsMockSeries: Bool

    init(
        mode: AssetChartMode = .line,
        tint: Color = AppTheme.ColorToken.brand,
        showsMockSeries: Bool = true
    ) {
        self.mode = mode
        self.tint = tint
        self.showsMockSeries = showsMockSeries
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))

            AssetChartSkeletonGrid()
                .stroke(Color(.tertiaryLabel).opacity(0.14), lineWidth: 1)
                .padding(.horizontal, 2)
                .padding(.vertical, 16)

            if showsMockSeries {
                switch mode {
                case .line:
                    AssetChartSkeletonLine()
                        .stroke(tint.opacity(0.72), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 22)

                    Circle()
                        .fill(tint.opacity(0.82))
                        .frame(width: 11, height: 11)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 22)
                        .padding(.bottom, 52)
                case .candles:
                    HStack(alignment: .center, spacing: 7) {
                        ForEach(0..<26, id: \.self) { index in
                            AssetChartCandleSkeleton(index: index, tint: tint)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 24)
                }
            }

            VStack {
                Spacer()

                HStack(spacing: 18) {
                    ForEach(0..<5, id: \.self) { index in
                        AssetSkeletonCapsule(width: [38, 46, 42, 52, 40][index], height: 7, fill: Color(.tertiarySystemFill))
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct OptionsChainSkeletonRow: View {
    let index: Int

    private let columns = [
        GridItem(.flexible(minimum: 62), spacing: 10),
        GridItem(.flexible(minimum: 62), spacing: 10),
        GridItem(.flexible(minimum: 62), spacing: 10),
        GridItem(.flexible(minimum: 62), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    AssetSkeletonCapsule(width: titleWidth, height: 18, fill: Color(.secondarySystemFill), cornerRadius: 5)
                    AssetSkeletonCapsule(width: subtitleWidth, height: 13, fill: Color(.tertiarySystemFill), cornerRadius: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AssetSkeletonCapsule(width: 48, height: 24, fill: badgeTint.opacity(0.12))
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(0..<8, id: \.self) { metricIndex in
                    VStack(alignment: .leading, spacing: 5) {
                        AssetSkeletonCapsule(width: metricTitleWidth(for: metricIndex), height: 10, fill: Color(.tertiarySystemFill), cornerRadius: 3)
                        AssetSkeletonCapsule(width: metricValueWidth(for: metricIndex), height: 15, fill: Color(.secondarySystemFill), cornerRadius: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            AssetSkeletonCapsule(width: 42, height: 11, fill: Color(.tertiarySystemFill), cornerRadius: 4)
        }
        .padding(.vertical, 14)
    }

    private var titleWidth: CGFloat {
        [210, 198, 224, 206, 216, 194][index % 6]
    }

    private var subtitleWidth: CGFloat {
        [138, 126, 148, 132, 154, 118][index % 6]
    }

    private var badgeTint: Color {
        index.isMultiple(of: 2) ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    private func metricTitleWidth(for metricIndex: Int) -> CGFloat {
        [22, 24, 24, 28, 18, 34, 34, 26][metricIndex % 8]
    }

    private func metricValueWidth(for metricIndex: Int) -> CGFloat {
        [68, 62, 66, 60, 36, 44, 42, 28][(metricIndex + index) % 8]
    }
}

private struct AssetChartCandleSkeleton: View {
    let index: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: topSpacer)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint.opacity(index.isMultiple(of: 2) ? 0.62 : 0.34))
                .frame(width: 3, height: wickHeight)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint.opacity(index.isMultiple(of: 2) ? 0.76 : 0.44))
                .frame(width: 7, height: bodyHeight)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint.opacity(index.isMultiple(of: 2) ? 0.62 : 0.34))
                .frame(width: 3, height: lowerWickHeight)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var topSpacer: CGFloat {
        [18, 46, 32, 24, 62, 40, 28, 54][index % 8]
    }

    private var wickHeight: CGFloat {
        [18, 26, 16, 22, 30, 19, 24, 17][index % 8]
    }

    private var bodyHeight: CGFloat {
        [32, 24, 42, 28, 22, 38, 30, 46][index % 8]
    }

    private var lowerWickHeight: CGFloat {
        [22, 14, 28, 18, 24, 16, 30, 20][index % 8]
    }
}

private struct AssetChartSkeletonGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        for offset in [0.25, 0.5, 0.75] {
            let y = rect.minY + rect.height * offset
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        return path
    }
}

private struct AssetChartSkeletonLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.56),
            CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.50),
            CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.62),
            CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.44),
            CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.52),
            CGPoint(x: rect.minX + rect.width * 0.60, y: rect.minY + rect.height * 0.36),
            CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.42),
            CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.30),
            CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.24)
        ]

        guard let firstPoint = points.first else {
            return path
        }

        path.move(to: firstPoint)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }
}

struct AssetSkeletonCapsule: View {
    let width: CGFloat?
    let height: CGFloat
    let fill: Color
    let cornerRadius: CGFloat?

    init(width: CGFloat? = nil, height: CGFloat, fill: Color, cornerRadius: CGFloat? = nil) {
        self.width = width
        self.height = height
        self.fill = fill
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius ?? height / 2, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

#Preview("Options Chain") {
    OptionsChainSkeleton(rowCount: 5)
        .background(Color(.systemBackground))
}

#Preview("Period Chart") {
    VStack(spacing: 24) {
        AssetPeriodChartSkeleton(mode: .line)
            .frame(height: 260)

        AssetPeriodChartSkeleton(mode: .candles, tint: AppTheme.ColorToken.positive)
            .frame(height: 260)
    }
    .padding(20)
    .background(Color(.systemBackground))
}
