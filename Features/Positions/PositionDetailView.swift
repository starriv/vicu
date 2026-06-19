import SwiftUI

struct PositionDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @State private var position: AlpacaPosition?
    @State private var isLoading = false
    @State private var positionSharePayload: AssetPositionSharePayload?
    @State private var closeConfirmation: PositionCloseConfirmationSnapshot?

    private let symbol: String

    init(position: AlpacaPosition) {
        self.symbol = PositionDisplay.normalizedSymbol(position.symbol)
        _position = State(initialValue: position)
    }

    init(symbol: String) {
        self.symbol = PositionDisplay.normalizedSymbol(symbol)
    }

    var body: some View {
        BasicLayout(L10n.PositionDetail.title, style: .scroll(spacing: 20)) {
            content
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if !displaySymbol.isEmpty {
                if let position {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            positionSharePayload = sharePayload(for: position)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(L10n.PositionDetail.share)
                    }

                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AssetDetailView(symbol: displaySymbol)
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .accessibilityLabel(L10n.PositionDetail.viewAsset)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 18)
                    .padding(.trailing, AppTheme.Spacing.pageHorizontal)
            }
        }
        .refreshable {
            await loadPosition()
        }
        .task(id: symbol) {
            await loadPosition()
        }
        .sheet(item: $positionSharePayload) { payload in
            AssetPositionShareSheet(payload: payload)
                .presentationDetents([.height(680)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $closeConfirmation) { snapshot in
            PositionCloseConfirmationSheet(snapshot: snapshot) {
                try await app.closePosition(snapshot.position)
            } onClosed: { _ in
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && position == nil {
            ProgressView(L10n.PositionDetail.loading)
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if let position {
            PositionOverviewPanel(position: position, title: L10n.PositionDetail.overview)

            ForEach(PositionDetailSectionModel.sections(for: position, locale: app.appLanguage.locale)) { section in
                PositionDetailSection(section: section)
            }

            PositionCloseActionButton {
                presentCloseConfirmation(for: position)
            }
        } else {
            ContentUnavailableView(
                L10n.PositionDetail.notFound,
                systemImage: AppIcon.Position.empty,
                description: Text(L10n.PositionDetail.notFoundDescription(locale: app.appLanguage.locale))
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private var displaySymbol: String {
        PositionDisplay.normalizedSymbol(position?.symbol ?? symbol)
    }

    private func sharePayload(for position: AlpacaPosition) -> AssetPositionSharePayload {
        let symbol = PositionDisplay.normalizedSymbol(position.symbol)
        let exchange = PositionDisplay.text(position.exchange)
        let displayName = AppFormatter.displayText(
            app.favoriteMarketAsset(for: symbol)?.name,
            placeholder: symbol
        )

        return AssetPositionSharePayload(
            symbol: symbol,
            displayName: displayName,
            exchange: exchange,
            position: position
        )
    }

    private func presentCloseConfirmation(for position: AlpacaPosition) {
        guard app.hasCredentials else {
            toastCenter.showErrorMessage(L10n.Credentials.apiKeyRequired(locale: app.appLanguage.locale))
            return
        }

        closeConfirmation = PositionCloseConfirmationSnapshot(
            position: position
        )
    }

    private func loadPosition() async {
        guard app.hasCredentials else {
            toastCenter.showErrorMessage(L10n.Credentials.apiKeyRequired(locale: app.appLanguage.locale))
            return
        }

        guard !symbol.isEmpty else {
            position = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetchedPosition = try await app.fetchOpenPosition(symbol: symbol)
            try Task.checkCancellation()
            position = fetchedPosition
        } catch where error.isPositionDetailCancellation {
            return
        } catch {
            toastCenter.showError(error, locale: app.appLanguage.locale)
        }
    }
}

private struct PositionCloseConfirmationSnapshot: Identifiable {
    let id = UUID()
    let position: AlpacaPosition

    var symbol: String {
        PositionDisplay.normalizedSymbol(position.symbol)
    }
}

private struct PositionCloseActionButton: View {
    @Environment(\.locale) private var locale

    let action: () -> Void

    var body: some View {
        barContent
            .padding(.top, 2)
    }

    @ViewBuilder
    private var barContent: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                closeButton(usesGlass: true)
            }
        } else {
            closeButton(usesGlass: false)
        }
    }

    @ViewBuilder
    private func closeButton(usesGlass: Bool) -> some View {
        let tint = AppTheme.ColorToken.negative
        let button = Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.headline.weight(.semibold))

                Text(L10n.PositionDetail.closeAction(locale: locale))
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.PositionDetail.closeAction(locale: locale))

        if usesGlass, #available(iOS 26.0, *) {
            button
                .glassEffect(.regular.tint(tint.opacity(0.22)).interactive(), in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(tint.opacity(0.34), lineWidth: 0.75)
                }
        } else {
            button
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(tint.opacity(0.30), lineWidth: 0.75)
                }
                .shadow(color: tint.opacity(0.10), radius: 16, y: 6)
        }
    }
}

private struct PositionCloseConfirmationSheet: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let snapshot: PositionCloseConfirmationSnapshot
    let onConfirm: () async throws -> AlpacaOrder
    let onClosed: (AlpacaOrder) -> Void

    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                summaryCard
                warningMessage
                PositionCloseConfirmButton(
                    title: L10n.PositionDetail.closeConfirmAction(locale: locale),
                    submittingTitle: L10n.Trade.simpleSubmitting(locale: locale),
                    isSubmitting: isSubmitting
                ) {
                    await submit()
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .presentationDetents([.height(350)])
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

                Text(L10n.PositionDetail.closeSheetTitle(locale: locale))
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

    private var summaryCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.symbol)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    Text(PositionDisplay.sideText(snapshot.position.side, locale: locale))
                        .font(AppTypography.detail.weight(.semibold))
                        .foregroundStyle(PositionDisplay.sideTint(snapshot.position.side))
                }

                Spacer(minLength: 12)

                AppPriceText(
                    snapshot.position.marketValue,
                    font: .title3.monospacedDigit().weight(.semibold),
                    minimumScaleFactor: 0.76,
                    notation: .compact
                )
                .foregroundStyle(.primary)
            }
            .padding(.vertical, 14)

            Divider()

            PositionCloseSummaryRow(
                title: L10n.PositionDetail.quantity,
                value: PositionDisplay.quantityText(
                    snapshot.position.quantity,
                    assetClass: snapshot.position.assetClass,
                    symbol: snapshot.position.symbol,
                    locale: locale
                )
            )
        }
        .padding(.horizontal, 18)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
    }

    private var warningMessage: some View {
        Text(L10n.PositionDetail.closeSheetMessage(symbol: snapshot.symbol, locale: locale))
            .font(AppTypography.detail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private func submit() async {
        guard !isSubmitting else {
            return
        }

        isSubmitting = true

        do {
            let order = try await onConfirm()
            dismiss()
            showSuccessToastAfterDismissal()
            onClosed(order)
        } catch {
            isSubmitting = false
            toastCenter.showError(error, locale: locale)
        }
    }

    private func showSuccessToastAfterDismissal() {
        Task { @MainActor [toastCenter, symbol = snapshot.symbol, locale = locale] in
            try? await Task.sleep(for: .milliseconds(320))
            toastCenter.show(L10n.PositionDetail.closeSubmitted(symbol: symbol, locale: locale))
        }
    }
}

private struct PositionCloseSummaryRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.vertical, 13)
    }
}

private struct PositionCloseConfirmButton: View {
    let title: String
    let submittingTitle: String
    let isSubmitting: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                Text(title)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .opacity(isSubmitting ? 0 : 1)

                if isSubmitting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)

                        Text(submittingTitle)
                            .font(.headline.weight(.bold))
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(AppTheme.ColorToken.negative, in: Capsule())
        .disabled(isSubmitting)
        .accessibilityLabel(isSubmitting ? submittingTitle : title)
    }
}

struct PositionOverviewPanel: View {
    @Environment(\.locale) private var locale

    let position: AlpacaPosition
    let title: LocalizedStringKey
    let onShare: (() -> Void)?

    init(
        position: AlpacaPosition,
        title: LocalizedStringKey = L10n.PositionDetail.yourPosition,
        onShare: (() -> Void)? = nil
    ) {
        self.position = position
        self.title = title
        self.onShare = onShare
    }

    private var totalPL: Double? {
        NumberParser.double(from: position.unrealizedPL)
    }

    private var totalPLPercent: Double? {
        NumberParser.double(from: position.unrealizedPLPC)
    }

    private var intradayPL: Double? {
        NumberParser.double(from: position.unrealizedIntradayPL)
    }

    private var intradayPLPercent: Double? {
        NumberParser.double(from: position.unrealizedIntradayPLPC)
    }

    private var totalTint: Color {
        PositionDisplay.tint(for: totalPL)
    }

    private var intradayTint: Color {
        PositionDisplay.tint(for: intradayPL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Spacer()

                if let onShare {
                    PositionShareIconButton(action: onShare)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(PositionDisplay.sideText(position.side, locale: locale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(PositionDisplay.quantityText(
                            position.quantity,
                            assetClass: position.assetClass,
                            symbol: position.symbol,
                            locale: locale
                        ))
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(L10n.PositionDetail.marketValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        AppPriceText(
                            position.marketValue,
                            font: .title3.monospacedDigit().weight(.semibold),
                            minimumScaleFactor: 0.76,
                            notation: .compact
                        )
                        .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 10) {
                    PositionChangeTile(
                        title: L10n.PositionDetail.today,
                        value: intradayPL,
                        percent: AppFormatter.signedPercent(intradayPLPercent),
                        tint: intradayTint
                    )

                    PositionChangeTile(
                        title: L10n.PositionDetail.unrealizedPL,
                        value: totalPL,
                        percent: AppFormatter.signedPercent(totalPLPercent),
                        tint: totalTint
                    )
                }

                Divider()
                    .opacity(0.45)

                HStack(spacing: 10) {
                    PositionMiniMetric(
                        title: L10n.PositionDetail.averageEntryPriceShort,
                        value: AppFormatter.compactMoney(position.averageEntryPrice)
                    )
                    PositionMiniMetric(
                        title: L10n.PositionDetail.costBasisShort,
                        value: AppFormatter.compactMoney(position.costBasis)
                    )
                    PositionMiniMetric(
                        title: L10n.PositionDetail.availableShort,
                        value: PositionDisplay.quantityText(
                            position.quantityAvailable,
                            assetClass: position.assetClass,
                            symbol: position.symbol,
                            locale: locale
                        )
                    )
                }
            }
            .padding(16)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PositionShareIconButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44, alignment: .center)
                .offset(y: -1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(PositionShareGlassCircleModifier())
        .accessibilityLabel(L10n.PositionDetail.share)
    }
}

private struct PositionShareGlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.10)).interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color(.separator).opacity(0.16))
                }
        }
    }
}

private struct PositionDetailSection: View {
    let section: PositionDetailSectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(section.rows) { row in
                    PositionDetailRow(row: row)

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

private struct PositionDetailRow: View {
    let row: PositionDetailRowModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: row.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(row.tint)
                .frame(width: 28)

            Text(row.title)
                .font(AppTypography.rowTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            valueContent
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var valueContent: some View {
        if let copyValue = row.copyValue, PositionDisplay.clean(copyValue) != nil {
            AppCopyableIdentifier(
                value: copyValue,
                displayValue: row.value,
                accessibilityLabel: row.title
            )
        } else {
            Text(row.value)
                .font(AppTypography.detail.monospacedDigit())
                .foregroundStyle(row.value == AppFormatter.placeholder ? Color.secondary : row.valueTint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
    }
}

private struct PositionChangeTile: View {
    let title: LocalizedStringKey
    let value: Double?
    let percent: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            AppPriceText(
                value,
                font: .headline.monospacedDigit().weight(.semibold),
                minimumScaleFactor: 0.72,
                isSigned: true,
                notation: .compact
            )
            .foregroundStyle(tint)

            Text(percent)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PositionMiniMetric: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PositionDetailSectionModel: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let rows: [PositionDetailRowModel]

    static func sections(for position: AlpacaPosition, locale: Locale) -> [PositionDetailSectionModel] {
        [
            PositionDetailSectionModel(id: "holdings", title: L10n.PositionDetail.holdings, rows: [
                PositionDetailRowModel(
                    id: "side",
                    title: L10n.PositionDetail.side,
                    value: PositionDisplay.sideText(position.side, locale: locale),
                    systemImage: position.side?.lowercased() == "short" ? "arrow.down.right.circle" : "arrow.up.right.circle",
                    valueTint: PositionDisplay.sideTint(position.side)
                ),
                PositionDetailRowModel(
                    id: "quantity",
                    title: L10n.PositionDetail.quantity,
                    value: PositionDisplay.quantityText(
                        position.quantity,
                        assetClass: position.assetClass,
                        symbol: position.symbol,
                        locale: locale
                    ),
                    systemImage: "number"
                ),
                PositionDetailRowModel(
                    id: "quantityAvailable",
                    title: L10n.PositionDetail.available,
                    value: PositionDisplay.quantityText(
                        position.quantityAvailable,
                        assetClass: position.assetClass,
                        symbol: position.symbol,
                        locale: locale
                    ),
                    systemImage: "checkmark.circle"
                ),
                PositionDetailRowModel(
                    id: "marketValue",
                    title: L10n.PositionDetail.marketValue,
                    value: AppFormatter.compactMoney(position.marketValue),
                    systemImage: "briefcase"
                )
            ]),
            PositionDetailSectionModel(id: "performance", title: L10n.PositionDetail.performance, rows: [
                PositionDetailRowModel(
                    id: "unrealizedPL",
                    title: L10n.PositionDetail.unrealizedPL,
                    value: PositionDisplay.signedCompactMoney(position.unrealizedPL),
                    systemImage: "chart.line.uptrend.xyaxis",
                    valueTint: PositionDisplay.tint(for: position.unrealizedPL)
                ),
                PositionDetailRowModel(
                    id: "unrealizedPLPC",
                    title: L10n.PositionDetail.unrealizedPLPercent,
                    value: PositionDisplay.signedPercent(position.unrealizedPLPC),
                    systemImage: "percent",
                    valueTint: PositionDisplay.tint(for: position.unrealizedPLPC)
                ),
                PositionDetailRowModel(
                    id: "unrealizedIntradayPL",
                    title: L10n.PositionDetail.intradayPL,
                    value: PositionDisplay.signedCompactMoney(position.unrealizedIntradayPL),
                    systemImage: "sun.max",
                    valueTint: PositionDisplay.tint(for: position.unrealizedIntradayPL)
                ),
                PositionDetailRowModel(
                    id: "unrealizedIntradayPLPC",
                    title: L10n.PositionDetail.intradayPLPercent,
                    value: PositionDisplay.signedPercent(position.unrealizedIntradayPLPC),
                    systemImage: "clock.arrow.circlepath",
                    valueTint: PositionDisplay.tint(for: position.unrealizedIntradayPLPC)
                ),
                PositionDetailRowModel(
                    id: "changeToday",
                    title: L10n.PositionDetail.changeToday,
                    value: PositionDisplay.signedPercent(position.changeToday),
                    systemImage: "arrow.left.and.right",
                    valueTint: PositionDisplay.tint(for: position.changeToday)
                )
            ]),
            PositionDetailSectionModel(id: "pricing", title: L10n.PositionDetail.pricingCost, rows: [
                PositionDetailRowModel(
                    id: "averageEntryPrice",
                    title: L10n.PositionDetail.averageEntryPrice,
                    value: AppFormatter.compactMoney(position.averageEntryPrice),
                    systemImage: "flag"
                ),
                PositionDetailRowModel(
                    id: "currentPrice",
                    title: L10n.PositionDetail.currentPrice,
                    value: AppFormatter.compactMoney(position.currentPrice),
                    systemImage: "dollarsign.circle"
                ),
                PositionDetailRowModel(
                    id: "lastDayPrice",
                    title: L10n.PositionDetail.lastDayPrice,
                    value: AppFormatter.compactMoney(position.lastDayPrice),
                    systemImage: "clock"
                ),
                PositionDetailRowModel(
                    id: "costBasis",
                    title: L10n.PositionDetail.costBasis,
                    value: AppFormatter.compactMoney(position.costBasis),
                    systemImage: "sum"
                )
            ]),
            PositionDetailSectionModel(id: "instrument", title: L10n.PositionDetail.instrument, rows: [
                PositionDetailRowModel(
                    id: "symbol",
                    title: L10n.PositionDetail.symbol,
                    value: PositionDisplay.normalizedSymbol(position.symbol),
                    systemImage: "tag",
                    copyValue: position.symbol
                ),
                PositionDetailRowModel(
                    id: "assetID",
                    title: L10n.PositionDetail.assetID,
                    value: PositionDisplay.text(position.assetID),
                    systemImage: "number.square",
                    copyValue: position.assetID
                ),
                PositionDetailRowModel(
                    id: "exchange",
                    title: L10n.PositionDetail.exchange,
                    value: PositionDisplay.apiValue(position.exchange),
                    systemImage: "building.columns"
                ),
                PositionDetailRowModel(
                    id: "assetClass",
                    title: L10n.PositionDetail.assetClass,
                    value: PositionDisplay.apiValue(position.assetClass),
                    systemImage: position.assetCategory.systemImage
                ),
                PositionDetailRowModel(
                    id: "assetMarginable",
                    title: L10n.PositionDetail.assetMarginable,
                    value: PositionDisplay.boolean(position.assetMarginable, locale: locale),
                    systemImage: "checkmark.shield"
                )
            ])
        ]
    }
}

private struct PositionDetailRowModel: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let tint: Color
    let valueTint: Color
    var copyValue: String?

    init(
        id: String,
        title: LocalizedStringKey,
        value: String,
        systemImage: String,
        tint: Color = AppTheme.ColorToken.icon,
        valueTint: Color = .secondary,
        copyValue: String? = nil
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
        self.valueTint = valueTint
        self.copyValue = copyValue
    }
}

enum PositionDisplay {
    static func normalizedSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

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

    static func apiValue(_ value: String?) -> String {
        guard let value = clean(value) else {
            return AppFormatter.placeholder
        }

        return value
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }

    static func boolean(_ value: Bool?, locale: Locale) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value
            ? L10n.PositionDetail.yes(locale: locale)
            : L10n.PositionDetail.no(locale: locale)
    }

    static func sideText(_ side: String?, locale: Locale) -> String {
        switch side?.lowercased() {
        case "long":
            L10n.PositionDetail.long(locale: locale)
        case "short":
            L10n.PositionDetail.short(locale: locale)
        default:
            apiValue(side)
        }
    }

    static func sideTint(_ side: String?) -> Color {
        switch side?.lowercased() {
        case "long":
            AppTheme.ColorToken.positive
        case "short":
            AppTheme.ColorToken.negative
        default:
            .secondary
        }
    }

    static func quantityText(
        _ value: String?,
        assetClass: String?,
        symbol: String?,
        locale: Locale
    ) -> String {
        let quantity = AppFormatter.numberText(value)
        guard quantity != AppFormatter.placeholder else {
            return AppFormatter.placeholder
        }

        guard let unit = PositionQuantityUnit(assetClass: assetClass, symbol: symbol).text(for: value, locale: locale) else {
            return quantity
        }

        return "\(quantity) \(unit)"
    }

    static func signedMoney(_ value: String?) -> String {
        AppFormatter.signedMoney(NumberParser.double(from: value))
    }

    static func signedCompactMoney(_ value: String?) -> String {
        AppFormatter.signedCompactMoney(NumberParser.double(from: value))
    }

    static func signedPercent(_ value: String?) -> String {
        AppFormatter.signedPercent(NumberParser.double(from: value))
    }

    static func tint(for value: String?) -> Color {
        tint(for: NumberParser.double(from: value))
    }

    static func tint(for value: Double?) -> Color {
        guard let value else {
            return .secondary
        }

        return value >= 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }
}

private enum PositionQuantityUnit {
    case shares
    case contracts
    case crypto(String?)
    case units
    case none

    init(assetClass: String?, symbol: String?) {
        guard let normalizedAssetClass = PositionDisplay.clean(assetClass)?.lowercased() else {
            self = .none
            return
        }

        if normalizedAssetClass.contains("crypto") {
            self = .crypto(Self.cryptoBaseSymbol(from: symbol))
        } else if normalizedAssetClass.contains("option") {
            self = .contracts
        } else if normalizedAssetClass.contains("equity") || normalizedAssetClass.contains("stock") || normalizedAssetClass.contains("etf") {
            self = .shares
        } else {
            self = .units
        }
    }

    func text(for quantity: String?, locale: Locale) -> String? {
        switch self {
        case .shares:
            return isSingular(quantity)
                ? L10n.PositionDetail.quantityUnitShare(locale: locale)
                : L10n.PositionDetail.quantityUnitShares(locale: locale)
        case .contracts:
            return isSingular(quantity)
                ? L10n.PositionDetail.quantityUnitContract(locale: locale)
                : L10n.PositionDetail.quantityUnitContracts(locale: locale)
        case .crypto(let baseSymbol):
            return baseSymbol ?? L10n.PositionDetail.quantityUnitUnits(locale: locale)
        case .units:
            return isSingular(quantity)
                ? L10n.PositionDetail.quantityUnitUnit(locale: locale)
                : L10n.PositionDetail.quantityUnitUnits(locale: locale)
        case .none:
            return nil
        }
    }

    private func isSingular(_ quantity: String?) -> Bool {
        guard let quantity = NumberParser.decimal(from: quantity) else {
            return false
        }

        return abs(quantity) == Decimal(1)
    }

    private static func cryptoBaseSymbol(from symbol: String?) -> String? {
        guard let symbol = PositionDisplay.clean(symbol) else {
            return nil
        }

        let normalizedSymbol = symbol.uppercased().replacingOccurrences(of: " ", with: "")
        if let separatorIndex = normalizedSymbol.firstIndex(of: "/") {
            let baseSymbol = String(normalizedSymbol[..<separatorIndex])
            return baseSymbol.isEmpty ? nil : baseSymbol
        }

        for quoteCurrency in ["USDT", "USDC", "USD"] where normalizedSymbol.hasSuffix(quoteCurrency) {
            let baseSymbol = normalizedSymbol.dropLast(quoteCurrency.count)
            if !baseSymbol.isEmpty {
                return String(baseSymbol)
            }
        }

        return normalizedSymbol.isEmpty ? nil : normalizedSymbol
    }
}

private extension Error {
    var isPositionDetailCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let apiError = self as? APIClientError, apiError == .cancelled {
            return true
        }

        if let urlError = self as? URLError {
            return urlError.code == .cancelled
        }

        return false
    }
}

#Preview {
    NavigationStack {
        PositionDetailView(position: .positionDetailPreview)
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}

private extension AlpacaPosition {
    static let positionDetailPreview = AlpacaPosition(
        assetID: "904837e3-3b76-47ec-b432-046db621571b",
        symbol: "AAPL",
        exchange: "NASDAQ",
        assetClass: "us_equity",
        assetMarginable: true,
        quantity: "5",
        quantityAvailable: "4",
        averageEntryPrice: "100.0",
        side: "long",
        marketValue: "600.0",
        costBasis: "500.0",
        unrealizedPL: "100.0",
        unrealizedPLPC: "0.20",
        unrealizedIntradayPL: "5.0",
        unrealizedIntradayPLPC: "0.0084",
        currentPrice: "120.0",
        lastDayPrice: "119.0",
        changeToday: "0.0084"
    )
}
