import SwiftUI
import UIKit

struct AssetPositionSharePayload: Identifiable {
    let id = UUID()
    let symbol: String
    let displayName: String
    let exchange: String
    let position: AlpacaPosition
}

struct AssetPositionShareSheet: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let payload: AssetPositionSharePayload
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
                .background(Color.clear)
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
            .navigationTitle(L10n.AssetPositionShare.title)
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
                .accessibilityLabel(L10n.AssetPositionShare.previewAccessibility)
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
                            L10n.AssetPositionShare.sharePreviewTitle(symbol: payload.symbol, locale: locale),
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
        let content = AssetPositionShareCard(payload: payload, locale: locale)
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

private struct AssetPositionShareCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: AssetPositionSharePayload
    let locale: Locale

    private var intradayPerformance: AssetPositionSharePerformance {
        AssetPositionSharePerformance.intraday(position: payload.position)
    }

    private var unrealizedPerformance: AssetPositionSharePerformance {
        AssetPositionSharePerformance.unrealized(position: payload.position)
    }

    private var isPositive: Bool {
        intradayPerformance.isPositive
    }

    private var tint: Color {
        isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    private var unrealizedTint: Color {
        guard let amount = unrealizedPerformance.amount else {
            return style.primaryText
        }

        return amount >= 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
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

                Spacer(minLength: 20)

                performanceBlock

                Spacer(minLength: 22)

                metricsCard

                ShareCardFooter(
                    timestampText: Date.now.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)),
                    style: style
                )
                .padding(.top, 24)
            }
            .padding(40)
        }
    }

    private var header: some View {
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

                Spacer(minLength: 12)
            }

            Text(payload.displayName)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(style.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
    }

    private var performanceBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.AssetPositionShare.intradayPL(locale: locale))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(style.metricTitleText)
                .lineLimit(1)

            Text(AppFormatter.signedMoney(intradayPerformance.amount))
                .font(.system(size: 82, weight: .black, design: .rounded))
                .monospacedDigit()
                .tracking(-1.5)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .padding(.top, 6)

            HStack(spacing: 7) {
                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 15, weight: .bold))

                Text(AppFormatter.signedPercent(intradayPerformance.percent, fractionLength: 2))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(style.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background(style.pillBackground, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(style.metricBorder, lineWidth: 1)
            }
            .padding(.top, 12)
        }
    }

    private var metricsCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L10n.AssetPositionShare.unrealizedPL(locale: locale))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(style.metricTitleText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AppFormatter.signedMoney(unrealizedPerformance.amount))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(unrealizedTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)

                    if let unrealizedPercent = unrealizedPerformance.percent {
                        Text(AppFormatter.signedPercent(unrealizedPercent, fractionLength: 2))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(style.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)

            Rectangle()
                .fill(style.divider)
                .frame(height: 1)
                .padding(.horizontal, 20)

            HStack(spacing: 0) {
                AssetPositionSharePriceColumn(
                    title: L10n.AssetPositionShare.entryPrice(locale: locale),
                    value: AppFormatter.money(payload.position.averageEntryPrice),
                    style: style
                )

                Rectangle()
                    .fill(style.divider)
                    .frame(width: 1)
                    .padding(.vertical, 14)

                AssetPositionSharePriceColumn(
                    title: L10n.AssetPositionShare.latestPrice(locale: locale),
                    value: AppFormatter.money(payload.position.currentPrice),
                    style: style
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(style.metricBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style.metricBorder, lineWidth: 1)
        }
    }
}

struct AssetPositionSharePerformance {
    let amount: Double?
    let percent: Double?

    var isPositive: Bool {
        (amount ?? percent ?? 0) >= 0
    }

    static func intraday(position: AlpacaPosition) -> AssetPositionSharePerformance {
        let amount = NumberParser.double(from: position.unrealizedIntradayPL)
            ?? calculatedIntradayAmount(position: position)
        let percent = NumberParser.double(from: position.unrealizedIntradayPLPC)
            ?? calculatedIntradayPercent(position: position)

        return AssetPositionSharePerformance(amount: amount, percent: percent)
    }

    static func unrealized(position: AlpacaPosition) -> AssetPositionSharePerformance {
        let amount = NumberParser.double(from: position.unrealizedPL)
            ?? calculatedUnrealizedAmount(position: position)
        let percent = NumberParser.double(from: position.unrealizedPLPC)
            ?? calculatedUnrealizedPercent(position: position)

        return AssetPositionSharePerformance(amount: amount, percent: percent)
    }

    private static func calculatedUnrealizedAmount(position: AlpacaPosition) -> Double? {
        let marketValue = NumberParser.double(from: position.marketValue)
        let costBasis = NumberParser.double(from: position.costBasis)
        guard let marketValue, let costBasis else {
            return nil
        }
        return marketValue - costBasis
    }

    private static func calculatedUnrealizedPercent(position: AlpacaPosition) -> Double? {
        guard let costBasis = NumberParser.double(from: position.costBasis),
              costBasis != 0,
              let amount = calculatedUnrealizedAmount(position: position) else {
            return nil
        }
        return amount / costBasis
    }

    private static func calculatedIntradayAmount(position: AlpacaPosition) -> Double? {
        guard position.assetCategory != .option,
              let currentPrice = NumberParser.double(from: position.currentPrice),
              let lastDayPrice = NumberParser.double(from: position.lastDayPrice),
              let quantity = NumberParser.double(from: position.quantity) else {
            return nil
        }

        let direction = positionDirection(position)
        return (currentPrice - lastDayPrice) * abs(quantity) * direction
    }

    private static func calculatedIntradayPercent(position: AlpacaPosition) -> Double? {
        if let changeToday = NumberParser.double(from: position.changeToday) {
            return changeToday * positionDirection(position)
        }

        guard position.assetCategory != .option,
              let currentPrice = NumberParser.double(from: position.currentPrice),
              let lastDayPrice = NumberParser.double(from: position.lastDayPrice),
              lastDayPrice != 0 else {
            return nil
        }

        let direction = positionDirection(position)
        return ((currentPrice - lastDayPrice) / lastDayPrice) * direction
    }

    private static func positionDirection(_ position: AlpacaPosition) -> Double {
        if position.side?.lowercased() == "short" {
            return -1
        }

        if let quantity = NumberParser.double(from: position.quantity), quantity < 0 {
            return -1
        }

        return 1
    }
}

private struct AssetPositionSharePriceColumn: View {
    let title: String
    let value: String
    let style: ShareCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(style.metricTitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
    }
}
