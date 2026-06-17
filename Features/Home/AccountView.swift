import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @State private var account: AlpacaAccount?
    @State private var isLoading = false

    var body: some View {
        BasicLayout(L10n.AccountDetail.title, style: .scroll(spacing: 18)) {
            content
        }
        .task {
            await loadAccountIfNeeded()
        }
        .refreshable {
            await loadAccount()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && account == nil {
            ProgressView(L10n.AccountDetail.loading)
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if let account {
            AccountHeader(account: account)
            AccountActivityLink()

            ForEach(AccountSectionModel.sections(for: account)) { section in
                AccountInfoSection(section: section)
            }
        } else {
            ContentUnavailableView(
                LocalizedStringKey("credentials.not_connected"),
                systemImage: AppIcon.Account.profile,
                description: Text(L10n.Credentials.notConnectedDescription(locale: app.appLanguage.locale))
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func loadAccountIfNeeded() async {
        guard account == nil else {
            return
        }

        await loadAccount()
    }

    private func loadAccount() async {
        guard app.hasCredentials else {
            toastCenter.showErrorMessage(L10n.Credentials.apiKeyRequired(locale: app.appLanguage.locale))
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            account = try await app.fetchAccountDetails()
        } catch where error.isRequestCancellation {
            return
        } catch {
            toastCenter.showError(error, locale: app.appLanguage.locale)
        }
    }
}

private struct AccountHeader: View {
    let account: AlpacaAccount

    var body: some View {
        HStack(spacing: 14) {
            AppAccountAvatar(size: 76, iconSize: 58)

            VStack(alignment: .leading, spacing: 7) {
                Text(account.accountNumber ?? AppFormatter.placeholder)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    AccountStatusPill(text: account.status)
                    Text(AccountDetailFormatter.currency(account.currency))
                        .font(AppTypography.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AccountStatusPill: View {
    let text: String?

    private var normalizedText: String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? AppFormatter.placeholder
    }

    private var tint: Color {
        normalizedText == "ACTIVE" ? AppTheme.ColorToken.positive : AppTheme.ColorToken.warning
    }

    var body: some View {
        Text(normalizedText)
            .font(AppTypography.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct AccountActivityLink: View {
    var body: some View {
        NavigationLink {
            AccountActivityView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: AppIcon.Account.activity)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.icon)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.AccountActivity.title)
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(.primary)

                    Text(L10n.AccountActivity.entrySubtitle)
                        .font(AppTypography.detail)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.AccountActivity.entryHint)
    }
}

private struct AccountInfoSection: View {
    let section: AccountSectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(section.rows) { row in
                    AccountInfoRow(row: row)

                    if row.id != section.rows.last?.id {
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

private struct AccountInfoRow: View {
    let row: AccountRowModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(row.tint)
                .frame(width: 28)

            Text(row.title)
                .font(AppTypography.rowTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(row.value)
                .font(AppTypography.detail.monospacedDigit())
                .foregroundStyle(row.valueTint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .padding(.vertical, 12)
    }
}

private struct AccountSectionModel: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let rows: [AccountRowModel]

    static func sections(for account: AlpacaAccount) -> [AccountSectionModel] {
        let currency = account.currency ?? "USD"

        return [
            AccountSectionModel(title: L10n.AccountDetail.overview, rows: [
                AccountRowModel(L10n.AccountDetail.accountNumber, account.accountNumber, "number"),
                AccountRowModel(L10n.AccountDetail.accountID, account.id, "person.text.rectangle"),
                AccountRowModel(L10n.AccountDetail.status, account.status, "checkmark.seal.fill", valueTint: AccountDetailFormatter.statusTint(account.status)),
                AccountRowModel(L10n.AccountDetail.cryptoStatus, account.cryptoStatus, "bitcoinsign.circle", valueTint: AccountDetailFormatter.statusTint(account.cryptoStatus)),
                AccountRowModel(L10n.AccountDetail.currency, AccountDetailFormatter.currency(account.currency), "dollarsign.circle"),
                AccountRowModel(L10n.AccountDetail.createdAt, AccountDetailFormatter.dateTime(account.createdAt), "calendar"),
                AccountRowModel(L10n.AccountDetail.balanceAsOf, account.balanceAsOf, "calendar.badge.clock")
            ]),
            AccountSectionModel(title: L10n.AccountDetail.buyingPowerSection, rows: [
                AccountRowModel(L10n.Account.buyingPower, AppFormatter.money(account.buyingPower, currencyCode: currency), "creditcard"),
                AccountRowModel(L10n.AccountDetail.effectiveBuyingPower, AppFormatter.money(account.effectiveBuyingPower, currencyCode: currency), "bolt.circle"),
                AccountRowModel(L10n.AccountDetail.regtBuyingPower, AppFormatter.money(account.regtBuyingPower, currencyCode: currency), "building.columns"),
                AccountRowModel(L10n.AccountDetail.daytradingBuyingPower, AppFormatter.money(account.daytradingBuyingPower, currencyCode: currency), "clock.arrow.circlepath"),
                AccountRowModel(L10n.AccountDetail.nonMarginableBuyingPower, AppFormatter.money(account.nonMarginableBuyingPower, currencyCode: currency), "lock.circle"),
                AccountRowModel(L10n.AccountDetail.optionsBuyingPower, AppFormatter.money(account.optionsBuyingPower, currencyCode: currency), "slider.horizontal.3"),
                AccountRowModel(L10n.AccountDetail.bodDtbp, AppFormatter.money(account.bodDtbp, currencyCode: currency), "sunrise")
            ]),
            AccountSectionModel(title: L10n.AccountDetail.balances, rows: [
                AccountRowModel(L10n.AccountDetail.portfolioValue, AppFormatter.money(account.portfolioValue, currencyCode: currency), "chart.pie"),
                AccountRowModel(L10n.AccountDetail.equity, AppFormatter.money(account.equity, currencyCode: currency), "sum"),
                AccountRowModel(L10n.AccountDetail.lastEquity, AppFormatter.money(account.lastEquity, currencyCode: currency), "clock"),
                AccountRowModel(L10n.Account.cash, AppFormatter.money(account.cash, currencyCode: currency), "dollarsign.circle"),
                AccountRowModel(L10n.Account.longMarketValue, AppFormatter.money(account.longMarketValue, currencyCode: currency), "arrow.up.right.circle"),
                AccountRowModel(L10n.Account.shortMarketValue, AppFormatter.money(account.shortMarketValue, currencyCode: currency), "arrow.down.right.circle"),
                AccountRowModel(L10n.AccountDetail.positionMarketValue, AppFormatter.money(account.positionMarketValue, currencyCode: currency), "briefcase")
            ]),
            AccountSectionModel(title: L10n.AccountDetail.margin, rows: [
                AccountRowModel(L10n.AccountDetail.multiplier, AccountDetailFormatter.multiplier(account.multiplier), "multiply.circle"),
                AccountRowModel(L10n.AccountDetail.initialMargin, AppFormatter.money(account.initialMargin, currencyCode: currency), "flag"),
                AccountRowModel(L10n.AccountDetail.maintenanceMargin, AppFormatter.money(account.maintenanceMargin, currencyCode: currency), "wrench.adjustable"),
                AccountRowModel(L10n.AccountDetail.lastMaintenanceMargin, AppFormatter.money(account.lastMaintenanceMargin, currencyCode: currency), "clock.badge.checkmark"),
                AccountRowModel(L10n.AccountDetail.sma, AppFormatter.money(account.sma, currencyCode: currency), "waveform.path.ecg")
            ]),
            AccountSectionModel(title: L10n.AccountDetail.trading, rows: [
                AccountRowModel(L10n.AccountDetail.shortingEnabled, AccountDetailFormatter.boolean(account.shortingEnabled), "arrow.down.right.circle", valueTint: AccountDetailFormatter.booleanTint(account.shortingEnabled, positiveWhenTrue: true)),
                AccountRowModel(L10n.AccountDetail.patternDayTrader, AccountDetailFormatter.boolean(account.patternDayTrader), "figure.run.circle", valueTint: AccountDetailFormatter.booleanTint(account.patternDayTrader, positiveWhenTrue: false)),
                AccountRowModel(L10n.AccountDetail.tradingBlocked, AccountDetailFormatter.boolean(account.tradingBlocked), "lock.circle", valueTint: AccountDetailFormatter.booleanTint(account.tradingBlocked, positiveWhenTrue: false)),
                AccountRowModel(L10n.AccountDetail.transfersBlocked, AccountDetailFormatter.boolean(account.transfersBlocked), "arrow.left.arrow.right.circle", valueTint: AccountDetailFormatter.booleanTint(account.transfersBlocked, positiveWhenTrue: false)),
                AccountRowModel(L10n.AccountDetail.accountBlocked, AccountDetailFormatter.boolean(account.accountBlocked), "xmark.octagon", valueTint: AccountDetailFormatter.booleanTint(account.accountBlocked, positiveWhenTrue: false)),
                AccountRowModel(L10n.AccountDetail.tradeSuspendedByUser, AccountDetailFormatter.boolean(account.tradeSuspendedByUser), "pause.circle", valueTint: AccountDetailFormatter.booleanTint(account.tradeSuspendedByUser, positiveWhenTrue: false)),
                AccountRowModel(L10n.AccountDetail.optionsApprovedLevel, AccountDetailFormatter.integer(account.optionsApprovedLevel), "checkmark.seal"),
                AccountRowModel(L10n.AccountDetail.optionsTradingLevel, AccountDetailFormatter.integer(account.optionsTradingLevel), "slider.horizontal.2.square"),
                AccountRowModel(L10n.AccountDetail.cryptoTier, AccountDetailFormatter.integer(account.cryptoTier), "bitcoinsign.circle"),
                AccountRowModel(L10n.AccountDetail.daytradeCount, AccountDetailFormatter.integer(account.daytradeCount), "number.circle")
            ]),
            AccountSectionModel(title: L10n.AccountDetail.feesAdjustments, rows: [
                AccountRowModel(L10n.AccountDetail.accruedFees, AppFormatter.money(account.accruedFees, currencyCode: currency), "receipt"),
                AccountRowModel(L10n.AccountDetail.pendingRegTAFFees, AppFormatter.money(account.pendingRegTAFFees, currencyCode: currency), "hourglass.circle"),
                AccountRowModel(L10n.AccountDetail.intradayAdjustments, AppFormatter.money(account.intradayAdjustments, currencyCode: currency), "arrow.triangle.2.circlepath")
            ])
        ]
    }
}

private struct AccountRowModel: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let tint: Color
    let valueTint: Color

    init(
        _ title: LocalizedStringKey,
        _ value: String?,
        _ systemImage: String,
        tint: Color = AppTheme.ColorToken.icon,
        valueTint: Color = .secondary
    ) {
        self.title = title
        self.value = AccountDetailFormatter.text(value)
        self.systemImage = systemImage
        self.tint = tint
        self.valueTint = valueTint
    }
}

private enum AccountDetailFormatter {
    static func text(_ value: String?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? AppFormatter.placeholder : trimmedValue
    }

    static func boolean(_ value: Bool?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value ? L10n.AccountDetail.yes : L10n.AccountDetail.no
    }

    static func booleanTint(_ value: Bool?, positiveWhenTrue: Bool) -> Color {
        guard let value else {
            return .secondary
        }

        return value == positiveWhenTrue ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    static func integer(_ value: Int?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value.formatted()
    }

    static func multiplier(_ value: String?) -> String {
        let normalized = AppFormatter.numberText(value)
        return normalized == AppFormatter.placeholder ? normalized : "\(normalized)x"
    }

    static func currency(_ value: String?) -> String {
        let normalized = text(value).uppercased()
        guard normalized != AppFormatter.placeholder else {
            return normalized
        }

        return normalized == "USD" ? "🇺🇸 USD" : normalized
    }

    static func dateTime(_ value: String?) -> String {
        guard let date = AlpacaDateParser.date(value) else {
            return AppFormatter.placeholder
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func statusTint(_ value: String?) -> Color {
        text(value).uppercased() == "ACTIVE" ? AppTheme.ColorToken.positive : AppTheme.ColorToken.warning
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
