import Observation
import SwiftUI

struct OptionTradeView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var store: OptionTradeStore
    @State private var confirmation: OptionTradeConfirmationSnapshot?

    init(
        contractSymbol: String,
        initialIntent: OrderPositionIntent = .buyToOpen,
        initialSnapshotModel: OptionDetailSnapshotModel? = nil
    ) {
        _store = State(initialValue: OptionTradeStore(
            contractSymbol: contractSymbol,
            initialIntent: initialIntent,
            initialSnapshotModel: initialSnapshotModel
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OptionTradeContractHeader(store: store)

                OptionTradeIntentSection(store: store)
                OptionTradePermissionSection(store: store)
                OptionTradeQuoteSection(store: store)
                OptionTradeInputSection(store: store)
                OptionTradeSummarySection(store: store, environment: app.environment)

                if let statusMessage {
                    OptionTradeStatusLine(message: statusMessage, isError: store.hasBlockingIssue)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.top, AppTheme.Spacing.pageTop)
            .padding(.bottom, 112)
        }
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationTitle("Option Order")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            OptionTradeBottomBar(
                title: store.reviewButtonTitle,
                tint: store.intent.side.tradeActionTint,
                isLoading: store.isSubmitting,
                isDimmed: !app.canUseAlpacaAPI || !store.validation.canSubmit
            ) {
                reviewOrder()
            }
        }
        .task {
            store.updateLocale(app.appLanguage.locale)
            await store.load(app: app, force: true)
        }
        .refreshable {
            await store.load(app: app, force: true)
        }
        .onChange(of: app.appLanguage) { _, language in
            store.updateLocale(language.locale)
        }
        .onChange(of: store.errorMessage) { _, message in
            showErrorMessage(message)
        }
        .sheet(item: $confirmation) { snapshot in
            OptionTradeConfirmationSheet(snapshot: snapshot) {
                await store.submit(app: app, snapshot: snapshot)
            } onSubmitted: { _ in
                dismiss()
            }
        }
    }

    private var statusMessage: String? {
        store.message ?? store.validation.errors.first
    }

    private func reviewOrder() {
        store.updateLocale(locale)

        guard app.canUseAlpacaAPI else {
            store.message = L10n.Trade.addCredentialsBeforeOrder(locale: locale)
            return
        }

        let validation = store.validation
        guard validation.canSubmit else {
            store.message = validation.errors.first
            return
        }

        confirmation = OptionTradeConfirmationSnapshot(store: store, environment: app.environment)
    }

    private func showErrorMessage(_ message: String?) {
        guard let message else {
            return
        }

        toastCenter.showErrorMessage(message)
    }
}

@MainActor
@Observable
final class OptionTradeStore {
    static let supportedIntents: [OrderPositionIntent] = [.buyToOpen, .sellToClose]
    static let contractMultiplier = Decimal(100)

    let contractSymbol: String
    let descriptor: OptionContractDescriptor
    var intent: OrderPositionIntent {
        didSet {
            applyIntentToDraft()
            message = nil
        }
    }
    var draft: OrderDraft {
        didSet { refreshDerivedState() }
    }
    private(set) var account: AlpacaAccount? {
        didSet { refreshDerivedState() }
    }
    private(set) var position: AlpacaPosition? {
        didSet { refreshDerivedState() }
    }
    private(set) var snapshot: AlpacaOptionSnapshot? {
        didSet { refreshDerivedState() }
    }
    private(set) var isLoading = false {
        didSet { refreshDerivedState() }
    }
    var isSubmitting = false
    var message: String?
    private(set) var errorMessage: String?
    private var initialSnapshotModel: OptionDetailSnapshotModel?
    private var locale = AppLocale.current
    private var estimatedNotionalSnapshot: Decimal?
    private var validationSnapshot: TradeValidationResult = .empty

    init(
        contractSymbol: String,
        initialIntent: OrderPositionIntent,
        initialSnapshotModel: OptionDetailSnapshotModel?
    ) {
        let normalizedSymbol = contractSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let resolvedIntent = Self.supportedIntents.contains(initialIntent) ? initialIntent : .buyToOpen
        self.contractSymbol = normalizedSymbol
        descriptor = OptionContractDescriptor(symbol: normalizedSymbol)
        intent = resolvedIntent
        self.initialSnapshotModel = initialSnapshotModel

        var draft = OrderDraft()
        draft.symbol = normalizedSymbol
        draft.orderType = .limit
        draft.timeInForce = .day
        draft.side = resolvedIntent.side
        draft.positionIntent = resolvedIntent
        self.draft = draft
        refreshDerivedState()
        fillDefaultLimitPriceIfNeeded()
    }

    func updateLocale(_ locale: Locale) {
        let resolvedLocale = AppLocale.resolvedLocale(for: locale)
        guard self.locale.identifier != resolvedLocale.identifier else {
            return
        }

        self.locale = resolvedLocale
        refreshDerivedState()
    }

    var snapshotModel: OptionDetailSnapshotModel {
        if let snapshot {
            return OptionDetailSnapshotModel(descriptor: descriptor, snapshot: snapshot)
        }

        if let initialSnapshotModel {
            return initialSnapshotModel
        }

        return OptionDetailSnapshotModel(descriptor: descriptor, snapshot: nil)
    }

    var bidPrice: Decimal? {
        decimal(snapshot?.latestQuote?.bidPrice) ?? decimal(initialSnapshotModel?.bidPrice)
    }

    var askPrice: Decimal? {
        decimal(snapshot?.latestQuote?.askPrice) ?? decimal(initialSnapshotModel?.askPrice)
    }

    var midPrice: Decimal? {
        decimal(snapshot?.latestQuote?.midpoint) ?? decimal(initialSnapshotModel?.midPrice)
    }

    var lastPrice: Decimal? {
        decimal(snapshot?.latestTrade?.price)
            ?? decimal(initialSnapshotModel?.lastPrice)
    }

    var bidSize: Double? {
        snapshot?.latestQuote?.bidSize ?? initialSnapshotModel?.bidSize
    }

    var askSize: Double? {
        snapshot?.latestQuote?.askSize ?? initialSnapshotModel?.askSize
    }

    var spread: Double? {
        snapshot?.latestQuote?.spread ?? initialSnapshotModel?.spread
    }

    var quoteTimeText: String {
        let timestamp = snapshot?.latestQuote?.timestamp
            ?? snapshot?.latestTrade?.timestamp
            ?? initialSnapshotModel?.quoteTime
            ?? initialSnapshotModel?.lastTradeTime
        return OptionTradeTimeFormatter.shortTime(timestamp) ?? AppFormatter.placeholder
    }

    var currencyCode: String {
        account?.currency ?? "USD"
    }

    var optionsTradingLevelText: String {
        guard let level = account?.optionsTradingLevel else {
            return AppFormatter.placeholder
        }
        return String(level)
    }

    var optionsApprovedLevelText: String {
        guard let level = account?.optionsApprovedLevel else {
            return AppFormatter.placeholder
        }
        return String(level)
    }

    var optionsTradingLevel: Int {
        account?.optionsTradingLevel ?? 0
    }

    var optionsApprovedLevel: Int {
        account?.optionsApprovedLevel ?? 0
    }

    var optionsBuyingPower: Decimal? {
        NumberParser.decimal(from: account?.optionsBuyingPower)
            ?? NumberParser.decimal(from: account?.buyingPower)
    }

    var positionQuantity: Decimal {
        NumberParser.decimal(from: position?.quantity) ?? 0
    }

    var closableContracts: Decimal {
        max(NumberParser.decimal(from: position?.quantityAvailable) ?? positionQuantity, 0)
    }

    var requestedContracts: Int? {
        let quantity = OrderDraft.normalizedSizeText(draft.quantityText)
        guard quantity.range(of: #"^[1-9]\d*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Int(quantity)
    }

    var limitPrice: Decimal? {
        NumberParser.decimal(from: NumberText.trimTrailingZeros(draft.limitPriceText))
    }

    var estimatedExecutionPrice: Decimal? {
        limitPrice
    }

    var estimatedNotional: Decimal? {
        estimatedNotionalSnapshot
    }

    var validation: TradeValidationResult {
        validationSnapshot
    }

    var hasBlockingIssue: Bool {
        !validation.canSubmit
    }

    var hasPermissionIssue: Bool {
        guard account != nil else {
            return !isLoading
        }

        return permissionIssue != nil
    }

    var reviewButtonTitle: String {
        if isSubmitting {
            return L10n.Trade.simpleSubmitting(locale: locale)
        }

        return "Review \(intent.shortTitle)"
    }

    var permissionStatusText: String {
        if account == nil {
            return isLoading ? "Loading account permissions..." : "Account permissions are unavailable."
        }

        if let issue = permissionIssue {
            return issue
        }

        return "\(intent.title) is available for this account."
    }

    var estimatedNotionalTitle: String {
        intent.side == .buy ? "Estimated Debit" : "Estimated Credit"
    }

    var priceFillModels: [OptionTradePriceFillModel] {
        [
            OptionTradePriceFillModel(source: .bid, price: bidPrice),
            OptionTradePriceFillModel(source: .mid, price: midPrice),
            OptionTradePriceFillModel(source: .ask, price: askPrice),
            OptionTradePriceFillModel(source: .last, price: lastPrice)
        ].filter { $0.price != nil }
    }

    func load(app: AppModel, force: Bool = false) async {
        updateLocale(app.appLanguage.locale)
        guard !contractSymbol.isEmpty else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        var firstError: Error?

        do {
            account = try await app.fetchAccountDetails()
        } catch {
            firstError = firstError ?? error
        }

        do {
            position = try await app.fetchOpenPosition(symbol: contractSymbol)
        } catch {
            firstError = firstError ?? error
        }

        do {
            if let loadedSnapshot = try await app.fetchOptionSnapshot(symbol: contractSymbol, forceReload: force) {
                snapshot = loadedSnapshot
                initialSnapshotModel = nil
                fillDefaultLimitPriceIfNeeded()
            }
        } catch {
            firstError = firstError ?? error
        }

        if let firstError {
            errorMessage = APIErrorDisplayMessage.message(for: firstError, locale: locale)
        } else {
            errorMessage = nil
            message = nil
        }
    }

    func selectPrice(_ source: OptionTradePriceFillSource) {
        guard let price = price(for: source) else {
            return
        }

        draft.limitPriceText = Self.apiPriceNumber(price)
        message = nil
    }

    func submit(app: AppModel, snapshot: OptionTradeConfirmationSnapshot) async -> TradeSubmitResult {
        updateLocale(app.appLanguage.locale)

        guard !isSubmitting else {
            return .failure(L10n.Trade.simpleSubmitting(locale: locale))
        }

        if draft != snapshot.order {
            draft = snapshot.order
        }

        guard validation.canSubmit else {
            let errorMessage = validation.errors.first ?? L10n.Trade.simpleOrderUnavailable(locale: locale)
            message = errorMessage
            return .failure(errorMessage)
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let result = await app.submit(snapshot.order, clientOrderID: snapshot.clientOrderID)
        switch result {
        case .success(let order):
            await load(app: app, force: true)
            message = L10n.Trade.orderSubmitted(locale: locale)
            return .success(order)
        case .failure(let errorMessage):
            message = errorMessage
            return .failure(errorMessage)
        }
    }

    private var permissionIssue: String? {
        if account?.tradingBlocked == true || account?.accountBlocked == true || account?.tradeSuspendedByUser == true {
            return L10n.Trade.accountTradingBlocked(locale: locale)
        }

        guard optionsTradingLevel > 0 else {
            return "Options trading is disabled for this account."
        }

        switch intent {
        case .buyToOpen:
            return optionsTradingLevel >= 2 ? nil : "Buying calls and puts requires options level 2."
        case .sellToClose:
            if optionsTradingLevel < 1 {
                return "Closing option positions requires options trading access."
            }
            return closableContracts > 0 ? nil : "No open contracts are available to close."
        case .buyToClose, .sellToOpen:
            return "\(intent.title) is not available in this screen."
        }
    }

    private func refreshDerivedState() {
        estimatedNotionalSnapshot = calculateEstimatedNotional()
        validationSnapshot = makeValidation()
    }

    private func calculateEstimatedNotional() -> Decimal? {
        guard let requestedContracts, let limitPrice else {
            return nil
        }

        return Decimal(requestedContracts) * limitPrice * Self.contractMultiplier
    }

    private func makeValidation() -> TradeValidationResult {
        var issues: [TradeValidationIssue] = []

        do {
            _ = try draft.requestPayload()
        } catch let error as OrderDraftError {
            issues.append(TradeValidationIssue(
                kind: Self.issueKind(for: error),
                message: error.errorDescription(locale: locale)
            ))
        } catch {
            issues.append(.generic(error.localizedDescription))
        }

        if requestedContracts == nil {
            let normalizedQuantity = OrderDraft.normalizedSizeText(draft.quantityText)
            if normalizedQuantity.isEmpty {
                issues.append(.generic("Enter the number of option contracts."))
            } else {
                issues.append(.generic("Contracts must be a positive whole number."))
            }
        }

        if draft.orderType != .limit {
            issues.append(.generic("Options orders on this screen must be limit orders."))
        }

        if draft.timeInForce != .day {
            issues.append(.generic("Options orders support DAY time in force."))
        }

        if draft.positionIntent != intent || draft.side != intent.side {
            issues.append(.generic("Order intent does not match the selected action."))
        }

        if account == nil, !isLoading {
            issues.append(.generic(L10n.Trade.contextNotLoaded(locale: locale)))
        }

        if let permissionIssue {
            issues.append(.generic(permissionIssue))
        }

        if intent == .sellToClose,
           let requestedContracts,
           Decimal(requestedContracts) > closableContracts {
            issues.append(TradeValidationIssue(
                kind: .sellExceedsPosition,
                message: "Sell to close quantity exceeds available contracts."
            ))
        }

        if intent == .buyToOpen,
           let estimatedNotional,
           let optionsBuyingPower,
           estimatedNotional > optionsBuyingPower {
            issues.append(TradeValidationIssue(
                kind: .buyExceedsBuyingPower,
                message: L10n.Trade.buyExceedsBuyingPower(locale: locale)
            ))
        }

        return TradeValidationResult(issues: Self.unique(issues), warnings: [])
    }

    private func applyIntentToDraft() {
        draft.side = intent.side
        draft.positionIntent = intent
        draft.orderType = .limit
        draft.timeInForce = .day
        draft.notionalText = ""
        draft.extendedHours = false
        fillDefaultLimitPriceIfNeeded()
        refreshDerivedState()
    }

    private func fillDefaultLimitPriceIfNeeded() {
        guard NumberText.trimTrailingZeros(draft.limitPriceText).isEmpty,
              let price = defaultLimitReferencePrice else {
            return
        }

        draft.limitPriceText = Self.apiPriceNumber(price)
    }

    private var defaultLimitReferencePrice: Decimal? {
        if let midPrice, midPrice > 0 {
            return midPrice
        }

        switch intent.side {
        case .buy:
            return askPrice ?? lastPrice ?? bidPrice
        case .sell:
            return bidPrice ?? lastPrice ?? askPrice
        }
    }

    private func price(for source: OptionTradePriceFillSource) -> Decimal? {
        switch source {
        case .bid:
            bidPrice
        case .mid:
            midPrice
        case .ask:
            askPrice
        case .last:
            lastPrice
        }
    }

    private func decimal(_ value: Double?) -> Decimal? {
        guard let value, value.isFinite else {
            return nil
        }

        return Decimal(value)
    }

    private static func apiPriceNumber(_ value: Decimal) -> String {
        apiNumber(value, scale: value >= 1 ? 2 : 4)
    }

    private static func apiNumber(_ value: Decimal, scale: Int) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, scale, .plain)
        return NumberText.trimTrailingZeros(NSDecimalNumber(decimal: rounded).stringValue)
    }

    private static func unique(_ issues: [TradeValidationIssue]) -> [TradeValidationIssue] {
        var seen = Set<String>()
        return issues.filter { issue in
            seen.insert(issue.message).inserted
        }
    }

    private static func issueKind(for error: OrderDraftError) -> TradeValidationIssueKind {
        switch error {
        case .missingSize:
            .missingInput
        default:
            .generic
        }
    }
}

enum OptionTradePriceFillSource: String, Identifiable {
    case bid
    case mid
    case ask
    case last

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bid:
            "Bid"
        case .mid:
            "Mid"
        case .ask:
            "Ask"
        case .last:
            "Last"
        }
    }
}

struct OptionTradePriceFillModel: Identifiable {
    let source: OptionTradePriceFillSource
    let price: Decimal?

    var id: OptionTradePriceFillSource { source }
    var title: String { source.title }
    var priceText: String { OptionTradeFormat.optionPrice(price) }
}

struct OptionTradeConfirmationSnapshot: Identifiable {
    let id = UUID()
    let clientOrderID: String
    let order: OrderDraft
    let descriptor: OptionContractDescriptor
    let intent: OrderPositionIntent
    let estimatedNotional: Decimal?
    let estimatedExecutionPrice: Decimal?
    let currencyCode: String
    let environment: TradeEnvironment
    let optionsTradingLevel: Int
    let optionsApprovedLevel: Int
    let positionQuantity: Decimal

    @MainActor
    init(store: OptionTradeStore, environment: TradeEnvironment) {
        clientOrderID = "vicu-\(UUID().uuidString.lowercased())"
        order = store.draft
        descriptor = store.descriptor
        intent = store.intent
        estimatedNotional = store.estimatedNotional
        estimatedExecutionPrice = store.estimatedExecutionPrice
        currencyCode = store.currencyCode
        self.environment = environment
        optionsTradingLevel = store.optionsTradingLevel
        optionsApprovedLevel = store.optionsApprovedLevel
        positionQuantity = store.positionQuantity
    }
}

private struct OptionTradeContractHeader: View {
    let store: OptionTradeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.descriptor.symbol)
                        .font(.title3.monospaced().weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Text("\(store.descriptor.expirationText)  \(store.descriptor.strikeText)")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(store.descriptor.typeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.snapshotModel.typeTint)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(store.snapshotModel.typeTint.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Limit Price")
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(OptionTradeFormat.optionPrice(store.limitPrice))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Label("Delayed", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            }
        }
        .padding(16)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .redacted(reason: store.isLoading && store.snapshotModel.displayPrice == nil ? .placeholder : [])
    }
}

private struct OptionTradeIntentSection: View {
    @Bindable var store: OptionTradeStore

    var body: some View {
        AssetDetailSection(title: "Action") {
            Picker("Action", selection: $store.intent) {
                ForEach(OptionTradeStore.supportedIntents) { intent in
                    Text(intent.shortTitle).tag(intent)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.isSubmitting)
        }
    }
}

private struct OptionTradePermissionSection: View {
    let store: OptionTradeStore

    var body: some View {
        AssetDetailSection(title: "Permissions") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    OptionTradeSummaryTile(
                        title: "Trading Level",
                        value: store.optionsTradingLevelText,
                        alignment: .leading
                    )
                    OptionTradeSummaryTile(
                        title: "Approved Level",
                        value: store.optionsApprovedLevelText,
                        alignment: .leading
                    )
                }

                Label(store.permissionStatusText, systemImage: store.hasPermissionIssue ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(AppTypography.detail.weight(.semibold))
                    .foregroundStyle(store.hasPermissionIssue ? AppTheme.ColorToken.warning : AppTheme.ColorToken.positive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct OptionTradeQuoteSection: View {
    let store: OptionTradeStore

    var body: some View {
        AssetDetailSection(title: "Quote") {
            VStack(spacing: 12) {
                AssetLevelOneQuoteContent(
                    bidPrice: OptionTradeFormat.double(store.bidPrice),
                    askPrice: OptionTradeFormat.double(store.askPrice),
                    bidSize: store.bidSize,
                    askSize: store.askSize,
                    spread: store.spread,
                    sizeUnit: "contracts",
                    priceFormatter: OptionValueText.money
                )

                HStack {
                    Text("Indicative quote")
                    Spacer()
                    Text(store.quoteTimeText)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct OptionTradeInputSection: View {
    @Bindable var store: OptionTradeStore

    var body: some View {
        AssetDetailSection(title: "Limit Order") {
            VStack(spacing: 0) {
                OptionTradeInputRow(
                    title: "Contracts",
                    placeholder: "0",
                    text: $store.draft.quantityText,
                    keyboard: .numberPad
                )

                Divider()

                OptionTradeInputRow(
                    title: "Limit Price",
                    placeholder: "0.00",
                    prefix: "$",
                    text: $store.draft.limitPriceText,
                    keyboard: .decimalPad
                )

                if !store.priceFillModels.isEmpty {
                    Divider()

                    LazyVGrid(columns: AssetDetailGrid.twoColumns, spacing: 10) {
                        ForEach(store.priceFillModels) { item in
                            Button {
                                store.selectPrice(item.source)
                            } label: {
                                HStack {
                                    Text(item.title)
                                    Spacer(minLength: 8)
                                    Text(item.priceText)
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isSubmitting)
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .padding(14)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct OptionTradeInputRow: View {
    let title: String
    let placeholder: String
    var prefix: String?
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(AppTypography.rowTitle.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            HStack(spacing: 3) {
                if let prefix, !text.isEmpty {
                    Text(prefix)
                        .foregroundStyle(.secondary)
                }

                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 120)
            }
            .frame(maxWidth: 190, alignment: .trailing)
        }
        .padding(.vertical, 14)
    }
}

private struct OptionTradeSummarySection: View {
    @Environment(\.locale) private var locale

    let store: OptionTradeStore
    let environment: TradeEnvironment

    var body: some View {
        AssetDetailSection(title: "Summary") {
            LazyVGrid(columns: AssetDetailGrid.twoColumns, spacing: 12) {
                OptionTradeSummaryTile(
                    title: store.estimatedNotionalTitle,
                    value: AppFormatter.money(store.estimatedNotional, currencyCode: store.currencyCode)
                )
                OptionTradeSummaryTile(
                    title: "Buying Power",
                    value: AppFormatter.money(store.optionsBuyingPower, currencyCode: store.currencyCode)
                )
                OptionTradeSummaryTile(
                    title: "Position",
                    value: OptionTradeFormat.contracts(store.positionQuantity)
                )
                OptionTradeSummaryTile(
                    title: "Available",
                    value: OptionTradeFormat.contracts(store.closableContracts)
                )
                OptionTradeSummaryTile(
                    title: "Order Type",
                    value: "Limit"
                )
                OptionTradeSummaryTile(
                    title: "Time in Force",
                    value: "DAY"
                )
                OptionTradeSummaryTile(
                    title: "Multiplier",
                    value: "100"
                )
                OptionTradeSummaryTile(
                    title: "Environment",
                    value: environment.titleText(locale: locale)
                )
            }
        }
    }
}

private struct OptionTradeSummaryTile: View {
    enum AlignmentMode {
        case leading
        case trailing
    }

    let title: String
    let value: String
    var alignment: AlignmentMode = .leading

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 5) {
            Text(title)
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(AppTypography.rowValue.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .padding(12)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var horizontalAlignment: HorizontalAlignment {
        alignment == .leading ? .leading : .trailing
    }

    private var frameAlignment: Alignment {
        alignment == .leading ? .leading : .trailing
    }
}

private struct OptionTradeStatusLine: View {
    let message: String
    let isError: Bool

    var body: some View {
        Label(message, systemImage: isError ? "exclamationmark.circle.fill" : "info.circle.fill")
            .font(AppTypography.detail.weight(.semibold))
            .foregroundStyle(isError ? AppTheme.ColorToken.warning : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct OptionTradeBottomBar: View {
    let title: String
    let tint: Color
    let isLoading: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(buttonFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var buttonFill: Color {
        isDimmed ? Color(.tertiaryLabel) : tint
    }
}

private struct OptionTradeConfirmationSheet: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let snapshot: OptionTradeConfirmationSnapshot
    let onSubmit: () async -> TradeSubmitResult
    let onSubmitted: (AlpacaOrder) -> Void

    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 58, height: 5)
                .padding(.top, 10)

            HStack {
                Button(L10n.Common.cancelText(locale: locale)) {
                    dismiss()
                }
                .font(AppTypography.control)
                .foregroundStyle(.secondary)
                .disabled(isSubmitting)

                Spacer(minLength: 12)

                Text("Review Option Order")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Color.clear
                    .frame(width: 52, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                identityCard
                detailCard
                confirmationMessage
                actionButton
            }
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.top, 8)
            .padding(.bottom, AppTheme.Spacing.pageBottom)
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.descriptor.symbol)
                .font(.title3.monospaced().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            HStack(spacing: 8) {
                Text(snapshot.intent.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.intent.side.tradeActionTint)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(snapshot.intent.side.tradeActionTint.opacity(0.12), in: Capsule())

                Text("\(snapshot.descriptor.expirationText)  \(snapshot.descriptor.strikeText)  \(snapshot.descriptor.typeText)")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            ForEach(detailItems.indices, id: \.self) { index in
                OptionTradeConfirmationInfoRow(item: detailItems[index])

                if index < detailItems.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var confirmationMessage: some View {
        Text("This \(snapshot.environment.titleText(locale: locale)) order will be submitted as a DAY limit option order.")
            .font(AppTypography.detail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                }

                Text(isSubmitting ? L10n.Trade.simpleSubmitting(locale: locale) : snapshot.intent.shortTitle)
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(snapshot.intent.side.tradeActionTint, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .padding(.top, 2)
    }

    private var detailItems: [OptionTradeConfirmationInfoItem] {
        [
            OptionTradeConfirmationInfoItem(
                title: "Action",
                value: snapshot.intent.title,
                tint: snapshot.intent.side.tradeActionTint
            ),
            OptionTradeConfirmationInfoItem(
                title: "Contracts",
                value: OrderDraft.normalizedSizeText(snapshot.order.quantityText)
            ),
            OptionTradeConfirmationInfoItem(
                title: "Limit Price",
                value: OptionTradeFormat.optionPrice(snapshot.estimatedExecutionPrice)
            ),
            OptionTradeConfirmationInfoItem(
                title: snapshot.intent.side == .buy ? "Estimated Debit" : "Estimated Credit",
                value: AppFormatter.money(snapshot.estimatedNotional, currencyCode: snapshot.currencyCode)
            ),
            OptionTradeConfirmationInfoItem(
                title: "Position Intent",
                value: snapshot.order.positionIntent?.rawValue ?? AppFormatter.placeholder
            ),
            OptionTradeConfirmationInfoItem(
                title: "Time in Force",
                value: snapshot.order.timeInForce.title
            ),
            OptionTradeConfirmationInfoItem(
                title: "Option Level",
                value: "\(snapshot.optionsTradingLevel) / \(snapshot.optionsApprovedLevel)"
            ),
            OptionTradeConfirmationInfoItem(
                title: "Environment",
                value: snapshot.environment.titleText(locale: locale)
            )
        ]
    }

    private func submit() async {
        guard !isSubmitting else {
            return
        }

        isSubmitting = true
        let result = await onSubmit()
        finishSubmission(result)
    }

    private func finishSubmission(_ result: TradeSubmitResult) {
        switch result {
        case .success(let submittedOrder):
            dismiss()
            showToastAfterSheetDismissal(.success(L10n.Trade.orderSubmitted(locale: locale)))
            onSubmitted(submittedOrder)
        case .failure(let message):
            isSubmitting = false
            dismiss()
            showToastAfterSheetDismissal(.error(message))
        }
    }

    private func showToastAfterSheetDismissal(_ feedback: OptionTradeConfirmationFeedback) {
        Task { @MainActor [toastCenter] in
            try? await Task.sleep(for: .milliseconds(320))

            switch feedback {
            case .success(let message):
                toastCenter.show(message)
            case .error(let message):
                toastCenter.showErrorMessage(message)
            }
        }
    }
}

private enum OptionTradeConfirmationFeedback {
    case success(String)
    case error(String)
}

private struct OptionTradeConfirmationInfoItem {
    let title: String
    let value: String
    var tint: Color?
}

private struct OptionTradeConfirmationInfoRow: View {
    let item: OptionTradeConfirmationInfoItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(item.title)
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(item.value)
                .font(AppTypography.rowValue)
                .foregroundStyle(item.tint ?? .primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(.vertical, 13)
    }
}

private enum OptionTradeFormat {
    static func optionPrice(_ value: Decimal?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return AppFormatter.money(value, fractionLength: optionPriceFractionLength(value))
    }

    static func contracts(_ value: Decimal) -> String {
        let normalized = NumberText.trimTrailingZeros(NSDecimalNumber(decimal: value).stringValue)
        return "\(normalized) ct"
    }

    static func double(_ value: Decimal?) -> Double? {
        guard let value else {
            return nil
        }

        return NSDecimalNumber(decimal: value).doubleValue
    }

    private static func optionPriceFractionLength(_ value: Decimal) -> Int {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        return OptionValueText.moneyFractionLength(for: doubleValue)
    }
}

private enum OptionTradeTimeFormatter {
    static func shortTime(_ text: String?) -> String? {
        guard let date = AlpacaDateParser.date(text) else {
            return nil
        }

        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}
