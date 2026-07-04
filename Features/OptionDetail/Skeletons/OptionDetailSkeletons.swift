import SwiftUI

struct OptionDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                AssetSkeletonCapsule(width: 230, height: 22, fill: Color(.secondarySystemFill), cornerRadius: 6)
                AssetSkeletonCapsule(width: 160, height: 14, fill: Color(.tertiarySystemFill), cornerRadius: 5)
                AssetSkeletonCapsule(width: 240, height: 28, fill: Color(.tertiarySystemFill))
            }

            AssetSkeletonCapsule(width: 150, height: 48, fill: Color(.secondarySystemFill), cornerRadius: 16)

            OptionChartLoadingBackground(tint: AppTheme.ColorToken.positive)
                .frame(height: 300)

            LazyVGrid(columns: AssetDetailGrid.twoColumns, spacing: 12) {
                ForEach(0..<8, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        AssetSkeletonCapsule(width: [56, 68, 44, 62][index % 4], height: 11, fill: Color(.tertiarySystemFill), cornerRadius: 4)
                        AssetSkeletonCapsule(width: [82, 74, 96, 58][index % 4], height: 17, fill: Color(.secondarySystemFill), cornerRadius: 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct OptionChartLoadingBackground: View {
    let tint: Color

    var body: some View {
        ZStack {
            Color(.systemBackground)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct OptionTradesSkeleton: View {
    let rowCount: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        AssetSkeletonCapsule(width: [74, 86, 66][index % 3], height: 16, fill: Color(.secondarySystemFill), cornerRadius: 5)
                        AssetSkeletonCapsule(width: [90, 72, 82][index % 3], height: 11, fill: Color(.tertiarySystemFill), cornerRadius: 4)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        AssetSkeletonCapsule(width: [42, 54, 36][index % 3], height: 16, fill: Color(.secondarySystemFill), cornerRadius: 5)
                        AssetSkeletonCapsule(width: 34, height: 11, fill: Color(.tertiarySystemFill), cornerRadius: 4)
                    }
                }
                .padding(.vertical, 12)

                if index < rowCount - 1 {
                    Divider()
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Option Detail Skeleton") {
    ScrollView {
        OptionDetailSkeleton()
            .padding(20)
    }
    .background(Color(.systemBackground))
}

#Preview("Option Trades Skeleton") {
    OptionTradesSkeleton(rowCount: 5)
        .padding(.horizontal, 14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(20)
        .background(AppTheme.ColorToken.pageBackground)
}
