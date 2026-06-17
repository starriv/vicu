import SwiftUI

struct PositionsSummaryView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedCategory: PositionAssetCategory?

    var body: some View {
        let snapshot = PositionCategorySnapshot(
            positions: app.portfolio.positions,
            selectedCategory: selectedCategory
        )

        VStack(alignment: .leading, spacing: AppTheme.Spacing.group) {
            NavigationLink {
                PositionsView()
            } label: {
                AppSectionHeader(L10n.Positions.sectionTitle) {
                    HStack(spacing: 6) {
                        if !snapshot.isEmpty {
                            Text("\(app.portfolio.positions.count)")
                                .font(AppTypography.detail.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                L10n.Positions.viewAllAccessibility(
                    count: app.portfolio.positions.count,
                    locale: locale
                )
            )

            if snapshot.isEmpty {
                AppEmptyStateView(
                    title: L10n.Common.noData,
                    systemImage: AppIcon.Position.empty,
                    minHeight: 190
                )
            } else {
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

                    positionList(snapshot.visiblePositions)
                }
            }
        }
    }

    @ViewBuilder
    private func positionList(_ positions: [AlpacaPosition]) -> some View {
        let lastPositionID = positions.last?.id

        VStack(spacing: 0) {
            ForEach(positions) { position in
                NavigationLink {
                    PositionDetailView(position: position)
                } label: {
                    PositionRow(position: position, locale: locale)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(position.accessibilityTitle(locale: locale))

                if position.id != lastPositionID {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
    }

    private var locale: Locale {
        app.appLanguage.locale
    }
}

private struct PositionRow: View {
    let position: AlpacaPosition
    let locale: Locale

    private var profitLossColor: Color {
        guard let value = NumberParser.double(from: position.unrealizedPL) else {
            return .secondary
        }
        return value >= 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(position.symbol)
                    .font(.headline)
                Spacer()
                Text(AppFormatter.money(position.marketValue))
                    .font(AppTypography.rowValue)
            }

            HStack {
                Text("\(L10n.string("positions.quantity_prefix", locale: locale)) \(PositionDisplay.quantityText(position.quantity, assetClass: position.assetClass, symbol: position.symbol, locale: locale))")
                Spacer()
                Text("\(L10n.string("positions.profit_loss_prefix", locale: locale)) \(AppFormatter.money(position.unrealizedPL))")
                    .foregroundStyle(profitLossColor)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .font(AppTypography.rowMeta)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppTheme.Spacing.rowVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private extension AlpacaPosition {
    func accessibilityTitle(locale: Locale) -> String {
        [
            symbol,
            "\(L10n.string("positions.quantity_prefix", locale: locale)) \(PositionDisplay.quantityText(quantity, assetClass: assetClass, symbol: symbol, locale: locale))",
            "\(L10n.string("positions.profit_loss_prefix", locale: locale)) \(AppFormatter.money(unrealizedPL))"
        ].joined(separator: ", ")
    }
}
