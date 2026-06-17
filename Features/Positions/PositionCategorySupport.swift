import SwiftUI

struct PositionCategorySnapshot {
    let selectedCategory: PositionAssetCategory?
    let visibleCategories: [PositionAssetCategory]
    let visiblePositions: [AlpacaPosition]
    let counts: [PositionAssetCategory: Int]
    let isEmpty: Bool

    init(positions: [AlpacaPosition], selectedCategory: PositionAssetCategory?) {
        let categoryCounts = Self.categoryCounts(for: positions)
        let categories = PositionAssetCategory.allCases.filter { categoryCounts[$0, default: 0] > 0 }
        let resolvedCategory = selectedCategory.flatMap { category in
            categoryCounts[category, default: 0] > 0 ? category : nil
        } ?? categories.first

        counts = categoryCounts
        visibleCategories = categories
        self.selectedCategory = resolvedCategory
        visiblePositions = resolvedCategory.map { category in
            positions.filter { $0.assetCategory == category }
        } ?? []
        isEmpty = positions.isEmpty
    }

    static func categoryCounts(for positions: [AlpacaPosition]) -> [PositionAssetCategory: Int] {
        positions.reduce(into: [:]) { counts, position in
            counts[position.assetCategory, default: 0] += 1
        }
    }
}

struct PositionCategoryFilter: View {
    @Binding var selection: PositionAssetCategory
    let categories: [PositionAssetCategory]
    let counts: [PositionAssetCategory: Int]
    let locale: Locale

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    chipRow
                }
            } else {
                chipRow
            }
        }
        .scrollClipDisabled()
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(categories) { category in
                AppFilterChip(
                    title: L10n.PositionCategory.chipTitle(category, locale: locale),
                    systemImage: category.systemImage,
                    tint: AppTheme.ColorToken.icon,
                    isSelected: selection == category
                ) {
                    withAnimation(.snappy) {
                        selection = category
                    }
                }
                .accessibilityLabel(
                    L10n.Positions.categoryAccessibility(
                        title: category.title(locale: locale),
                        count: counts[category, default: 0],
                        locale: locale
                    )
                )
            }
        }
    }
}
