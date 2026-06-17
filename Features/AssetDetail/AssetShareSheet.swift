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
                isPositive: periodChange.isPositive
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

    let points: [AssetShareChartPoint]
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>
    let priceChangeBaseline: Double?

    init(renderModel: AssetChartRenderModel) {
        points = Self.sampledPoints(from: renderModel.points)
        xDomain = renderModel.xDomain
        yDomain = renderModel.yDomain
        priceChangeBaseline = renderModel.priceChangeBaseline
    }

    private static func sampledPoints(from points: [AssetChartPoint]) -> [AssetShareChartPoint] {
        guard points.count > maximumPointCount, maximumPointCount > 1 else {
            return points.map(AssetShareChartPoint.init(point:))
        }

        let step = Double(points.count - 1) / Double(maximumPointCount - 1)
        var sampled: [AssetShareChartPoint] = []
        sampled.reserveCapacity(maximumPointCount)

        var lastIndex = -1
        for outputIndex in 0..<maximumPointCount {
            let sourceIndex = min(points.count - 1, Int((Double(outputIndex) * step).rounded()))
            guard sourceIndex != lastIndex else {
                continue
            }

            sampled.append(AssetShareChartPoint(point: points[sourceIndex]))
            lastIndex = sourceIndex
        }

        if let last = points.last, sampled.last?.xPosition != last.xPosition {
            sampled.append(AssetShareChartPoint(point: last))
        }

        return sampled
    }
}

struct AssetShareChartPoint {
    let xPosition: Double
    let close: Double

    init(point: AssetChartPoint) {
        xPosition = point.xPosition
        close = point.close
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
            .navigationTitle(L10n.AssetShare.title)
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

    private var style: AssetShareCardStyle {
        AssetShareCardStyle(colorScheme: colorScheme)
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

                Spacer(minLength: 28)

                priceBlock

                AssetShareSparklineChart(
                    model: payload.chartModel,
                    tint: tint,
                    style: style
                )
                .frame(height: 205)
                .padding(.top, 28)

                metrics
                    .padding(.top, 26)

                Spacer(minLength: 18)

                footer
            }
            .padding(40)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(payload.symbol)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .monospaced()
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    if payload.exchange != AppFormatter.placeholder {
                        Text(payload.exchange)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(style.badgeText)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(style.badgeBackground, in: Capsule())
                            .lineLimit(1)
                    }
                }

                Text(payload.displayName)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(L10n.AssetShare.marketSnapshot(locale: locale))
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ColorToken.brand)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)

                if payload.assetClass != AppFormatter.placeholder {
                    Text(payload.assetClass)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 126, alignment: .trailing)
        }
    }

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppFormatter.money(payload.currentPrice))
                .font(.system(size: 76, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.48)

            HStack(alignment: .center, spacing: 11) {
                AssetShareChangeBadge(
                    change: payload.priceChange,
                    percentChange: payload.percentChange,
                    isPositive: payload.isPositive,
                    tint: tint,
                    style: style
                )

                Text(verbatim: "\(payload.range.title) · \(payload.range.performanceLabel)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Spacer(minLength: 0)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            AssetShareMetric(
                title: L10n.AssetShare.open(locale: locale),
                value: AppFormatter.money(payload.open),
                style: style
            )
            AssetShareMetric(
                title: L10n.AssetShare.high(locale: locale),
                value: AppFormatter.money(payload.high),
                style: style
            )
            AssetShareMetric(
                title: L10n.AssetShare.low(locale: locale),
                value: AppFormatter.money(payload.low),
                style: style
            )
            AssetShareMetric(
                title: L10n.AssetShare.volume(locale: locale),
                value: AssetShareNumber.compact(payload.volume),
                style: style
            )
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("@Vicu")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.ColorToken.brand)

            Spacer()

            Text(updatedText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(style.tertiaryText)
                .lineLimit(1)
        }
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
    let style: AssetShareCardStyle

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 13, weight: .black))

            Text("\(AppFormatter.signedMoney(change)) \(AppFormatter.signedPercent(percentChange))")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(style.changeBadgeBackground, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(style.changeBadgeStrokeOpacity), lineWidth: 1)
        }
    }
}

private struct AssetShareSparklineChart: View {
    let model: AssetShareChartModel
    let tint: Color
    let style: AssetShareCardStyle

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size)

            guard model.points.count > 1 else {
                drawEmptyLine(context: &context, size: size)
                return
            }

            let points = model.points.map { point(for: $0, in: size) }
            guard let first = points.first, let last = points.last else {
                return
            }

            var linePath = Path()
            linePath.move(to: first)
            points.dropFirst().forEach { linePath.addLine(to: $0) }

            var areaPath = linePath
            areaPath.addLine(to: CGPoint(x: last.x, y: size.height - 8))
            areaPath.addLine(to: CGPoint(x: first.x, y: size.height - 8))
            areaPath.closeSubpath()

            context.fill(
                areaPath,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(style.chartFillOpacity), tint.opacity(0.02)]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )

            context.stroke(
                linePath,
                with: .color(tint.opacity(0.92)),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                linePath,
                with: .color(style.chartHighlight),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )

            context.fill(
                Path(ellipseIn: CGRect(x: last.x - 6, y: last.y - 6, width: 12, height: 12)),
                with: .color(tint)
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: last.x - 9, y: last.y - 9, width: 18, height: 18)),
                with: .color(tint.opacity(0.30)),
                lineWidth: 3
            )
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        for index in 1..<4 {
            let y = size.height * CGFloat(index) / 4
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(style.chartGrid), lineWidth: 1)
        }

        for index in 1..<5 {
            let x = size.width * CGFloat(index) / 5
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(style.chartGrid), lineWidth: 1)
        }
    }

    private func drawEmptyLine(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height * 0.58))
        path.addLine(to: CGPoint(x: size.width, y: size.height * 0.42))
        context.stroke(
            path,
            with: .color(tint.opacity(0.35)),
            style: StrokeStyle(lineWidth: 5, lineCap: .round)
        )
    }

    private func point(for point: AssetShareChartPoint, in size: CGSize) -> CGPoint {
        let xSpan = max(model.xDomain.upperBound - model.xDomain.lowerBound, 0.0001)
        let ySpan = max(model.yDomain.upperBound - model.yDomain.lowerBound, 0.0001)
        let xProgress = (point.xPosition - model.xDomain.lowerBound) / xSpan
        let yProgress = (point.close - model.yDomain.lowerBound) / ySpan
        let inset: CGFloat = 8

        return CGPoint(
            x: inset + (size.width - inset * 2) * CGFloat(xProgress),
            y: inset + (size.height - inset * 2) * (1 - CGFloat(yProgress))
        )
    }

}

private struct AssetShareMetric: View {
    let title: String
    let value: String
    let style: AssetShareCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(style.metricTitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.56)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 12)
        .background(style.metricBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style.metricBorder)
        }
    }
}

private struct AssetShareCardStyle {
    let backgroundColors: [Color]
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let badgeText: Color
    let badgeBackground: Color
    let metricTitleText: Color
    let metricBackground: Color
    let metricBorder: Color
    let changeBadgeBackground: Color
    let changeBadgeStrokeOpacity: Double
    let chartGrid: Color
    let chartHighlight: Color
    let chartFillOpacity: Double

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .light:
            self.init(
                backgroundColors: [
                    Color(red: 0.990, green: 0.992, blue: 0.994),
                    Color(red: 0.940, green: 0.966, blue: 0.982),
                    Color(red: 0.984, green: 0.982, blue: 0.956)
                ],
                primaryText: Color(red: 0.052, green: 0.058, blue: 0.064),
                secondaryText: Color(red: 0.260, green: 0.285, blue: 0.300),
                tertiaryText: Color(red: 0.455, green: 0.475, blue: 0.490),
                badgeText: Color(red: 0.145, green: 0.160, blue: 0.170),
                badgeBackground: Color.black.opacity(0.07),
                metricTitleText: Color(red: 0.455, green: 0.475, blue: 0.490),
                metricBackground: Color.white.opacity(0.70),
                metricBorder: Color.black.opacity(0.08),
                changeBadgeBackground: Color.white.opacity(0.62),
                changeBadgeStrokeOpacity: 0.20,
                chartGrid: Color.black.opacity(0.06),
                chartHighlight: Color.white.opacity(0.82),
                chartFillOpacity: 0.20
            )
        case .dark:
            self.init(
                backgroundColors: [
                    Color.black,
                    Color(red: 0.038, green: 0.044, blue: 0.050),
                    Color(red: 0.012, green: 0.014, blue: 0.016)
                ],
                primaryText: .white,
                secondaryText: .white.opacity(0.78),
                tertiaryText: .white.opacity(0.44),
                badgeText: .white.opacity(0.78),
                badgeBackground: .white.opacity(0.10),
                metricTitleText: .white.opacity(0.46),
                metricBackground: .white.opacity(0.095),
                metricBorder: .white.opacity(0.08),
                changeBadgeBackground: .white.opacity(0.09),
                changeBadgeStrokeOpacity: 0.34,
                chartGrid: .white.opacity(0.06),
                chartHighlight: .white.opacity(0.22),
                chartFillOpacity: 0.22
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
        badgeText: Color,
        badgeBackground: Color,
        metricTitleText: Color,
        metricBackground: Color,
        metricBorder: Color,
        changeBadgeBackground: Color,
        changeBadgeStrokeOpacity: Double,
        chartGrid: Color,
        chartHighlight: Color,
        chartFillOpacity: Double
    ) {
        self.backgroundColors = backgroundColors
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.badgeText = badgeText
        self.badgeBackground = badgeBackground
        self.metricTitleText = metricTitleText
        self.metricBackground = metricBackground
        self.metricBorder = metricBorder
        self.changeBadgeBackground = changeBadgeBackground
        self.changeBadgeStrokeOpacity = changeBadgeStrokeOpacity
        self.chartGrid = chartGrid
        self.chartHighlight = chartHighlight
        self.chartFillOpacity = chartFillOpacity
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
