import SwiftUI

struct PositionsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @State private var selectedCategory: PositionAssetCategory?
    @State private var hasLoaded = false
    @State private var positionsSharePayload: PositionsSharePayload?

    var body: some View {
        let snapshot = PositionCategorySnapshot(
            positions: app.portfolio.positions,
            selectedCategory: selectedCategory
        )

        BasicLayout(L10n.Positions.title, style: .scroll(spacing: 18)) {
            if !app.portfolio.positions.isEmpty {
                PositionsShareHeaderButton {
                    positionsSharePayload = PositionsSharePayload(
                        positions: app.portfolio.positions,
                        account: app.portfolio.account
                    )
                }
            }
        } content: {
            content(snapshot: snapshot)
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .topTrailing) {
            if app.portfolio.isRefreshing && hasLoaded {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 18)
                    .padding(.trailing, AppTheme.Spacing.pageHorizontal)
            }
        }
        .refreshable {
            await refreshPositions()
        }
        .task {
            guard !hasLoaded else {
                return
            }

            await refreshPositions()
        }
        .sheet(item: $positionsSharePayload) { payload in
            PositionsShareSheet(payload: payload)
                .presentationDetents([.height(720)])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func content(snapshot: PositionCategorySnapshot) -> some View {
        if app.portfolio.isRefreshing && !hasLoaded && snapshot.isEmpty {
            ProgressView(L10n.Positions.loading)
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if snapshot.isEmpty {
            AppEmptyStateView(
                title: L10n.Positions.emptyTitle,
                message: L10n.Positions.emptyDescription,
                systemImage: AppIcon.Position.empty
            )
        } else {
            PositionsSummaryPanel(
                positions: app.portfolio.positions,
                account: app.portfolio.account
            )

            if let selectedCategory = snapshot.selectedCategory {
                PositionCategoryFilter(
                    selection: Binding(
                        get: { selectedCategory },
                        set: { self.selectedCategory = $0 }
                    ),
                    categories: snapshot.visibleCategories,
                    counts: snapshot.counts,
                    locale: locale
                )
            }

            LazyVStack(spacing: 12) {
                ForEach(snapshot.visiblePositions) { position in
                    NavigationLink {
                        PositionDetailView(position: position)
                    } label: {
                        PositionListCard(position: position, locale: locale)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(position.listAccessibilityTitle(locale: locale))
                }
            }
        }
    }

    private var locale: Locale {
        app.appLanguage.locale
    }

    private func refreshPositions() async {
        do {
            try await app.refreshPositions()
        } catch where error.isRequestCancellation {
            return
        } catch {
            toastCenter.showError(error, locale: locale)
        }

        hasLoaded = true
    }
}

private struct PositionsSummaryPanel: View {
    let positions: [AlpacaPosition]
    let account: AlpacaAccount?

    private var totalMarketValue: Double? {
        Self.sum(positions.map(\.marketValue))
    }

    private var totalUnrealizedPL: Double? {
        Self.sum(positions.map(\.unrealizedPL))
    }

    private var totalIntradayPL: Double? {
        Self.sum(positions.map(\.unrealizedIntradayPL))
    }

    private var currencyCode: String {
        account?.currency ?? "USD"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.Positions.overview)
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("\(positions.count)")
                    .font(AppTypography.detail.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                PositionsSummaryMetric(
                    title: L10n.Positions.totalMarketValue,
                    value: AppFormatter.compactMoney(totalMarketValue),
                    tint: .primary
                )

                PositionsSummaryMetric(
                    title: L10n.Positions.totalUnrealizedPL,
                    value: AppFormatter.signedCompactMoney(totalUnrealizedPL),
                    tint: PositionDisplay.tint(for: totalUnrealizedPL)
                )

                PositionsSummaryMetric(
                    title: L10n.Positions.totalIntradayPL,
                    value: AppFormatter.signedCompactMoney(totalIntradayPL),
                    tint: PositionDisplay.tint(for: totalIntradayPL)
                )
            }

            Divider()
                .opacity(0.36)

            HStack(spacing: 12) {
                PositionsSummaryMetric(
                    title: L10n.Account.buyingPower,
                    value: AppFormatter.compactMoney(account?.buyingPower, currencyCode: currencyCode),
                    tint: .primary
                )

                PositionsSummaryMetric(
                    title: L10n.Account.cash,
                    value: AppFormatter.compactMoney(account?.cash, currencyCode: currencyCode),
                    tint: .primary
                )

                PositionsSummaryMetric(
                    title: L10n.AccountDetail.portfolioValue,
                    value: AppFormatter.compactMoney(account?.portfolioValue, currencyCode: currencyCode),
                    tint: .primary
                )
            }
        }
        .padding(18)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
    }

    private static func sum(_ values: [String?]) -> Double? {
        let parsedValues = values.compactMap(NumberParser.double)
        guard !parsedValues.isEmpty else {
            return nil
        }

        return parsedValues.reduce(0, +)
    }
}

private struct PositionsSummaryMetric: View {
    let title: LocalizedStringKey
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PositionListCard: View {
    let position: AlpacaPosition
    let locale: Locale

    private var sideTint: Color {
        PositionDisplay.sideTint(position.side)
    }

    private var unrealizedTint: Color {
        PositionDisplay.tint(for: position.unrealizedPL)
    }

    private var intradayTint: Color {
        PositionDisplay.tint(for: position.unrealizedIntradayPL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()
                .opacity(0.36)

            metrics
        }
        .padding(16)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: position.assetCategory.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.icon)
                .frame(width: 38, height: 38)
                .background(Color(.tertiarySystemFill), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(PositionDisplay.normalizedSymbol(position.symbol))
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(PositionDisplay.sideText(position.side, locale: locale))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sideTint)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(position.assetCategory.title(locale: locale))
                    Text(PositionDisplay.apiValue(position.exchange))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

                Text(PositionDisplay.quantityText(
                    position.quantity,
                    assetClass: position.assetClass,
                    symbol: position.symbol,
                    locale: locale
                ))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 7) {
                AppPriceText(
                    position.marketValue,
                    font: .headline.monospacedDigit().weight(.semibold),
                    minimumScaleFactor: 0.76,
                    notation: .compact
                )

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
            PositionListMetric(
                title: L10n.PositionDetail.unrealizedPL,
                value: "\(PositionDisplay.signedCompactMoney(position.unrealizedPL)) \(PositionDisplay.signedPercent(position.unrealizedPLPC))",
                valueTint: unrealizedTint
            )

            PositionListMetric(
                title: L10n.PositionDetail.today,
                value: "\(PositionDisplay.signedCompactMoney(position.unrealizedIntradayPL)) \(PositionDisplay.signedPercent(position.unrealizedIntradayPLPC))",
                valueTint: intradayTint
            )

            PositionListMetric(
                title: L10n.PositionDetail.availableShort,
                value: PositionDisplay.quantityText(
                    position.quantityAvailable,
                    assetClass: position.assetClass,
                    symbol: position.symbol,
                    locale: locale
                )
            )

            PositionListMetric(
                title: L10n.PositionDetail.averageEntryPriceShort,
                value: AppFormatter.compactMoney(position.averageEntryPrice)
            )

            PositionListMetric(
                title: L10n.PositionDetail.currentPrice,
                value: AppFormatter.compactMoney(position.currentPrice)
            )

            PositionListMetric(
                title: L10n.PositionDetail.costBasisShort,
                value: AppFormatter.compactMoney(position.costBasis)
            )
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }
}

private struct PositionListMetric: View {
    let title: LocalizedStringKey
    let value: String
    var valueTint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension AlpacaPosition {
    func listAccessibilityTitle(locale: Locale) -> String {
        [
            PositionDisplay.normalizedSymbol(symbol),
            PositionDisplay.sideText(side, locale: locale),
            PositionDisplay.quantityText(quantity, assetClass: assetClass, symbol: symbol, locale: locale),
            AppFormatter.money(marketValue),
            PositionDisplay.signedMoney(unrealizedPL)
        ].joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        PositionsView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
