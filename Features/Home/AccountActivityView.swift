import SwiftUI

struct AccountActivityView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.locale) private var locale
    @State private var activityRows: [AccountActivityRowModel] = []
    @State private var nextPageToken: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var isLoadingMore = false

    private let pageSize = 100

    var body: some View {
        BasicLayout(L10n.AccountActivity.title, style: .list) {
            AppInfiniteScrollView(
                spacing: 18,
                canLoadMore: nextPageToken != nil,
                isLoadingMore: isLoadingMore,
                loadMoreTrigger: activityRows.count,
                loadMore: loadMoreActivities
            ) {
                content
            }
        }
        .task {
            await loadIfNeeded()
        }
        .refreshable {
            await loadActivities(reset: true)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && activityRows.isEmpty {
            ProgressView(L10n.AccountActivity.loading)
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if activityRows.isEmpty {
            emptyState
        } else {
            AccountActivityList(
                rows: activityRows
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            L10n.AccountActivity.emptyTitle,
            systemImage: AppIcon.Account.activity,
            description: Text(L10n.AccountActivity.emptyDescription)
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await loadActivities(reset: true)
    }

    private func loadActivities(reset: Bool) async {
        guard reset || nextPageToken != nil else {
            return
        }

        guard !isLoading, !isLoadingMore else {
            return
        }

        if reset {
            isLoading = true
            nextPageToken = nil
        } else {
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
            hasLoaded = true
        }

        do {
            let page = try await app.fetchAccountActivities(
                pageSize: pageSize,
                pageToken: reset ? nil : nextPageToken
            )
            guard !Task.isCancelled else {
                return
            }

            if reset {
                activityRows = page.activities.map { AccountActivityRowModel(activity: $0, locale: locale) }
            } else {
                appendActivities(page.activities.map { AccountActivityRowModel(activity: $0, locale: locale) })
            }
            nextPageToken = page.nextPageToken
        } catch where error.isRequestCancellation {
            return
        } catch {
            toastCenter.showError(error, locale: locale)
        }
    }

    @MainActor
    private func loadMoreActivities() async {
        await loadActivities(reset: false)
    }

    private func appendActivities(_ newRows: [AccountActivityRowModel]) {
        var knownIDs = Set(activityRows.map(\.id))
        activityRows.append(contentsOf: newRows.filter { knownIDs.insert($0.id).inserted })
    }
}

private struct AccountActivityList: View {
    let rows: [AccountActivityRowModel]

    var body: some View {
        let lastRowID = rows.last?.id

        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.AccountActivity.recentSection)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    AccountActivityRow(row: row)

                    if row.id != lastRowID {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct AccountActivityRowModel: Identifiable, Equatable {
    let id: String
    let kind: AccountActivityKind
    let title: String
    let timestampText: String
    let summaryText: String
    let tags: [String]

    init(activity: AlpacaAccountActivity, locale: Locale) {
        let kind = AccountActivityKind(activityType: activity.activityType)

        self.id = activity.id
        self.kind = kind
        self.title = kind.title(locale: locale)
        self.timestampText = Self.timestampText(activity: activity)
        self.summaryText = Self.summaryText(activity: activity)
        self.tags = [
            Self.normalized(activity.symbol),
            Self.normalized(activity.side)?.uppercased(),
            Self.normalized(activity.type)?.uppercased()
        ].compactMap { $0 }
    }

    private static func timestampText(activity: AlpacaAccountActivity) -> String {
        if let occurredAt = activity.occurredAt {
            return occurredAt.formatted(
                date: .abbreviated,
                time: activity.transactionTime == nil ? .omitted : .shortened
            )
        }

        return normalized(activity.transactionTime)
            ?? normalized(activity.date)
            ?? AppFormatter.placeholder
    }

    private static func summaryText(activity: AlpacaAccountActivity) -> String {
        if activity.activityType == "FILL" {
            return fillSummaryText(activity: activity)
        }

        if let netAmount = moneyText(activity.netAmount) {
            return netAmount
        }

        if let quantity = numberText(activity.quantity), let perShareAmount = moneyText(activity.perShareAmount) {
            return "\(quantity) x \(perShareAmount)"
        }

        return normalized(activity.description)
            ?? normalized(activity.cusip)
            ?? activity.id
    }

    private static func fillSummaryText(activity: AlpacaAccountActivity) -> String {
        let side = normalized(activity.side)?.uppercased()
        let quantity = numberText(activity.quantity)
        let symbol = normalized(activity.symbol)
        let price = moneyText(activity.price)

        return [side, quantity, symbol]
            .compactMap { $0 }
            .joined(separator: " ")
            .appending(price.map { " @ \($0)" } ?? "")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    private static func numberText(_ value: String?) -> String? {
        let text = AppFormatter.numberText(value)
        return text == AppFormatter.placeholder ? nil : text
    }

    private static func moneyText(_ value: String?) -> String? {
        guard NumberParser.decimal(from: value) != nil else {
            return nil
        }

        return AppFormatter.money(value)
    }
}

private struct AccountActivityRow: View, Equatable {
    let row: AccountActivityRowModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(row.kind.tint)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.title)
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(row.timestampText)
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                Text(row.summaryText)
                    .font(AppTypography.detail)
                    .foregroundStyle(.secondary)
                    .lineSpacing(AppTypography.secondaryLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)

                tagRow
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var tagRow: some View {
        if !row.tags.isEmpty {
            HStack(spacing: 7) {
                ForEach(row.tags, id: \.self) { tag in
                    Text(tag)
                        .font(AppTypography.badge.monospaced())
                        .foregroundStyle(AppTheme.ColorToken.brand)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.ColorToken.brand.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

private enum AccountActivityKind: Equatable {
    case fill
    case transfer
    case dividend
    case fee
    case option
    case corporateAction
    case other(String)

    init(activityType: String) {
        switch activityType.uppercased() {
        case "FILL":
            self = .fill
        case "TRANS", "CSD", "CSW", "ACATC", "ACATS", "FOPT", "JNL", "JNLC", "JNLS":
            self = .transfer
        case "DIV", "DIVCGL", "DIVCGS", "DIVFT", "DIVNRA", "DIVROC", "DIVTW", "DIVTXEX", "CGD":
            self = .dividend
        case "CFEE", "FEE", "DIVFEE", "PTC":
            self = .fee
        case "OPASN", "OPEXP", "OPXRC":
            self = .option
        case "MA", "NC", "PTR", "REORG", "SC", "SSO", "SSP":
            self = .corporateAction
        default:
            self = .other(activityType)
        }
    }

    var systemImage: String {
        switch self {
        case .fill:
            AppIcon.Account.activityFill
        case .transfer:
            AppIcon.Account.activityTransfer
        case .dividend:
            AppIcon.Account.activityDividend
        case .fee:
            AppIcon.Account.activityFee
        case .option:
            AppIcon.Account.activityOption
        case .corporateAction:
            AppIcon.Account.activityCorporateAction
        case .other:
            AppIcon.Account.activity
        }
    }

    var tint: Color {
        switch self {
        case .fill, .dividend:
            AppTheme.ColorToken.positive
        case .fee:
            AppTheme.ColorToken.negative
        case .transfer, .option, .corporateAction, .other:
            AppTheme.ColorToken.icon
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .fill:
            L10n.AccountActivity.tradeFill(locale: locale)
        case .transfer:
            L10n.AccountActivity.transfer(locale: locale)
        case .dividend:
            L10n.AccountActivity.dividend(locale: locale)
        case .fee:
            L10n.AccountActivity.fee(locale: locale)
        case .option:
            L10n.AccountActivity.optionEvent(locale: locale)
        case .corporateAction:
            L10n.AccountActivity.corporateAction(locale: locale)
        case .other(let activityType):
            activityType
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}

#Preview {
    NavigationStack {
        AccountActivityView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
