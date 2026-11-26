import SwiftUI
import UIKit

struct AssetSharePayload: Identifiable {
    let id = UUID()
    let symbol: String
    let displayName: String
    let exchange: String
    let assetClass: String
    let range: AssetChartRange
    let chartModel: AssetShareChartModel
    let currentPrice: Double?
    let priceChange: Double?
    let percentChange: Double?
    let isPositive: Bool
    let open: Double?
    let high: Double?
    let low: Double?
    let volume: Double?
    let updatedAt: Date?

    @MainActor
    init(store: AssetDetailStore) {
        let model = store.chartRenderModels.line
        let fallbackModel = store.chartRenderModels.model(for: store.effectiveChartMode)
        let activeModel = model.points.isEmpty ? fallbackModel : model
        let periodChange = Self.priceChange(for: store, model: activeModel)

        symbol = store.symbol
        displayName = store.displayName
        exchange = store.exchangeText
        assetClass = store.assetClassText
        range = store.selectedRange
        chartModel = AssetShareChartModel(renderModel: activeModel)
        currentPrice = store.currentPrice ?? activeModel.points.last?.close
        priceChange = periodChange.change
        percentChange = periodChange.percentChange
        isPositive = periodChange.isPositive
        open = store.dayOpen
        high = store.dayHigh
        low = store.dayLow
        volume = store.dayVolume
        updatedAt = store.lastEventDate ?? store.lastUpdatedAt
    }

    @MainActor
    private static func priceChange(
        for store: AssetDetailStore,
        model: AssetChartRenderModel
    ) -> AssetSharePriceChange {
        // 1D must match the page's "Today" line (measured from the previous close),
        // not the chart's first intraday bar.
        if store.selectedRange == .oneDay {
            return AssetSharePriceChange(
                change: store.todayPriceChange,
                percentChange: store.todayPercentChange,
                isPositive: store.isTodayPositive
            )
        }

        if let periodChange = model.periodPriceChange {
            return AssetSharePriceChange(
                change: periodChange.change,
                percentChange: periodChange.percentChange,
                isPositive: model.isPeriodPositive
            )
        }

        return AssetSharePriceChange(
            change: store.priceChange,
            percentChange: store.percentChange,
            isPositive: store.isPositive
        )
    }
}

struct AssetShareChartModel {
    private static let maximumPointCount = 180

    let series: FinancialChartSeries
    let priceChangeBaseline: Double?

    init(renderModel: AssetChartRenderModel) {
        let sampled = FinancialChartDownsampler.lttb(
            renderModel.financialPoints[...],
            targetCount: Self.maximumPointCount
        )
        series = FinancialChartSeries(
            kind: .area,
            points: sampled,
            xDomain: renderModel.xDomain,
            baselinePolicy: .none,
            yScaleConfig: .sparkline,
            allowsZoomAndPan: false
        )
        priceChangeBaseline = renderModel.priceChangeBaseline
    }
}

struct AssetShareSheet: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let payload: AssetSharePayload
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
            .navigationTitle(L10n.AssetShare.title)
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
                .accessibilityLabel(L10n.AssetShare.previewAccessibility)
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
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
                            L10n.AssetShare.sharePreviewTitle(symbol: payload.symbol, locale: locale),
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
        let content = AssetShareCard(payload: payload, locale: locale)
            .frame(width: 540, height: 675)
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, locale)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 540, height: 675)
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

private struct AssetShareCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: AssetSharePayload
    let locale: Locale

    private var tint: Color {
        payload.isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    private var style: ShareCardStyle {
        ShareCardStyle(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            ShareCardBackground(
                accentTint: tint,
                style: style
            )

            VStack(alignment: .leading, spacing: 0) {
                header

                Spacer(minLength: 26)

                priceBlock

                AssetShareSparklineChart(
                    model: payload.chartModel,
                    tint: tint,
                    style: style
                )
                .frame(height: 200)
                .padding(.top, 26)

                metricsStrip
                    .padding(.top, 24)

                Spacer(minLength: 18)

                ShareCardFooter(
                    timestampText: updatedText,
                    style: style
                )
            }
            .padding(40)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(payload.symbol)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .monospaced()
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    if payload.exchange != AppFormatter.placeholder {
                        Text(payload.exchange)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(style.badgeText)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(style.badgeBackground, in: Capsule())
                            .lineLimit(1)
                    }
                }

                Text(payload.displayName)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(L10n.AssetShare.marketSnapshot(locale: locale))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(style.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)

                if payload.assetClass != AppFormatter.placeholder {
                    Text(payload.assetClass)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 126, alignment: .trailing)
            .padding(.top, 6)
        }
    }

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppFormatter.money(payload.currentPrice))
                .font(.system(size: 74, weight: .black, design: .rounded))
                .monospacedDigit()
                .tracking(-1.5)
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.48)

            HStack(alignment: .center, spacing: 10) {
                AssetShareChangeBadge(
                    change: payload.priceChange,
                    percentChange: payload.percentChange,
                    isPositive: payload.isPositive,
                    tint: tint,
                    style: style
                )

                Text(verbatim: "\(payload.range.title) · \(payload.range.performanceLabel)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Spacer(minLength: 0)
            }
        }
    }

    private var metricsStrip: some View {
        HStack(spacing: 0) {
            AssetShareMetricColumn(
                title: L10n.AssetShare.open(locale: locale),
                value: AppFormatter.money(payload.open),
                style: style
            )

            metricDivider

            AssetShareMetricColumn(
                title: L10n.AssetShare.high(locale: locale),
                value: AppFormatter.money(payload.high),
                style: style
            )

            metricDivider

            AssetShareMetricColumn(
                title: L10n.AssetShare.low(locale: locale),
                value: AppFormatter.money(payload.low),
                style: style
            )

            metricDivider

            AssetShareMetricColumn(
                title: L10n.AssetShare.volume(locale: locale),
                value: AssetShareNumber.compact(payload.volume),
                style: style
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(style.metricBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style.metricBorder, lineWidth: 1)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(style.divider)
            .frame(width: 1)
            .padding(.vertical, 12)
    }

    private var updatedText: String {
        let date = payload.updatedAt ?? Date.now
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }
}

private struct AssetShareChangeBadge: View {
    let change: Double?
    let percentChange: Double?
    let isPositive: Bool
    let tint: Color
    let style: ShareCardStyle

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 13, weight: .bold))

            Text("\(AppFormatter.signedMoney(change)) \(AppFormatter.signedPercent(percentChange))")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 13)
        .frame(height: 36)
        .background(style.pillBackground, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(style.metricBorder, lineWidth: 1)
        }
    }
}

private struct AssetShareSparklineChart: View {
    let model: AssetShareChartModel
    let tint: Color
    let style: ShareCardStyle

    var body: some View {
        StaticSparklineChartView(
            series: model.series,
            style: FinancialChartStyle(
                lineColor: tint.opacity(0.92),
                positiveColor: AppTheme.ColorToken.positive,
                negativeColor: AppTheme.ColorToken.negative,
                areaTopOpacity: style.chartFillOpacity,
                areaBottomOpacity: 0.01,
                lineWidth: 4.5,
                lineHighlightColor: style.chartHighlight,
                lineHighlightWidth: 1.4,
                gridColor: style.chartGrid,
                showsGrid: true,
                showsVolume: false,
                showsEndpointPulse: false,
                interpolation: .monotone
            ),
            insets: .sparkline,
            showsEndpointDot: true
        )
    }
}

private struct AssetShareMetricColumn: View {
    let title: String
    let value: String
    let style: ShareCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(style.metricTitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.56)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
    }
}

private struct AssetSharePriceChange {
    let change: Double?
    let percentChange: Double?
    let isPositive: Bool
}

private enum AssetShareNumber {
    static func compact(_ value: Double?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...2)))
    }
}
