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
        AppTheme.ColorToken.brand,
        Color(red: 0.118, green: 0.533, blue: 0.898),
        AppTheme.ColorToken.positive,
        Color(red: 0.933, green: 0.463, blue: 0.129),
        Color(red: 0.514, green: 0.341, blue: 0.820),
        Color(red: 0.071, green: 0.647, blue: 0.725)
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
            ScrollView {
                VStack(spacing: 22) {
                    preview
                    shareActions
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 26)
            }
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
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.AssetPositionShare.done)
                    }
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

    private var style: PositionsShareCardStyle {
        PositionsShareCardStyle(colorScheme: colorScheme)
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

    private var totalUnrealizedPercentText: String? {
        payload.totalUnrealizedPLPercent.map { AppFormatter.signedPercent($0) }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: style.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                header

                HStack(alignment: .center, spacing: 20) {
                    PositionsSharePieChart(
                        slices: payload.allocationSlices(limit: allocationLimit, locale: locale),
                        positionCount: payload.positions.count,
                        style: style,
                        locale: locale
                    )
                    .frame(width: 190, height: 190)

                    PositionsShareLegend(
                        slices: payload.allocationSlices(limit: allocationLimit, locale: locale),
                        locale: locale,
                        style: style
                    )
                }
                .padding(.top, 24)

                PositionsShareMetric(
                    title: L10n.PositionsShare.unrealizedPL(locale: locale),
                    value: AppFormatter.signedCompactMoney(payload.totalUnrealizedPL, currencyCode: payload.currencyCode),
                    secondaryValue: totalUnrealizedPercentText,
                    tint: totalUnrealizedTint,
                    style: style
                )
                .padding(.top, 22)

                Text(L10n.PositionsShare.holdings(locale: locale))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(style.primaryText)
                    .padding(.top, 24)

                PositionsShareTableHeader(style: style, locale: locale)
                    .padding(.top, 12)

                VStack(spacing: 0) {
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
                .padding(.top, 2)

                if hiddenCount > 0 {
                    Text(L10n.PositionsShare.morePositions(count: hiddenCount, locale: locale))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(style.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 10)
                }

                Spacer(minLength: 0)

                footer
            }
            .padding(34)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(L10n.PositionsShare.portfolioSnapshot(locale: locale))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 12)
            }

            Text(L10n.PositionsShare.sharePreviewTitle(count: payload.positions.count, locale: locale))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private var footer: some View {
        HStack {
            Text("@Vicu")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.ColorToken.brand)

            Spacer()

            Text(Date.now.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(style.tertiaryText)
        }
        .padding(.top, 18)
    }
}

private struct PositionsSharePieChart: View {
    let slices: [PositionsShareAllocationSlice]
    let positionCount: Int
    let style: PositionsShareCardStyle
    let locale: Locale

    var body: some View {
        ZStack {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value(L10n.PositionsShare.allocation(locale: locale), slice.value),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.2
                )
                .cornerRadius(5)
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)

            VStack(spacing: 2) {
                Text("\(positionCount)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.primaryText)

                Text(L10n.PositionsShare.positionCount(count: positionCount, locale: locale))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 82)
        }
    }
}

private struct PositionsShareLegend: View {
    let slices: [PositionsShareAllocationSlice]
    let locale: Locale
    let style: PositionsShareCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.PositionsShare.allocation(locale: locale))
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(style.metricTitleText)
                .lineLimit(1)

            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 9, height: 9)

                    Text(slice.title)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)

                    Spacer(minLength: 8)

                    Text(slice.percentText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.metricBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style.metricBorder)
        }
    }
}

private struct PositionsShareMetric: View {
    let title: String
    let value: String
    let secondaryValue: String?
    let tint: Color
    let style: PositionsShareCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(style.metricTitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(displayValue)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(style.metricBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style.metricBorder)
        }
    }

    private var displayValue: String {
        guard let secondaryValue else {
            return value
        }

        return "\(value) \(secondaryValue)"
    }
}

private struct PositionsShareTableHeader: View {
    let style: PositionsShareCardStyle
    let locale: Locale

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.PositionsShare.assetCode(locale: locale))
                .frame(width: 88, alignment: .leading)

            Text(L10n.PositionsShare.entryPrice(locale: locale))
                .frame(width: 112, alignment: .trailing)

            Text(L10n.PositionsShare.latestPrice(locale: locale))
                .frame(width: 112, alignment: .trailing)

            Text(L10n.PositionsShare.unrealizedPL(locale: locale))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .black, design: .rounded))
        .foregroundStyle(style.metricTitleText)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .padding(.bottom, 6)
    }
}

private struct PositionsShareTableRow: View {
    let position: AlpacaPosition
    let currencyCode: String
    let style: PositionsShareCardStyle

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
                .font(.system(size: 17, weight: .black, design: .rounded))
                .monospaced()
                .foregroundStyle(style.primaryText)
                .frame(width: 88, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            Text(AppFormatter.money(position.averageEntryPrice, currencyCode: currencyCode))
                .frame(width: 112, alignment: .trailing)

            Text(AppFormatter.money(position.currentPrice, currencyCode: currencyCode))
                .frame(width: 112, alignment: .trailing)

            Text(AppFormatter.signedCompactMoney(unrealizedValue, currencyCode: currencyCode))
                .foregroundStyle(unrealizedTint)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 16, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(style.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.60)
        .padding(.vertical, 10)
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

private struct PositionsShareCardStyle {
    let backgroundColors: [Color]
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let metricTitleText: Color
    let metricBackground: Color
    let metricBorder: Color
    let divider: Color

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .light:
            self.init(
                backgroundColors: [
                    Color(red: 0.988, green: 0.992, blue: 0.980),
                    Color(red: 0.925, green: 0.965, blue: 0.968),
                    Color(red: 0.984, green: 0.968, blue: 0.902)
                ],
                primaryText: Color(red: 0.055, green: 0.060, blue: 0.064),
                secondaryText: Color(red: 0.260, green: 0.278, blue: 0.286),
                tertiaryText: Color(red: 0.415, green: 0.426, blue: 0.440),
                metricTitleText: Color(red: 0.405, green: 0.420, blue: 0.430),
                metricBackground: Color.white.opacity(0.74),
                metricBorder: Color.black.opacity(0.08),
                divider: Color.black.opacity(0.08)
            )
        case .dark:
            self.init(
                backgroundColors: [
                    Color.black,
                    Color(red: 0.055, green: 0.062, blue: 0.068),
                    Color.black
                ],
                primaryText: .white,
                secondaryText: .white.opacity(0.82),
                tertiaryText: .white.opacity(0.46),
                metricTitleText: .white.opacity(0.54),
                metricBackground: .white.opacity(0.10),
                metricBorder: .white.opacity(0),
                divider: .white.opacity(0.10)
            )
        @unknown default:
            self.init(colorScheme: .dark)
        }
    }

    private init(
        backgroundColors: [Color],
        primaryText: Color,
        secondaryText: Color,
        tertiaryText: Color,
        metricTitleText: Color,
        metricBackground: Color,
        metricBorder: Color,
        divider: Color
    ) {
        self.backgroundColors = backgroundColors
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.metricTitleText = metricTitleText
        self.metricBackground = metricBackground
        self.metricBorder = metricBorder
        self.divider = divider
    }
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
