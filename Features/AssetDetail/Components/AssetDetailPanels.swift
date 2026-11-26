import SwiftUI

struct AssetDetailMarketDataContent: View {
    let store: AssetDetailStore
    let showQuoteHistory: () -> Void
    let showOptions: () -> Void
    let sharePosition: (AlpacaPosition) -> Void

    var body: some View {
        if store.errorMessage != nil, store.asset == nil {
            ContentUnavailableView(
                "Asset data unavailable",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                AssetHeroChartInteractionSection(store: store)
                AssetLevelOnePanel(
                    store: store,
                    showQuoteHistory: showQuoteHistory
                )
                AssetPositionSection(
                    store: store,
                    sharePosition: sharePosition
                )
                AssetDayStatsPanel(store: store)
                AssetAboutPanel(store: store, showOptions: showOptions)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AssetPositionSection: View {
    let store: AssetDetailStore
    let sharePosition: (AlpacaPosition) -> Void

    var body: some View {
        if let position = store.position {
            PositionOverviewPanel(
                position: position,
                onShare: { sharePosition(position) }
            )
        }
    }
}

private struct AssetLevelOnePanel: View {
    let store: AssetDetailStore
    let showQuoteHistory: () -> Void

    var body: some View {
        AssetLevelOneBook(
            bidPrice: store.bidPrice,
            askPrice: store.askPrice,
            bidSize: store.quote?.bidSize,
            askSize: store.quote?.askSize,
            spread: store.spread,
            quoteTime: store.quote?.timestamp,
            showHistory: showQuoteHistory
        )
    }
}

private struct AssetDayStatsPanel: View {
    let store: AssetDetailStore

    var body: some View {
        AssetDetailSection(title: "Key statistics") {
            AssetTodayStatsGrid(
                open: store.dayOpen,
                high: store.dayHigh,
                low: store.dayLow,
                volume: store.dayVolume,
                vwap: store.dailyBar?.vwap,
                trades: store.dailyBar?.tradeCount
            )
            .equatable()
        }
    }
}

private struct AssetTodayStatsGrid: View, Equatable {
    let open: Double?
    let high: Double?
    let low: Double?
    let volume: Double?
    let vwap: Double?
    let trades: Double?

    var body: some View {
        // Static 2x3 Grid avoids LazyVGrid measuring overhead inside ScrollView.
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 18) {
            GridRow {
                AssetDenseMetric(title: "Volume", value: AssetDetailNumber.compact(volume))
                AssetDenseMetric(title: "Open", value: AppFormatter.money(open))
                AssetDenseMetric(title: "VWAP", value: AppFormatter.money(vwap))
            }
            GridRow {
                AssetDenseMetric(title: "High", value: AppFormatter.money(high))
                AssetDenseMetric(title: "Low", value: AppFormatter.money(low))
                AssetDenseMetric(title: "Trades", value: AssetDetailNumber.compact(trades))
            }
        }
        .padding(14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AssetDenseMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssetAboutPanel: View {
    let store: AssetDetailStore
    let showOptions: () -> Void

    @State private var showsCapabilitiesSheet = false
    @State private var opensOptionsAfterCapabilitiesSheet = false

    var body: some View {
        AssetDetailSection(title: "About") {
            VStack(spacing: 0) {
                AssetInfoRow(title: "Name", value: store.displayName)
                AssetInfoRow(title: "Exchange", value: store.exchangeText)
                AssetInfoRow(title: "Type", value: AssetDetailText.assetClass(store.asset?.assetClass))
                AssetInfoRow(title: "Status", value: AssetDetailText.status(store.asset?.status))
                AssetCapabilitiesEntryRow(asset: store.asset) {
                    showsCapabilitiesSheet = true
                }
            }
        }
        .sheet(isPresented: $showsCapabilitiesSheet, onDismiss: openQueuedOptionsSheet) {
            AssetCapabilitiesSheet(
                asset: store.asset,
                openOptions: queueOptionsSheet
            )
        }
    }

    private func queueOptionsSheet() {
        opensOptionsAfterCapabilitiesSheet = true
        showsCapabilitiesSheet = false
    }

    private func openQueuedOptionsSheet() {
        guard opensOptionsAfterCapabilitiesSheet else {
            return
        }

        opensOptionsAfterCapabilitiesSheet = false
        showOptions()
    }
}

private struct AssetCapabilitiesEntryRow: View {
    let asset: AlpacaAsset?
    let action: () -> Void

    var body: some View {
        let count = AssetCapabilityItem.enabledCount(for: asset)

        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.brand)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trading capabilities")
                        .font(AppTypography.detail.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("\(count) available")
                        .font(AppTypography.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityLabel("Trading capabilities")
        .accessibilityValue("\(count) available")
    }
}

private struct AssetCapabilitiesSheet: View {
    let asset: AlpacaAsset?
    let openOptions: () -> Void

    var body: some View {
        let items = AssetCapabilityItem.items(for: asset)

        AppActionSheetContainer(
            title: "Trading capabilities",
            minHeight: 420,
            maxHeight: 640,
            fallbackHeight: 500,
            allowsLargeDetent: true
        ) {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    AssetCapabilitySheetRow(item: item) {
                        openOptions()
                    }

                    if item.id != items.last?.id {
                        AppSheetDivider()
                    }
                }
            }
            .appSheetCard(horizontalPadding: 16, verticalPadding: 4)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }
}

private struct AssetCapabilityItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
    let isEnabled: Bool
    var opensOptions = false

    static func enabledCount(for asset: AlpacaAsset?) -> Int {
        guard let asset else {
            return 0
        }

        var count = 0
        if asset.tradable == true { count += 1 }
        if asset.fractionable == true { count += 1 }
        if asset.hasAttribute("has_options") { count += 1 }
        if asset.hasAttribute("fractional_eh_enabled") { count += 1 }
        if asset.hasAttribute("overnight_tradable") { count += 1 }
        if asset.marginable == true { count += 1 }
        if asset.shortable == true { count += 1 }
        if asset.easyToBorrow == true { count += 1 }
        return count
    }

    static func items(for asset: AlpacaAsset?) -> [AssetCapabilityItem] {
        [
            AssetCapabilityItem(
                id: "tradable",
                title: "Tradable",
                value: AssetDetailText.boolean(asset?.tradable),
                systemImage: "arrow.left.arrow.right",
                isEnabled: asset?.tradable == true
            ),
            AssetCapabilityItem(
                id: "fractional",
                title: "Fractional",
                value: AssetDetailText.boolean(asset?.fractionable),
                systemImage: "chart.pie",
                isEnabled: asset?.fractionable == true
            ),
            AssetCapabilityItem(
                id: "options",
                title: "Options",
                value: AssetDetailText.boolean(asset?.hasAttribute("has_options")),
                systemImage: "square.stack.3d.up",
                isEnabled: asset?.hasAttribute("has_options") == true,
                opensOptions: asset?.hasAttribute("has_options") == true
            ),
            AssetCapabilityItem(
                id: "extended-hours",
                title: "Extended hours",
                value: AssetDetailText.boolean(asset?.hasAttribute("fractional_eh_enabled")),
                systemImage: "clock",
                isEnabled: asset?.hasAttribute("fractional_eh_enabled") == true
            ),
            AssetCapabilityItem(
                id: "overnight",
                title: "Overnight",
                value: AssetDetailText.boolean(asset?.hasAttribute("overnight_tradable")),
                systemImage: "moon",
                isEnabled: asset?.hasAttribute("overnight_tradable") == true
            ),
            AssetCapabilityItem(
                id: "margin",
                title: "Margin",
                value: AssetDetailText.boolean(asset?.marginable),
                systemImage: "creditcard",
                isEnabled: asset?.marginable == true
            ),
            AssetCapabilityItem(
                id: "shortable",
                title: "Shortable",
                value: AssetDetailText.boolean(asset?.shortable),
                systemImage: "arrow.down.right",
                isEnabled: asset?.shortable == true
            ),
            AssetCapabilityItem(
                id: "borrow",
                title: "Borrow",
                value: AssetDetailText.borrowStatus(asset),
                systemImage: "arrow.down.circle",
                isEnabled: asset?.easyToBorrow == true
            )
        ]
    }
}

private struct AssetCapabilitySheetRow: View {
    let item: AssetCapabilityItem
    let openOptions: () -> Void

    private var tint: Color {
        item.isEnabled ? AppTheme.ColorToken.positive : Color(.tertiaryLabel)
    }

    var body: some View {
        if item.opensOptions {
            Button(action: openOptions) {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens options")
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)

            Text(item.title)
                .font(AppTypography.detail)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(item.value)
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(tint.opacity(item.isEnabled ? 0.12 : 0.08), in: Capsule())

            if item.opensOptions {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct AssetInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(AppTypography.detail.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private enum AssetDetailNumber {
    static func compact(_ value: Double?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...2)))
    }
}

private enum AssetDetailText {
    static func assetClass(_ value: String?) -> String {
        title(value) ?? AppFormatter.placeholder
    }

    static func status(_ value: String?) -> String {
        title(value) ?? AppFormatter.placeholder
    }

    static func borrowStatus(_ asset: AlpacaAsset?) -> String {
        guard let asset else {
            return AppFormatter.placeholder
        }

        if let status = title(asset.borrowStatus) {
            return status
        }

        if asset.easyToBorrow == true {
            return "Easy"
        }

        return asset.shortable == true ? "Available" : "Unavailable"
    }

    static func boolean(_ value: Bool?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value ? "Yes" : "No"
    }

    private static func title(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let words = value
            .split(separator: "_")
            .map { word in
                let lowercased = word.lowercased()
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }

        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}

private extension AlpacaAsset {
    func hasAttribute(_ attribute: String) -> Bool {
        attributes?.contains(attribute) == true
    }
}
