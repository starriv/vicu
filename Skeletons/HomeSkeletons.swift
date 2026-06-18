import SwiftUI

struct HomeHeroSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HomeSkeletonBlock(width: 188, height: 48, fill: Color(.secondarySystemFill), cornerRadius: 14)
                HomeSkeletonBlock(width: 116, height: 14, fill: Color(.tertiarySystemFill), cornerRadius: 5)
            }

            HStack(spacing: 8) {
                HomeSkeletonBlock(width: 74, height: 16, fill: Color(.secondarySystemFill), cornerRadius: 5)
                HomeSkeletonBlock(width: 58, height: 16, fill: Color(.tertiarySystemFill), cornerRadius: 5)
                HomeSkeletonBlock(width: 38, height: 16, fill: Color(.tertiarySystemFill), cornerRadius: 5)
            }

            HomeChartSkeleton()
                .frame(height: 230)

            HStack(spacing: 12) {
                HomeRangePickerSkeleton()

                Spacer(minLength: 8)

                HomeChartModePickerSkeleton()
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeSkeletonPresentation()
    }
}

struct HomeAccountMetricsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.group) {
            HomeSkeletonSectionHeader(titleWidth: 86)

            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    HomeMetricRowSkeleton(index: index)

                    if index < 3 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeSkeletonPresentation()
    }
}

struct HomePositionsSummarySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.group) {
            HomeSkeletonSectionHeader(titleWidth: 96, countWidth: 18)
            HomePositionCategoryFilterSkeleton()
            HomePositionRowsSkeleton(rowCount: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeSkeletonPresentation()
    }
}

struct HomeRecentOrdersSummarySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.group) {
            HomeSkeletonSectionHeader(titleWidth: 128, countWidth: 18)
            HomeOrderRowsSkeleton(rowCount: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeSkeletonPresentation()
    }
}

struct HomeChartSkeleton: View {
    var body: some View {
        ZStack {
            HomeChartSkeletonArea()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.ColorToken.brand.opacity(0.18),
                            AppTheme.ColorToken.brand.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            HomeChartSkeletonLine()
                .stroke(AppTheme.ColorToken.brand.opacity(0.72), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HomeMetricRowSkeleton: View {
    let index: Int

    var body: some View {
        HStack(spacing: 14) {
            HomeSkeletonBlock(width: 24, height: 24, fill: Color(.tertiarySystemFill), cornerRadius: 8)
                .frame(width: 30)

            HomeSkeletonBlock(width: titleWidth, height: 16, fill: Color(.secondarySystemFill), cornerRadius: 5)

            Spacer(minLength: 12)

            HomeSkeletonBlock(width: valueWidth, height: 18, fill: Color(.secondarySystemFill), cornerRadius: 5)
        }
        .padding(.vertical, AppTheme.Spacing.rowVertical)
    }

    private var titleWidth: CGFloat {
        [104, 58, 132, 136][index % 4]
    }

    private var valueWidth: CGFloat {
        [112, 88, 104, 78][index % 4]
    }
}

private struct HomePositionCategoryFilterSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: 7) {
                        HomeSkeletonBlock(width: 14, height: 14, fill: Color(.tertiarySystemFill), cornerRadius: 5)
                        HomeSkeletonBlock(width: [46, 34, 48, 42][index], height: 12, fill: Color(.secondarySystemFill), cornerRadius: 4)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color(.separator).opacity(index == 0 ? 0.18 : 0.08))
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct HomePositionRowsSkeleton: View {
    let rowCount: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                HomePositionRowSkeleton(index: index)

                if index < rowCount - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
    }
}

private struct HomePositionRowSkeleton: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HomeSkeletonBlock(width: [54, 42, 62][index % 3], height: 18, fill: Color(.secondarySystemFill), cornerRadius: 5)

                Spacer(minLength: 16)

                HomeSkeletonBlock(width: [92, 106, 84][index % 3], height: 18, fill: Color(.secondarySystemFill), cornerRadius: 5)
            }

            HStack {
                HomeSkeletonBlock(width: [88, 74, 96][index % 3], height: 13, fill: Color(.tertiarySystemFill), cornerRadius: 4)

                Spacer(minLength: 16)

                HomeSkeletonBlock(width: [76, 88, 70][index % 3], height: 13, fill: Color(.tertiarySystemFill), cornerRadius: 4)
                HomeSkeletonBlock(width: 10, height: 13, fill: Color(.tertiarySystemFill), cornerRadius: 4)
            }
        }
        .padding(.vertical, AppTheme.Spacing.rowVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeOrderRowsSkeleton: View {
    let rowCount: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                HomeOrderRowSkeleton(index: index)

                if index < rowCount - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 16)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
    }
}

private struct HomeOrderRowSkeleton: View {
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    HomeSkeletonBlock(width: [52, 44, 58][index % 3], height: 18, fill: Color(.secondarySystemFill), cornerRadius: 5)
                    HomeSkeletonBlock(width: [34, 38, 32][index % 3], height: 15, fill: sideFill, cornerRadius: 5)
                }

                HomeSkeletonBlock(width: [116, 136, 104][index % 3], height: 13, fill: Color(.tertiarySystemFill), cornerRadius: 4)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 7) {
                HomeSkeletonBlock(width: [56, 72, 64][index % 3], height: 15, fill: statusFill, cornerRadius: 5)
                HomeSkeletonBlock(width: [48, 42, 50][index % 3], height: 12, fill: Color(.tertiarySystemFill), cornerRadius: 4)
            }

            HomeSkeletonBlock(width: 10, height: 13, fill: Color(.tertiarySystemFill), cornerRadius: 4)
        }
        .padding(.vertical, AppTheme.Spacing.rowVertical)
    }

    private var sideFill: Color {
        index.isMultiple(of: 2) ? AppTheme.ColorToken.positive.opacity(0.14) : AppTheme.ColorToken.negative.opacity(0.14)
    }

    private var statusFill: Color {
        [AppTheme.ColorToken.positive.opacity(0.14), AppTheme.ColorToken.warning.opacity(0.16), Color(.tertiarySystemFill)][index % 3]
    }
}

private struct HomeRangePickerSkeleton: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                HomeSkeletonBlock(width: 42, height: 30, fill: index == 0 ? AppTheme.ColorToken.brand.opacity(0.18) : Color(.secondarySystemFill), cornerRadius: 15)
            }
        }
    }
}

private struct HomeChartModePickerSkeleton: View {
    var body: some View {
        HomeSkeletonBlock(width: 34, height: 30, fill: Color(.secondarySystemFill), cornerRadius: 15)
    }
}

private struct HomeSkeletonSectionHeader: View {
    let titleWidth: CGFloat
    var countWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 8) {
            HomeSkeletonBlock(width: titleWidth, height: 17, fill: Color(.tertiarySystemFill), cornerRadius: 5)

            Spacer(minLength: 12)

            if let countWidth {
                HomeSkeletonBlock(width: countWidth, height: 15, fill: Color(.tertiarySystemFill), cornerRadius: 5)
            }

            HomeSkeletonBlock(width: 10, height: 13, fill: Color(.tertiarySystemFill), cornerRadius: 4)
        }
    }
}

private struct HomeSkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let fill: Color
    let cornerRadius: CGFloat

    init(width: CGFloat? = nil, height: CGFloat, fill: Color, cornerRadius: CGFloat? = nil) {
        self.width = width
        self.height = height
        self.fill = fill
        self.cornerRadius = cornerRadius ?? height / 2
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

private struct HomeChartSkeletonLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = chartPoints(in: rect)

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

private struct HomeChartSkeletonArea: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = chartPoints(in: rect)

        guard let firstPoint = points.first, let lastPoint = points.last else {
            return path
        }

        path.move(to: CGPoint(x: firstPoint.x, y: rect.maxY))
        path.addLine(to: firstPoint)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: lastPoint.x, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private func chartPoints(in rect: CGRect) -> [CGPoint] {
    [
        CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.58),
        CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.50),
        CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.63),
        CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.45),
        CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.52),
        CGPoint(x: rect.minX + rect.width * 0.60, y: rect.minY + rect.height * 0.36),
        CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.42),
        CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.30),
        CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.24)
    ]
}

private extension View {
    func homeSkeletonPresentation() -> some View {
        redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview("Home Skeletons") {
    ScrollView {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            HomeHeroSkeleton()
            HomeAccountMetricsSkeleton()
            HomePositionsSummarySkeleton()
            HomeRecentOrdersSummarySkeleton()
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.vertical, AppTheme.Spacing.pageTop)
    }
    .background(AppTheme.ColorToken.pageBackground)
}
