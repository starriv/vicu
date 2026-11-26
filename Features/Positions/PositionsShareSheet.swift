import Charts
import SwiftUI
import UIKit

struct PositionsSharePayload: Identifiable {
    let id = UUID()
    let positions: [AlpacaPosition]
    let account: AlpacaAccount?

    init(positions: [AlpacaPosition], account: AlpacaAccount?) {
        self.positions = positions
        self.account = account
    }

    var currencyCode: String {
        account?.currency ?? "USD"
    }

    var totalUnrealizedPL: Double? {
        Self.sum(positions.map(\.unrealizedPL))
    }

    var totalUnrealizedPLPercent: Double? {
        guard let totalUnrealizedPL,
              let totalCostBasis = Self.sumAbsolute(positions.map(\.costBasis)),
              totalCostBasis != 0 else {
            return nil
        }

        return totalUnrealizedPL / totalCostBasis
    }

    func visibleRows(limit: Int) -> [AlpacaPosition] {
        Array(
            positions
                .sorted { lhs, rhs in
                    let lhsVolume = Self.absolutePositionVolume(lhs)
                    let rhsVolume = Self.absolutePositionVolume(rhs)
                    if lhsVolume == rhsVolume {
                        return PositionDisplay.normalizedSymbol(lhs.symbol) < PositionDisplay.normalizedSymbol(rhs.symbol)
                    }

                    return lhsVolume > rhsVolume
                }
                .prefix(limit)
        )
    }

    fileprivate func allocationSlices(limit: Int, locale: Locale) -> [PositionsShareAllocationSlice] {
        let valuedPositions = positions
            .compactMap { position -> PositionsShareAllocationEntry? in
                guard let marketValue = NumberParser.double(from: position.marketValue) else {
                    return nil
                }

                let absoluteValue = abs(marketValue)
                guard absoluteValue > 0 else {
                    return nil
                }

                return PositionsShareAllocationEntry(
                    symbol: PositionDisplay.normalizedSymbol(position.symbol),
                    value: absoluteValue
                )
            }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.symbol < rhs.symbol
                }

                return lhs.value > rhs.value
            }

        if valuedPositions.isEmpty {
            return fallbackAllocationSlices(limit: limit, locale: locale)
        }

        return allocationSlices(from: valuedPositions, limit: limit, locale: locale)
    }

    private func fallbackAllocationSlices(limit: Int, locale: Locale) -> [PositionsShareAllocationSlice] {
        let volumeEntries = visibleRows(limit: positions.count).map { position in
            PositionsShareAllocationEntry(
                symbol: PositionDisplay.normalizedSymbol(position.symbol),
                value: 1
            )
        }

        return allocationSlices(from: volumeEntries, limit: limit, locale: locale)
    }

    private func allocationSlices(
        from entries: [PositionsShareAllocationEntry],
        limit: Int,
        locale: Locale
    ) -> [PositionsShareAllocationSlice] {
        guard !entries.isEmpty else {
            return []
        }

        let total = entries.reduce(0) { $0 + $1.value }
        let maximumSliceCount = max(limit, 1)
        let visibleEntryCount = entries.count > maximumSliceCount
            ? maximumSliceCount - 1
            : entries.count
        let visibleEntries = Array(entries.prefix(visibleEntryCount))
        let hiddenValue = entries.dropFirst(visibleEntryCount).reduce(0) { $0 + $1.value }

        let visibleSlices = visibleEntries.enumerated().map { index, entry in
            PositionsShareAllocationSlice(
                id: entry.symbol,
                title: entry.symbol,
                value: entry.value,
                percentText: Self.percentText(entry.value, total: total),
                color: Self.palette[index % Self.palette.count]
            )
        }

        guard hiddenValue > 0 else {
            return visibleSlices
        }

        return visibleSlices + [
            PositionsShareAllocationSlice(
                id: "others",
                title: L10n.PositionsShare.other(locale: locale),
                value: hiddenValue,
                percentText: Self.percentText(hiddenValue, total: total),
                color: Self.palette[visibleSlices.count % Self.palette.count]
            )
        ]
    }

    private static func sum(_ values: [String?]) -> Double? {
        let parsedValues = values.compactMap(NumberParser.double)
        guard !parsedValues.isEmpty else {
            return nil
        }

        return parsedValues.reduce(0, +)
    }

    private static func sumAbsolute(_ values: [String?]) -> Double? {
        let parsedValues = values.compactMap(NumberParser.double).map(abs)
        guard !parsedValues.isEmpty else {
            return nil
        }

        return parsedValues.reduce(0, +)
    }

    private static func absolutePositionVolume(_ position: AlpacaPosition) -> Double {
        abs(NumberParser.double(from: position.quantity) ?? 0)
    }

    private static func percentText(_ value: Double, total: Double) -> String {
        guard total > 0 else {
            return AppFormatter.placeholder
        }

        return AppFormatter.percent(value / total, fractionLength: 0)
    }

    private static let palette: [Color] = [
        Color(red: 0.290, green: 0.435, blue: 0.647),
        Color(red: 0.239, green: 0.569, blue: 0.549),
        Color(red: 0.831, green: 0.635, blue: 0.298),
        Color(red: 0.486, green: 0.435, blue: 0.624),
        Color(red: 0.557, green: 0.588, blue: 0.643),
        Color(red: 0.784, green: 0.478, blue: 0.420)
    ]
}

struct PositionsShareHeaderButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .offset(y: -1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(PositionsShareCircleButtonModifier())
        .accessibilityLabel(L10n.Positions.share)
    }
}

struct PositionsShareSheet: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let payload: PositionsSharePayload
    @State private var renderedImage: AssetRenderedShareImage?
    @State private var isSavingImage = false
    @State private var didSaveImage = false
    @State private var saveAlert: AssetShareSaveAlert?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    preview
                    shareActions
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, 12)
                .padding(.bottom, 26)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .task(id: "\(payload.id)-\(locale.identifier)-\(colorScheme)") {
                await Task.yield()
                guard !Task.isCancelled else {
                    return
                }

                renderShareImage()
            }
            .alert(item: $saveAlert) { alert in
                if alert.showsSettingsButton {
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        primaryButton: .default(Text(L10n.AssetPositionShare.openSettings(locale: locale))) {
                            openAppSettings()
                        },
                        secondaryButton: .cancel()
                    )
                } else {
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text(L10n.AssetPositionShare.ok(locale: locale)))
                    )
                }
            }
            .navigationTitle(L10n.PositionsShare.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppSheetCloseButton()
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .presentationBackground(.thinMaterial)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let renderedImage {
            Image(uiImage: renderedImage.image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.16))
                }
                .frame(maxWidth: 370)
                .accessibilityLabel(L10n.PositionsShare.previewAccessibility)
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    ProgressView()
                }
                .frame(maxWidth: 370)
        }
    }

    @ViewBuilder
    private var shareActions: some View {
        Group {
            if let renderedImage {
                HStack(spacing: 12) {
                    Button {
                        saveImage(renderedImage)
                    } label: {
                        AssetShareButtonLabel(
                            title: saveButtonTitle,
                            systemImage: didSaveImage ? "checkmark" : "square.and.arrow.down",
                            isEnabled: !isSavingImage
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingImage)

                    ShareLink(
                        item: AssetShareImage(pngData: renderedImage.pngData),
                        preview: SharePreview(
                            L10n.PositionsShare.sharePreviewTitle(count: payload.positions.count, locale: locale),
                            image: Image(uiImage: renderedImage.image)
                        )
                    ) {
                        AssetShareButtonLabel(
                            title: L10n.AssetPositionShare.share(locale: locale),
                            systemImage: "square.and.arrow.up",
                            isEnabled: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                AssetShareButtonLabel(
                    title: L10n.AssetPositionShare.preparingImage(locale: locale),
                    systemImage: "photo",
                    isEnabled: false
                )
            }
        }
        .frame(maxWidth: 370)
    }

    @MainActor
    private func renderShareImage() {
        renderedImage = nil
        let content = PositionsShareCard(payload: payload, locale: locale)
            .frame(width: 600, height: 800)
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, locale)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 600, height: 800)
        renderer.scale = 2.0
        renderedImage = renderer.uiImage.flatMap(AssetRenderedShareImage.init(image:))
    }

    private func saveImage(_ renderedImage: AssetRenderedShareImage) {
        Task {
            await saveImageToPhotoLibrary(renderedImage)
        }
    }

    @MainActor
    private func saveImageToPhotoLibrary(_ renderedImage: AssetRenderedShareImage) async {
        guard !isSavingImage else {
            return
        }

        isSavingImage = true
        didSaveImage = false
        defer { isSavingImage = false }

        let authorizationStatus = await AssetSharePhotoLibraryWriter.requestAddAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            saveAlert = .photoAuthorization(status: authorizationStatus, locale: locale)
            return
        }

        do {
            try await AssetSharePhotoLibraryWriter.writePNGData(renderedImage.pngData)
            didSaveImage = true
        } catch {
            toastCenter.showErrorMessage(L10n.AssetPositionShare.saveFailed(locale: locale))
        }
    }

    private var saveButtonTitle: String {
        if isSavingImage {
            return L10n.AssetPositionShare.saving(locale: locale)
        }

        if didSaveImage {
            return L10n.AssetPositionShare.saved(locale: locale)
        }

        return L10n.AssetPositionShare.save(locale: locale)
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(settingsURL)
    }
}

private struct PositionsShareCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: PositionsSharePayload
    let locale: Locale

    private let allocationLimit = 4
    private let rowLimit = 5

    private var style: ShareCardStyle {
        ShareCardStyle(colorScheme: colorScheme)
    }

    private var rows: [AlpacaPosition] {
        payload.visibleRows(limit: rowLimit)
    }

    private var hiddenCount: Int {
        max(payload.positions.count - rows.count, 0)
    }

    private var totalUnrealizedTint: Color {
        PositionDisplay.tint(for: payload.totalUnrealizedPL)
    }

    private var isUnrealizedPositive: Bool {
        (payload.totalUnrealizedPL ?? payload.totalUnrealizedPLPercent ?? 0) >= 0
    }

    private var totalUnrealizedPercentText: String? {
        payload.totalUnrealizedPLPercent.map { AppFormatter.signedPercent($0) }
    }

    private var allocationSlices: [PositionsShareAllocationSlice] {
        payload.allocationSlices(limit: allocationLimit, locale: locale)
    }

    var body: some View {
        ZStack {
            ShareCardBackground(
                accentTint: totalUnrealizedTint,
                style: style
            )

            VStack(alignment: .leading, spacing: 0) {
                header

                performanceHero
                    .padding(.top, 20)

                allocationCard
                    .padding(.top, 18)

                holdingsHeader
                    .padding(.top, 22)

                holdingsTableCard
                    .padding(.top, 10)

                Spacer(minLength: 14)

                ShareCardFooter(
                    timestampText: Date.now.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)),
                    style: style
                )
            }
            .padding(36)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(L10n.PositionsShare.portfolioSnapshot(locale: locale))
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 8)

            Text(L10n.PositionsShare.sharePreviewTitle(count: payload.positions.count, locale: locale))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(style.badgeText)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(style.badgeBackground, in: Capsule())
                .lineLimit(1)
        }
    }

    private var performanceHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.PositionsShare.unrealizedPL(locale: locale))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(style.metricTitleText)
                .lineLimit(1)

            HStack(alignment: .center, spacing: 12) {
                Text(AppFormatter.signedCompactMoney(payload.totalUnrealizedPL, currencyCode: payload.currencyCode))
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1.0)
                    .foregroundStyle(totalUnrealizedTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                if let totalUnrealizedPercentText {
                    HStack(spacing: 5) {
                        Image(systemName: isUnrealizedPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 12, weight: .bold))

                        Text(totalUnrealizedPercentText)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(style.pillBackground, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(style.metricBorder, lineWidth: 1)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var allocationCard: some View {
        HStack(alignment: .center, spacing: 20) {
            PositionsSharePieChart(
                slices: allocationSlices,
                positionCount: payload.positions.count,
                style: style,
                locale: locale
            )
            .frame(width: 148, height: 148)

            PositionsShareLegend(
                slices: allocationSlices,
                locale: locale,
                style: style
            )
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.metricBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style.metricBorder, lineWidth: 1)
        }
    }

    private var holdingsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.PositionsShare.holdings(locale: locale))
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(style.primaryText)

            Spacer()

            if hiddenCount > 0 {
                Text(L10n.PositionsShare.morePositions(count: hiddenCount, locale: locale))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.tertiaryText)
            }
        }
    }

    private var holdingsTableCard: some View {
        VStack(spacing: 0) {
            PositionsShareTableHeader(style: style, locale: locale)

            Rectangle()
                .fill(style.divider)
                .frame(height: 1)

            ForEach(rows) { position in
                PositionsShareTableRow(
                    position: position,
                    currencyCode: payload.currencyCode,
                    style: style
                )

                if position.id != rows.last?.id {
                    Rectangle()
                        .fill(style.divider)
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(style.metricBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style.metricBorder, lineWidth: 1)
        }
    }
}

private struct PositionsSharePieChart: View {
    let slices: [PositionsShareAllocationSlice]
    let positionCount: Int
    let style: ShareCardStyle
    let locale: Locale

    var body: some View {
        ZStack {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value(L10n.PositionsShare.allocation(locale: locale), slice.value),
                    innerRadius: .ratio(0.65),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)

            VStack(spacing: 1) {
                Text("\(positionCount)")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.primaryText)

                Text(L10n.PositionsShare.positionCount(count: positionCount, locale: locale))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 72)
        }
    }
}

private struct PositionsShareLegend: View {
    let slices: [PositionsShareAllocationSlice]
    let locale: Locale
    let style: ShareCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L10n.PositionsShare.allocation(locale: locale))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(style.metricTitleText)
                .lineLimit(1)

            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 8, height: 8)

                    Text(slice.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)

                    Spacer(minLength: 8)

                    Text(slice.percentText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PositionsShareTableHeader: View {
    let style: ShareCardStyle
    let locale: Locale

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.PositionsShare.assetCode(locale: locale))
                .frame(width: 84, alignment: .leading)

            Text(L10n.PositionsShare.entryPrice(locale: locale))
                .frame(width: 106, alignment: .trailing)

            Text(L10n.PositionsShare.latestPrice(locale: locale))
                .frame(width: 106, alignment: .trailing)

            Text(L10n.PositionsShare.unrealizedPL(locale: locale))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(style.metricTitleText)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .padding(.bottom, 8)
    }
}

private struct PositionsShareTableRow: View {
    let position: AlpacaPosition
    let currencyCode: String
    let style: ShareCardStyle

    private var symbol: String {
        PositionDisplay.normalizedSymbol(position.symbol)
    }

    private var unrealizedValue: Double? {
        NumberParser.double(from: position.unrealizedPL)
    }

    private var unrealizedTint: Color {
        PositionDisplay.tint(for: unrealizedValue)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(symbol)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .monospaced()
                .foregroundStyle(style.primaryText)
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            Text(AppFormatter.money(position.averageEntryPrice, currencyCode: currencyCode))
                .frame(width: 106, alignment: .trailing)

            Text(AppFormatter.money(position.currentPrice, currencyCode: currencyCode))
                .frame(width: 106, alignment: .trailing)

            Text(AppFormatter.signedCompactMoney(unrealizedValue, currencyCode: currencyCode))
                .foregroundStyle(unrealizedTint)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(style.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.60)
        .padding(.vertical, 9)
    }
}

private struct PositionsShareAllocationEntry {
    let symbol: String
    let value: Double
}

private struct PositionsShareAllocationSlice: Identifiable {
    let id: String
    let title: String
    let value: Double
    let percentText: String
    let color: Color
}

private struct PositionsShareCircleButtonModifier: ViewModifier {
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
