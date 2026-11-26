import SwiftUI

struct MarketSearchLandingView: View {
    let store: MarketSearchStore
    let favoriteSymbols: Set<String>
    let ownedSymbols: Set<String>
    let onSelectRecent: (String) -> Void
    let onRemoveRecent: (String) -> Void
    let onClearRecents: () -> Void
    let onChangePopularSort: (MarketMostActiveSort) -> Void
    let onExpandPopular: () -> Void
    let onSelectPopular: (String) -> Void
    let onToggleFavorite: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !store.recentSymbols.isEmpty {
                SearchRecentStrip(
                    symbols: store.recentSymbols,
                    onSelect: onSelectRecent,
                    onRemove: onRemoveRecent,
                    onClearAll: onClearRecents
                )
            }

            if store.shouldShowTrendingSection {
                SearchTrendingSection(
                    symbols: store.displayedPopularSymbols,
                    sort: store.popularSort,
                    showsSkeleton: store.shouldShowPopularSkeleton,
                    canExpand: store.canExpandPopularSymbols,
                    favoriteSymbols: favoriteSymbols,
                    ownedSymbols: ownedSymbols,
                    showsSectionHeader: true,
                    onChangeSort: onChangePopularSort,
                    onExpand: onExpandPopular,
                    onSelect: onSelectPopular,
                    onToggleFavorite: onToggleFavorite
                )
            }
        }
    }
}

struct MarketSearchResultsView: View {
    let query: String
    let store: MarketSearchStore
    let favoriteSymbols: Set<String>
    let onSelectScope: (MarketSearchScope) -> Void
    let onOpenAsset: (String) -> Void
    let onToggleFavorite: (String) -> Void

    private var queryUpper: String {
        query.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SearchScopeFilterStrip(
                selection: store.scope,
                onSelect: onSelectScope
            )

            if store.isCatalogSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(L10n.Search.syncingCatalog)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            if store.isSearching && store.results.isEmpty {
                MarketSearchResultsSkeleton(rowCount: 6)
            } else if store.results.isEmpty {
                VStack(spacing: 12) {
                    if MarketSearchIndex.looksLikeTicker(queryUpper) {
                        SearchDirectJumpRow(symbol: queryUpper) {
                            onOpenAsset(queryUpper)
                        }
                    }

                    AppEmptyStateView(
                        title: L10n.Markets.searchNoResults,
                        message: L10n.Markets.searchNoResultsDescription,
                        systemImage: "magnifyingglass",
                        minHeight: 190
                    ) {
                        if store.scope != .all {
                            Button {
                                onSelectScope(.all)
                            } label: {
                                AppEmptyStateActionButton(L10n.Search.resetScope)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(store.results) { row in
                        SearchResultRow(
                            row: row,
                            isFavorite: favoriteSymbols.contains(row.symbol),
                            onSelect: { onOpenAsset(row.symbol) },
                            onToggleFavorite: { onToggleFavorite(row.symbol) }
                        )
                        .equatable()

                        if row.id != store.results.last?.id {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(
                    AppTheme.ColorToken.groupedSurface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

                if MarketSearchIndex.looksLikeTicker(queryUpper),
                   !store.results.contains(where: { $0.symbol == queryUpper }) {
                    SearchDirectJumpRow(symbol: queryUpper) {
                        onOpenAsset(queryUpper)
                    }
                }
            }
        }
    }
}
