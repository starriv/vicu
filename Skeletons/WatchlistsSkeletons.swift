import SwiftUI

struct WatchlistsLoadingView: View {
    var body: some View {
        VStack(spacing: 0) {
            WatchlistTabsSkeleton()

            ScrollView(.vertical, showsIndicators: false) {
                WatchlistAssetListSkeleton(rowCount: 6)
                    .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                    .padding(.top, 12)
                    .padding(.bottom, AppTheme.Spacing.pageBottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WatchlistTabsSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { index in
                    WatchlistTabSkeleton(index: index)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .scrollClipDisabled()
    }
}

private struct WatchlistTabSkeleton: View {
    let index: Int

    var body: some View {
        HStack(spacing: index == 0 ? 8 : 0) {
            if index == 0 {
                Image(systemName: "heart.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }

            VStack(alignment: .leading, spacing: 5) {
                WatchlistsSkeletonBlock(width: titleWidth, height: 14, fill: Color(.secondarySystemFill), cornerRadius: 5)
                WatchlistsSkeletonBlock(width: countWidth, height: 10, fill: Color(.tertiarySystemFill), cornerRadius: 4)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .watchlistTabSkeletonBackground(isSelected: index == 0)
    }

    private var titleWidth: CGFloat {
        [74, 68, 86, 62][index % 4]
    }

    private var countWidth: CGFloat {
        [52, 44, 58, 40][index % 4]
    }
}

private struct WatchlistAssetListSkeleton: View {
    let rowCount: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                WatchlistAssetRowSkeleton(index: index)

                if index < rowCount - 1 {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct WatchlistAssetRowSkeleton: View {
    let index: Int

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 8) {
                WatchlistsSkeletonBlock(width: symbolWidth, height: 18, fill: Color(.secondarySystemFill), cornerRadius: 5)
                WatchlistsSkeletonBlock(width: nameWidth, height: 13, fill: Color(.tertiarySystemFill), cornerRadius: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WatchlistsSkeletonBlock(width: exchangeWidth, height: 14, fill: Color(.secondarySystemFill), cornerRadius: 5)

            WatchlistsSkeletonBlock(width: 8, height: 14, fill: Color(.tertiarySystemFill), cornerRadius: 4)
        }
        .frame(minHeight: 62)
        .padding(.vertical, 8)
    }

    private var symbolWidth: CGFloat {
        [52, 46, 58, 44, 64, 50][index % 6]
    }

    private var nameWidth: CGFloat {
        [174, 218, 156, 194, 132, 204][index % 6]
    }

    private var exchangeWidth: CGFloat {
        [62, 54, 68, 58, 50, 64][index % 6]
    }
}

private struct WatchlistsSkeletonBlock: View {
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

private extension View {
    @ViewBuilder
    func watchlistTabSkeletonBackground(isSelected: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular, in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(isSelected ? 0.18 : 0.08))
                }
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(isSelected ? 0.20 : 0.10))
                }
                .shadow(color: .black.opacity(isSelected ? 0.10 : 0.05), radius: 8, y: 3)
        }
    }
}

#Preview("Watchlists Skeleton") {
    VStack(spacing: 0) {
        AppScreenHeader(background: AppTheme.ColorToken.pageBackground) {
            AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {}
        } center: {
            Text("自选列表")
                .font(.headline.weight(.semibold))
        } trailing: {
            Image(systemName: AppIcon.Market.more)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .modifier(AppGlassCircleModifier())
        }

        WatchlistsLoadingView()
    }
    .background(AppTheme.ColorToken.pageBackground)
}
