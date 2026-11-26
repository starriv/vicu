import SwiftUI

// MARK: - Recent Searches Strip

struct SearchRecentStrip: View {
    let symbols: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.Search.recentTitle)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onClearAll) {
                    Text(L10n.Common.clear)
                        .font(AppTypography.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            onSelect(symbol)
                        } label: {
                            HStack(spacing: 6) {
                                SymbolLogoView(symbol: symbol, size: 18, usesGlass: false)

                                Text(verbatim: symbol)
                                    .font(AppTypography.chip)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 7)
                            .padding(.trailing, 11)
                            .frame(height: 34)
                            .background(AppTheme.ColorToken.groupedSurface, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onRemove(symbol)
                            } label: {
                                Label(L10n.Common.clear, systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Compact Trending Section

struct SearchTrendingSection: View {
    let symbols: [MarketActiveSymbol]
    let sort: MarketMostActiveSort
    let showsSkeleton: Bool
    let canExpand: Bool
    let favoriteSymbols: Set<String>
    let ownedSymbols: Set<String>
    var showsSectionHeader: Bool = false
    let onChangeSort: (MarketMostActiveSort) -> Void
    let onExpand: () -> Void
    let onSelect: (String) -> Void
    let onToggleFavorite: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                if showsSectionHeader {
                    Text(L10n.Markets.popular)
                        .font(AppTypography.sectionHeader)
                        .foregroundStyle(.secondary)
                } else {
                    Text(sort.searchPopularSubtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                SearchSortPillSwitch(selection: sort, onSelect: onChangeSort)
            }

            if showsSkeleton {
                MarketSearchResultsSkeleton(rowCount: 6)
            } else {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 0) {
                        ForEach(symbols) { item in
                            let key = item.symbol.uppercased()
                            SearchTrendingRow(
                                item: item,
                                sort: sort,
                                isFavorite: favoriteSymbols.contains(key),
                                isHeld: ownedSymbols.contains(key),
                                onSelect: { onSelect(item.symbol) },
                                onToggleFavorite: { onToggleFavorite(item.symbol) }
                            )

                            if item.id != symbols.last?.id {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }

                    if canExpand {
                        Divider()
                        Button(action: onExpand) {
                            HStack(spacing: 4) {
                                Text(L10n.Search.showMoreTrending)
                                    .font(AppTypography.caption.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    AppTheme.ColorToken.groupedSurface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
    }
}

private struct SearchSortPillSwitch: View {
    let selection: MarketMostActiveSort
    let onSelect: (MarketMostActiveSort) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MarketMostActiveSort.displayCases) { item in
                let isSelected = item == selection
                Button {
                    onSelect(item)
                } label: {
                    Text(item.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color(.tertiarySystemGroupedBackground))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(AppTheme.ColorToken.groupedSurface, in: Capsule())
    }
}

private struct SearchTrendingRow: View {
    let item: MarketActiveSymbol
    let sort: MarketMostActiveSort
    let isFavorite: Bool
    let isHeld: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onSelect) {
                HStack(spacing: 11) {
                    SymbolLogoView(symbol: item.symbol, size: 32, usesGlass: false)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(verbatim: item.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if isHeld {
                                SearchMicroTag(text: L10n.Search.badgeHeld, tint: AppTheme.ColorToken.brand)
                            }
                        }

                        if let companyName = resolvedCompanyName {
                            Text(companyName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    trailingMetric
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SearchFavoriteIconButton(isFavorite: isFavorite, action: onToggleFavorite)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 54)
        .padding(.vertical, 4)
    }

    private var resolvedCompanyName: String? {
        guard let name = item.companyName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    @ViewBuilder
    private var trailingMetric: some View {
        if let price = item.price {
            VStack(alignment: .trailing, spacing: 2) {
                Text(AppFormatter.money(price))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let percentChange = item.percentChange {
                    Text(AppFormatter.signedPercent(percentChange))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(item.isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative)
                        .lineLimit(1)
                }
            }
        } else if let activityMetric {
            VStack(alignment: .trailing, spacing: 2) {
                Text(AppFormatter.compactNumber(activityMetric.value))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // Caption follows the metric actually shown, which can differ from `sort`
                // when the preferred metric is missing.
                Text(activityMetric.isTrades ? L10n.Markets.sortTrades : L10n.Markets.sortVolume)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var activityMetric: (value: Double, isTrades: Bool)? {
        let trades = item.tradeCount.flatMap { $0 > 0 ? $0 : nil }
        let volume = item.volume.flatMap { $0 > 0 ? $0 : nil }
        switch sort {
        case .trades:
            if let trades { return (trades, true) }
            if let volume { return (volume, false) }
            return nil
        case .volume:
            if let volume { return (volume, false) }
            if let trades { return (trades, true) }
            return nil
        }
    }
}

// MARK: - Search Scope Filter Strip

struct SearchScopeFilterStrip: View {
    let selection: MarketSearchScope
    let onSelect: (MarketSearchScope) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(MarketSearchScope.allCases) { scope in
                    let isSelected = scope == selection
                    Button {
                        onSelect(scope)
                    } label: {
                        Text(scope.localizedTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? AppTheme.ColorToken.brandForeground : .secondary)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(
                                isSelected ? AppTheme.ColorToken.brand : AppTheme.ColorToken.groupedSurface,
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }
}

extension MarketSearchScope {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .all:
            L10n.Search.scopeAll
        case .saved:
            L10n.Search.scopeSaved
        case .etf:
            L10n.Markets.etf
        case .fractional:
            L10n.Search.scopeFractional
        }
    }
}

// MARK: - Compact Search Result Row

struct SearchResultRow: View, @MainActor Equatable {
    let row: MarketSearchRowModel
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    static func == (lhs: SearchResultRow, rhs: SearchResultRow) -> Bool {
        lhs.row == rhs.row && lhs.isFavorite == rhs.isFavorite
    }

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onSelect) {
                HStack(spacing: 11) {
                    SymbolLogoView(symbol: row.symbol, size: 32, usesGlass: false)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(verbatim: row.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if let exchange = row.exchange {
                                Text(verbatim: exchange)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .lineLimit(1)
                            }

                            if row.isHeld {
                                SearchMicroTag(text: L10n.Search.badgeHeld, tint: AppTheme.ColorToken.brand)
                            } else if row.isETF {
                                SearchMicroTag(text: L10n.Markets.etf, tint: .secondary)
                            }
                        }

                        if let companyName = row.companyName {
                            Text(verbatim: companyName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let priceText = row.priceText {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: priceText)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if let percentText = row.percentChangeText {
                                Text(verbatim: percentText)
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(row.isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SearchFavoriteIconButton(isFavorite: isFavorite, action: onToggleFavorite)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 54)
        .padding(.vertical, 4)
    }
}

// MARK: - Direct Ticker Jump Row

struct SearchDirectJumpRow: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppTheme.ColorToken.brand)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Search.directOpenTitle(symbol: symbol))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(L10n.Search.directOpenSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                AppTheme.ColorToken.groupedSurface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Micro Components

struct SearchMicroTag: View {
    let text: LocalizedStringKey
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint == AppTheme.ColorToken.brand ? AppTheme.ColorToken.brandForeground : tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                tint == AppTheme.ColorToken.brand
                    ? AppTheme.ColorToken.brand.opacity(0.92)
                    : Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .lineLimit(1)
    }
}

struct SearchFavoriteIconButton: View {
    let isFavorite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isFavorite ? AppTheme.ColorToken.brand : AppTheme.ColorToken.icon.opacity(0.75))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Markets.favorites)
    }
}
