import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.locale) private var locale
    @State private var account: AlpacaAccount?
    @State private var isLoading = false

    private var displayedAccount: AlpacaAccount? {
        account ?? app.portfolio.account
    }

    var body: some View {
        Group {
            if let activeAccount = displayedAccount {
                accountList(for: activeAccount)
            } else if isLoading {
                ProgressView(L10n.AccountDetail.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
            } else {
                ContentUnavailableView(
                    LocalizedStringKey("credentials.not_connected"),
                    systemImage: AppIcon.Account.profile,
                    description: Text(L10n.Credentials.notConnectedDescription(locale: locale))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
            }
        }
        .navigationTitle(L10n.AccountDetail.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAccountIfNeeded()
        }
    }

    private func accountList(for account: AlpacaAccount) -> some View {
        let sections = AccountSectionModel.sections(for: account, locale: locale)

        return List {
            Section {
                AccountHeroHeader(
                    account: account,
                    isPaperTrading: app.environment == .paper
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                NavigationLink {
                    AccountActivityView()
                } label: {
                    AppSettingsRow(
                        title: L10n.AccountActivity.title,
                        subtitle: L10n.string("account_activity.entry_subtitle", locale: locale),
                        systemImage: AppIcon.Account.activity,
                        badgeColor: .blue
                    )
                }
                .accessibilityHint(L10n.AccountActivity.entryHint)
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        AccountInfoRow(row: row)
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await loadAccount()
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
            toastCenter.showErrorMessage(L10n.Credentials.apiKeyRequired(locale: locale))
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            account = try await app.fetchAccountDetails()
        } catch where error.isRequestCancellation {
            return
        } catch {
            toastCenter.showError(error, locale: locale)
        }
    }
}

private struct AccountHeroHeader: View {
    let account: AlpacaAccount
    let isPaperTrading: Bool

    @State private var isPaperTipPresented = false

    private var accountTitle: String {
        AccountDetailFormatter.clean(account.accountNumber) ?? AppFormatter.placeholder
    }

    var body: some View {
        VStack(spacing: 12) {
            AppAccountAvatar(size: 74, iconSize: 70)
                .modifier(AccountAvatarRingModifier())

            VStack(spacing: 8) {
                Text(accountTitle)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    AccountStatusPill(text: account.status)

                    if isPaperTrading {
                        AccountPaperTradingPill(isPresented: $isPaperTipPresented)
                    }

                    AccountCurrencyPill(text: AccountDetailFormatter.currency(account.currency))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

private struct AccountAvatarRingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(3)
                .glassEffect(.regular, in: .circle)
        } else {
            content
                .overlay {
                    Circle()
                        .strokeBorder(Color(.separator).opacity(0.22), lineWidth: 1)
                }
        }
    }
}

private struct AccountPaperTradingPill: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(L10n.AccountDetail.paperBadge)

                Image(systemName: "info.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(AppTheme.ColorToken.brandForeground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(AppTheme.ColorToken.brand, in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            AccountPaperTradingTooltip()
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(L10n.AccountDetail.paperBadge)
        .accessibilityHint(L10n.AccountDetail.paperBannerMessage)
    }
}

private struct AccountPaperTradingTooltip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.AccountDetail.paperBadge)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(L10n.AccountDetail.paperBannerMessage)
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)
                .lineSpacing(AppTypography.secondaryLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
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
        HStack(spacing: 5) {
            AppSettingsStatusDot(color: tint, size: 6)

            Text(normalizedText)
                .font(AppTypography.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

private struct AccountCurrencyPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTypography.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

private struct AccountInfoRow: View {
    let row: AccountRowModel

    var body: some View {
        HStack(spacing: 12) {
            AppSettingsCompactBadge(
                systemImage: row.systemImage,
                color: row.badgeColor
            )

            Text(row.title)
                .font(AppTypography.rowTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 12)

            valueContent
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var valueContent: some View {
        if let copyValue = row.copyValue, AccountDetailFormatter.clean(copyValue) != nil {
            AppCopyableIdentifier(
                value: copyValue,
                displayValue: row.value,
                accessibilityLabel: row.title,
                style: .plain
            )
        } else {
            Text(row.value)
                .font(AppTypography.rowMeta.monospacedDigit())
                .foregroundStyle(row.valueTint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
    }
}

private struct AccountSectionModel: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let rows: [AccountRowModel]

    static func sections(for account: AlpacaAccount, locale: Locale) -> [AccountSectionModel] {
        let currency = account.currency ?? "USD"

        return [
            AccountSectionModel(id: "overview", title: L10n.AccountDetail.overview, rows: [
                AccountRowModel("overview.number", L10n.AccountDetail.accountNumber, account.accountNumber, "number", badgeColor: .blue),
                AccountRowModel("overview.id", L10n.AccountDetail.accountID, account.id, "person.text.rectangle", badgeColor: .blue, copyValue: account.id),
                AccountRowModel("overview.status", L10n.AccountDetail.status, account.status, "checkmark.seal.fill", badgeColor: AccountDetailFormatter.statusTint(account.status), valueTint: AccountDetailFormatter.statusTint(account.status)),
                AccountRowModel("overview.crypto", L10n.AccountDetail.cryptoStatus, account.cryptoStatus, "bitcoinsign.circle", badgeColor: .orange, valueTint: AccountDetailFormatter.statusTint(account.cryptoStatus)),
                AccountRowModel("overview.currency", L10n.AccountDetail.currency, AccountDetailFormatter.currency(account.currency), "dollarsign.circle", badgeColor: .green),
                AccountRowModel("overview.created", L10n.AccountDetail.createdAt, AccountDetailFormatter.dateTime(account.createdAt), "calendar", badgeColor: .blue),
                AccountRowModel("overview.balanceAsOf", L10n.AccountDetail.balanceAsOf, account.balanceAsOf, "calendar.badge.clock", badgeColor: .blue)
            ]),
            AccountSectionModel(id: "buyingPower", title: L10n.AccountDetail.buyingPowerSection, rows: [
                AccountRowModel("bp.total", L10n.Account.buyingPower, AppFormatter.compactMoney(account.buyingPower, currencyCode: currency), "creditcard", badgeColor: .green),
                AccountRowModel("bp.effective", L10n.AccountDetail.effectiveBuyingPower, AppFormatter.compactMoney(account.effectiveBuyingPower, currencyCode: currency), "bolt.circle", badgeColor: .green),
                AccountRowModel("bp.regt", L10n.AccountDetail.regtBuyingPower, AppFormatter.compactMoney(account.regtBuyingPower, currencyCode: currency), "building.columns", badgeColor: .green),
                AccountRowModel("bp.daytrading", L10n.AccountDetail.daytradingBuyingPower, AppFormatter.compactMoney(account.daytradingBuyingPower, currencyCode: currency), "clock.arrow.circlepath", badgeColor: .green),
                AccountRowModel("bp.nonMarginable", L10n.AccountDetail.nonMarginableBuyingPower, AppFormatter.compactMoney(account.nonMarginableBuyingPower, currencyCode: currency), "lock.circle", badgeColor: .green),
                AccountRowModel("bp.options", L10n.AccountDetail.optionsBuyingPower, AppFormatter.compactMoney(account.optionsBuyingPower, currencyCode: currency), "slider.horizontal.3", badgeColor: .green),
                AccountRowModel("bp.bodDtbp", L10n.AccountDetail.bodDtbp, AppFormatter.compactMoney(account.bodDtbp, currencyCode: currency), "sunrise", badgeColor: .green)
            ]),
            AccountSectionModel(id: "balances", title: L10n.AccountDetail.balances, rows: [
                AccountRowModel("bal.portfolio", L10n.AccountDetail.portfolioValue, AppFormatter.compactMoney(account.portfolioValue, currencyCode: currency), "chart.pie", badgeColor: .teal),
                AccountRowModel("bal.equity", L10n.AccountDetail.equity, AppFormatter.compactMoney(account.equity, currencyCode: currency), "sum", badgeColor: .teal),
                AccountRowModel("bal.lastEquity", L10n.AccountDetail.lastEquity, AppFormatter.compactMoney(account.lastEquity, currencyCode: currency), "clock", badgeColor: .teal),
                AccountRowModel("bal.cash", L10n.Account.cash, AppFormatter.compactMoney(account.cash, currencyCode: currency), "dollarsign.circle", badgeColor: .teal),
                AccountRowModel("bal.long", L10n.Account.longMarketValue, AppFormatter.compactMoney(account.longMarketValue, currencyCode: currency), "arrow.up.right.circle", badgeColor: .teal),
                AccountRowModel("bal.short", L10n.Account.shortMarketValue, AppFormatter.compactMoney(account.shortMarketValue, currencyCode: currency), "arrow.down.right.circle", badgeColor: .teal),
                AccountRowModel("bal.position", L10n.AccountDetail.positionMarketValue, AppFormatter.compactMoney(account.positionMarketValue, currencyCode: currency), "briefcase", badgeColor: .teal)
            ]),
            AccountSectionModel(id: "margin", title: L10n.AccountDetail.margin, rows: [
                AccountRowModel("margin.multiplier", L10n.AccountDetail.multiplier, AccountDetailFormatter.multiplier(account.multiplier), "multiply.circle", badgeColor: .indigo),
                AccountRowModel("margin.initial", L10n.AccountDetail.initialMargin, AppFormatter.compactMoney(account.initialMargin, currencyCode: currency), "flag", badgeColor: .indigo),
                AccountRowModel("margin.maintenance", L10n.AccountDetail.maintenanceMargin, AppFormatter.compactMoney(account.maintenanceMargin, currencyCode: currency), "wrench.adjustable", badgeColor: .indigo),
                AccountRowModel("margin.lastMaintenance", L10n.AccountDetail.lastMaintenanceMargin, AppFormatter.compactMoney(account.lastMaintenanceMargin, currencyCode: currency), "clock.badge.checkmark", badgeColor: .indigo),
                AccountRowModel("margin.sma", L10n.AccountDetail.sma, AppFormatter.compactMoney(account.sma, currencyCode: currency), "waveform.path.ecg", badgeColor: .indigo)
            ]),
            AccountSectionModel(id: "trading", title: L10n.AccountDetail.trading, rows: [
                AccountRowModel("trading.shorting", L10n.AccountDetail.shortingEnabled, AccountDetailFormatter.boolean(account.shortingEnabled, locale: locale), "arrow.down.right.circle", badgeColor: .orange, valueTint: AccountDetailFormatter.booleanTint(account.shortingEnabled, positiveWhenTrue: true)),
                AccountRowModel("trading.pdt", L10n.AccountDetail.patternDayTrader, AccountDetailFormatter.boolean(account.patternDayTrader, locale: locale), "figure.run.circle", badgeColor: .orange, valueTint: AccountDetailFormatter.booleanTint(account.patternDayTrader, positiveWhenTrue: false)),
                AccountRowModel("trading.blocked", L10n.AccountDetail.tradingBlocked, AccountDetailFormatter.boolean(account.tradingBlocked, locale: locale), "lock.circle", badgeColor: .orange, valueTint: AccountDetailFormatter.booleanTint(account.tradingBlocked, positiveWhenTrue: false)),
                AccountRowModel("trading.transfersBlocked", L10n.AccountDetail.transfersBlocked, AccountDetailFormatter.boolean(account.transfersBlocked, locale: locale), "arrow.left.arrow.right.circle", badgeColor: .orange, valueTint: AccountDetailFormatter.booleanTint(account.transfersBlocked, positiveWhenTrue: false)),
                AccountRowModel("trading.accountBlocked", L10n.AccountDetail.accountBlocked, AccountDetailFormatter.boolean(account.accountBlocked, locale: locale), "xmark.octagon", badgeColor: .orange, valueTint: AccountDetailFormatter.booleanTint(account.accountBlocked, positiveWhenTrue: false)),
                AccountRowModel("trading.suspended", L10n.AccountDetail.tradeSuspendedByUser, AccountDetailFormatter.boolean(account.tradeSuspendedByUser, locale: locale), "pause.circle", badgeColor: .orange, valueTint: AccountDetailFormatter.booleanTint(account.tradeSuspendedByUser, positiveWhenTrue: false)),
                AccountRowModel("trading.optionsApproved", L10n.AccountDetail.optionsApprovedLevel, AccountDetailFormatter.integer(account.optionsApprovedLevel), "checkmark.seal", badgeColor: .orange),
                AccountRowModel("trading.optionsLevel", L10n.AccountDetail.optionsTradingLevel, AccountDetailFormatter.integer(account.optionsTradingLevel), "slider.horizontal.2.square", badgeColor: .orange),
                AccountRowModel("trading.cryptoTier", L10n.AccountDetail.cryptoTier, AccountDetailFormatter.integer(account.cryptoTier), "bitcoinsign.circle", badgeColor: .orange),
                AccountRowModel("trading.daytradeCount", L10n.AccountDetail.daytradeCount, AccountDetailFormatter.integer(account.daytradeCount), "number.circle", badgeColor: .orange)
            ]),
            AccountSectionModel(id: "fees", title: L10n.AccountDetail.feesAdjustments, rows: [
                AccountRowModel("fees.accrued", L10n.AccountDetail.accruedFees, AppFormatter.compactMoney(account.accruedFees, currencyCode: currency), "receipt", badgeColor: .purple),
                AccountRowModel("fees.pendingRegTaf", L10n.AccountDetail.pendingRegTAFFees, AppFormatter.compactMoney(account.pendingRegTAFFees, currencyCode: currency), "hourglass.circle", badgeColor: .purple),
                AccountRowModel("fees.intraday", L10n.AccountDetail.intradayAdjustments, AppFormatter.compactMoney(account.intradayAdjustments, currencyCode: currency), "arrow.triangle.2.circlepath", badgeColor: .purple)
            ])
        ]
    }
}

private struct AccountRowModel: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let badgeColor: Color
    let valueTint: Color
    let copyValue: String?

    init(
        _ id: String,
        _ title: LocalizedStringKey,
        _ value: String?,
        _ systemImage: String,
        badgeColor: Color,
        valueTint: Color = .secondary,
        copyValue: String? = nil
    ) {
        self.id = id
        self.title = title
        self.value = AccountDetailFormatter.text(value)
        self.systemImage = systemImage
        self.badgeColor = badgeColor
        self.valueTint = valueTint
        self.copyValue = copyValue
    }
}

private enum AccountDetailFormatter {
    static func clean(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    static func text(_ value: String?) -> String {
        clean(value) ?? AppFormatter.placeholder
    }

    static func boolean(_ value: Bool?, locale: Locale) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value
            ? L10n.string("account_detail.yes", locale: locale)
            : L10n.string("account_detail.no", locale: locale)
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
