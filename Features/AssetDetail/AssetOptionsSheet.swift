import SwiftUI

struct AssetOptionsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var store: AssetOptionsStore

    init(symbol: String, displayName: String) {
        _store = State(initialValue: AssetOptionsStore(symbol: symbol, displayName: displayName))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AssetOptionsFilterBar(store: store)
                Divider()
                AssetOptionsContent(
                    store: store,
                    hasCredentials: app.hasCredentials
                )
            }
            .background(Color(.systemBackground))
            .navigationTitle("\(store.symbol) Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Common.close)
                }
            }
        }
        .task {
            store.start(app: app)
        }
        .onDisappear {
            store.stop()
        }
    }
}

private struct AssetOptionsFilterBar: View {
    let store: AssetOptionsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.symbol)
                        .font(.headline.monospaced().weight(.bold))
                        .foregroundStyle(.primary)

                    if !store.displayName.isEmpty, store.displayName != AppFormatter.placeholder {
                        Text(store.displayName)
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                Label("Delayed quotes", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    .accessibilityLabel("Options quotes are delayed")
            }

            Picker("Type", selection: Binding(
                get: { store.selectedFilter },
                set: { store.selectFilter($0) }
            )) {
                ForEach(AssetOptionTypeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            expirationFilterRow
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var expirationFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                AssetOptionExpirationChip(
                    title: AssetOptionExpirationFilter.all.title,
                    isSelected: store.selectedExpiration == .all
                ) {
                    store.selectExpiration(.all)
                }

                ForEach(store.quickExpirationOptions) { expiration in
                    AssetOptionExpirationChip(
                        title: expiration.title,
                        isSelected: store.selectedExpiration == .exact(expiration)
                    ) {
                        store.selectExpiration(.exact(expiration))
                    }
                }

                if store.isLoadingExpirations {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 32, height: 32)
                }

                if store.shouldShowMoreExpirations {
                    Menu {
                        Button {
                            store.selectExpiration(.all)
                        } label: {
                            Label("All expirations", systemImage: store.selectedExpiration == .all ? "checkmark" : "calendar")
                        }

                        ForEach(store.expirationMenuGroups) { group in
                            Section(group.title) {
                                ForEach(group.expirations) { expiration in
                                    Button {
                                        store.selectExpiration(.exact(expiration))
                                    } label: {
                                        Label(
                                            expiration.menuTitle,
                                            systemImage: store.selectedExpiration == .exact(expiration) ? "checkmark" : "calendar"
                                        )
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("More")
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if let expirationErrorMessage = store.expirationErrorMessage {
                    Text(expirationErrorMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ColorToken.negative)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(AppTheme.ColorToken.negative.opacity(0.10), in: Capsule())
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct AssetOptionsContent: View {
    let store: AssetOptionsStore
    let hasCredentials: Bool

    @ViewBuilder
    var body: some View {
        if !hasCredentials {
            ContentUnavailableView(
                L10n.Common.noData,
                systemImage: AppIcon.More.alpaca
            )
        } else if store.isLoading && store.rows.isEmpty {
            AssetOptionsLoadingView()
        } else {
            optionList
        }
    }

    private var optionList: some View {
        AppInfiniteScrollView(
            alignment: .leading,
            spacing: 0,
            contentMargins: EdgeInsets(
                top: 4,
                leading: AppTheme.Spacing.pageHorizontal,
                bottom: AppTheme.Spacing.pageBottom,
                trailing: AppTheme.Spacing.pageHorizontal
            ),
            canLoadMore: store.canLoadMore,
            isLoadingMore: store.isLoadingMore,
            loadMoreTrigger: store.loadMoreTrigger,
            loadMore: {
                store.loadMoreIfNeeded()
            }
        ) {
            if let errorMessage = store.errorMessage, store.rows.isEmpty {
                AssetOptionsErrorBanner(message: errorMessage) {
                    store.reloadOptions(forceReload: true)
                }
            } else if store.rows.isEmpty {
                ContentUnavailableView(
                    "No options",
                    systemImage: AppIcon.Position.option,
                    description: Text("No \(store.selectedFilter.emptyStateName) contracts were returned for \(store.selectedExpiration.emptyStateSuffix(symbol: store.symbol)).")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                let rows = store.rows
                let lastRowID = rows.last?.id

                ForEach(rows) { row in
                    NavigationLink {
                        OptionDetailView(
                            contractSymbol: row.contractSymbol,
                            initialSnapshot: row.snapshot
                        )
                    } label: {
                        AssetOptionRow(row: row)
                            .equatable()
                    }
                    .buttonStyle(.plain)

                    if row.id != lastRowID {
                        Divider()
                    }
                }

                if let loadMoreErrorMessage = store.loadMoreErrorMessage {
                    AssetOptionsErrorBanner(message: loadMoreErrorMessage) {
                        store.loadMoreIfNeeded(force: true)
                    }
                    .padding(.top, 12)
                }
            }
        }
        .refreshable {
            store.refreshAll(forceReload: true)
        }
    }
}

private struct AssetOptionExpirationChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background(backgroundShape)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if isSelected {
            Capsule()
                .fill(Color(.systemGray))
        } else {
            Capsule()
                .fill(Color(.tertiarySystemGroupedBackground))
        }
    }
}

private struct AssetOptionRow: Equatable, View {
    let row: AssetOptionRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.contractSymbol)
                        .font(.callout.monospaced().weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(row.summaryText)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(row.typeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(row.typeTint)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(row.typeTint.opacity(0.10), in: Capsule())
            }

            LazyVGrid(columns: Self.metricColumns, alignment: .leading, spacing: 10) {
                AssetOptionMetric(title: "Bid", value: row.bidText)
                AssetOptionMetric(title: "Ask", value: row.askText)
                AssetOptionMetric(title: "Mid", value: row.midText)
                AssetOptionMetric(title: "Last", value: row.lastText)
                AssetOptionMetric(title: "IV", value: row.ivText)
                AssetOptionMetric(title: "Delta", value: row.deltaText)
                AssetOptionMetric(title: "Theta", value: row.thetaText)
                AssetOptionMetric(title: "Size", value: row.volumeText)
            }

            Text(row.timeText)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private static let metricColumns = [
        GridItem(.flexible(minimum: 62), spacing: 10),
        GridItem(.flexible(minimum: 62), spacing: 10),
        GridItem(.flexible(minimum: 62), spacing: 10),
        GridItem(.flexible(minimum: 62), spacing: 10)
    ]
}

private struct AssetOptionMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(value == AppFormatter.placeholder ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssetOptionsLoadingView: View {
    var body: some View {
        OptionsChainSkeleton(rowCount: 6)
    }
}

private struct AssetOptionsErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(AppTypography.detail)
                .foregroundStyle(AppTheme.ColorToken.negative)
                .fixedSize(horizontal: false, vertical: true)

            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.negative.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
