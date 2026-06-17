import CoreTransferable
import Photos
import SwiftUI
import UniformTypeIdentifiers
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
    @State private var renderedImage: UIImage?
    @State private var isSavingImage = false
    @State private var didSaveImage = false
    @State private var saveAlert: AssetPositionShareSaveAlert?

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
            .scrollContentBackground(.hidden)
            .task(id: "\(payload.id)-\(locale.identifier)-\(colorScheme)") {
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
            Image(uiImage: renderedImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.16))
                }
                .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
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
            if let renderedImage, let shareItem = AssetPositionShareImage(image: renderedImage) {
                HStack(spacing: 12) {
                    Button {
                        saveImage(renderedImage)
                    } label: {
                        AssetPositionShareButtonLabel(
                            title: saveButtonTitle,
                            systemImage: didSaveImage ? "checkmark" : "square.and.arrow.down",
                            isEnabled: !isSavingImage
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingImage)

                    ShareLink(
                        item: shareItem,
                        preview: SharePreview(
                            L10n.AssetPositionShare.sharePreviewTitle(symbol: payload.symbol, locale: locale),
                            image: Image(uiImage: renderedImage)
                        )
                    ) {
                        AssetPositionShareButtonLabel(
                            title: L10n.AssetPositionShare.share(locale: locale),
                            systemImage: "square.and.arrow.up",
                            isEnabled: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                AssetPositionShareButtonLabel(
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
        let content = AssetPositionShareCard(payload: payload, locale: locale)
            .frame(width: 540, height: 675)
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, locale)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 540, height: 675)
        renderer.scale = 2.0
        renderedImage = renderer.uiImage
    }

    private func saveImage(_ image: UIImage) {
        Task {
            await saveImageToPhotoLibrary(image)
        }
    }

    @MainActor
    private func saveImageToPhotoLibrary(_ image: UIImage) async {
        guard !isSavingImage else {
            return
        }

        isSavingImage = true
        didSaveImage = false
        defer { isSavingImage = false }

        guard let imageData = image.pngData() else {
            toastCenter.showErrorMessage(L10n.AssetPositionShare.prepareFailed(locale: locale))
            return
        }

        let authorizationStatus = await AssetPositionPhotoLibraryWriter.requestAddAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            saveAlert = .photoAuthorization(status: authorizationStatus, locale: locale)
            return
        }

        do {
            try await AssetPositionPhotoLibraryWriter.writePNGData(imageData)
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

private enum AssetPositionPhotoLibraryWriter {
    static func requestAddAuthorization() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch currentStatus {
        case .authorized, .limited:
            return currentStatus
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(returning: status)
                }
            }
        case .denied, .restricted:
            return currentStatus
        @unknown default:
            return currentStatus
        }
    }

    static func writePNGData(_ imageData: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.png.identifier
                request.addResource(with: .photo, data: imageData, options: options)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AssetPositionShareSaveError.failed)
                }
            }
        }
    }
}

private struct AssetPositionShareSaveAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let showsSettingsButton: Bool

    static func photoAuthorization(status: PHAuthorizationStatus, locale: Locale) -> AssetPositionShareSaveAlert {
        switch status {
        case .denied:
            AssetPositionShareSaveAlert(
                title: L10n.AssetPositionShare.photoAccessOffTitle(locale: locale),
                message: L10n.AssetPositionShare.photoAccessOffMessage(locale: locale),
                showsSettingsButton: true
            )
        case .restricted:
            AssetPositionShareSaveAlert(
                title: L10n.AssetPositionShare.photoAccessRestrictedTitle(locale: locale),
                message: L10n.AssetPositionShare.photoAccessRestrictedMessage(locale: locale),
                showsSettingsButton: false
            )
        default:
            AssetPositionShareSaveAlert(
                title: L10n.AssetPositionShare.photoAccessNeededTitle(locale: locale),
                message: L10n.AssetPositionShare.photoAccessNeededMessage(locale: locale),
                showsSettingsButton: false
            )
        }
    }
}

private enum AssetPositionShareSaveError: LocalizedError {
    case failed

    var errorDescription: String? {
        L10n.AssetPositionShare.saveFailed(locale: AppLocale.current)
    }
}

private struct AssetPositionShareImage: Transferable {
    let pngData: Data

    init?(image: UIImage) {
        guard let pngData = image.pngData() else {
            return nil
        }

        self.pngData = pngData
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            image.pngData
        }
    }
}

private struct AssetPositionShareButtonLabel: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool

    var body: some View {
        label
            .modifier(AssetPositionShareGlassButton(isEnabled: isEnabled))
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(isEnabled ? AppTheme.ColorToken.brand : Color(.secondaryLabel))
            .contentShape(Capsule())
    }
}

private struct AssetPositionShareGlassButton: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isEnabled {
                content
                    .glassEffect(
                        .regular.tint(AppTheme.ColorToken.brand.opacity(0.24)).interactive(),
                        in: .capsule
                    )
            } else {
                content
                    .glassEffect(
                        .regular.tint(Color.white.opacity(0.10)),
                        in: .capsule
                    )
            }
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(fallbackStrokeColor)
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        }
    }

    private var fallbackStrokeColor: Color {
        colorScheme == .light ? Color.black.opacity(0.10) : Color.white.opacity(0.16)
    }
}

private struct AssetPositionShareCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: AssetPositionSharePayload
    let locale: Locale

    private var intradayPerformance: AssetPositionSharePerformance {
        AssetPositionSharePerformance.intraday(position: payload.position)
    }

    private var isPositive: Bool {
        intradayPerformance.isPositive
    }

    private var tint: Color {
        isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    private var style: AssetPositionShareCardStyle {
        AssetPositionShareCardStyle(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: style.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            AssetPositionShareTrendBackground(
                isPositive: isPositive,
                tint: tint,
                highlight: style.trendHighlight,
                strokeOpacity: style.trendStrokeOpacity,
                highlightOpacity: style.trendHighlightOpacity
            )
                .opacity(style.trendLayerOpacity)
                .padding(34)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(payload.symbol)
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .monospaced()
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)

                    if payload.exchange != AppFormatter.placeholder {
                        Text(payload.exchange)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(style.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)
                }

                Text(payload.displayName)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(2)
                    .padding(.top, 8)

                Spacer(minLength: 26)

                Text(AppFormatter.signedPercent(intradayPerformance.percent, fractionLength: 2))
                    .font(.system(size: 86, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                HStack(spacing: 8) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 20, weight: .black))

                    Text(AppFormatter.signedMoney(intradayPerformance.amount))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.top, 6)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    AssetPositionSharePriceMetric(
                        title: L10n.AssetPositionShare.entryPrice(locale: locale),
                        value: AppFormatter.money(payload.position.averageEntryPrice),
                        style: style
                    )

                    AssetPositionSharePriceMetric(
                        title: L10n.AssetPositionShare.latestPrice(locale: locale),
                        value: AppFormatter.money(payload.position.currentPrice),
                        style: style
                    )
                }

                HStack {
                    Text("@Vicu")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ColorToken.brand)

                    Spacer()

                    Text(Date.now.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(style.tertiaryText)
                }
                .padding(.top, 28)
            }
            .padding(42)
        }
    }
}

private struct AssetPositionShareCardStyle {
    let backgroundColors: [Color]
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let metricTitleText: Color
    let metricBackground: Color
    let metricBorder: Color
    let trendHighlight: Color
    let trendStrokeOpacity: Double
    let trendHighlightOpacity: Double
    let trendLayerOpacity: Double

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .light:
            self.init(
                backgroundColors: [
                    Color(red: 0.992, green: 0.992, blue: 0.980),
                    Color(red: 0.942, green: 0.965, blue: 0.952),
                    Color(red: 0.984, green: 0.972, blue: 0.918)
                ],
                primaryText: Color(red: 0.055, green: 0.060, blue: 0.064),
                secondaryText: Color(red: 0.260, green: 0.278, blue: 0.286),
                tertiaryText: Color(red: 0.415, green: 0.426, blue: 0.440),
                metricTitleText: Color(red: 0.405, green: 0.420, blue: 0.430),
                metricBackground: Color.white.opacity(0.72),
                metricBorder: Color.black.opacity(0.08),
                trendHighlight: Color.white,
                trendStrokeOpacity: 0.30,
                trendHighlightOpacity: 0.46,
                trendLayerOpacity: 0.48
            )
        case .dark:
            self.init(
                backgroundColors: [
                    Color.black,
                    Color(red: 0.055, green: 0.055, blue: 0.065),
                    Color.black
                ],
                primaryText: .white,
                secondaryText: .white.opacity(0.82),
                tertiaryText: .white.opacity(0.46),
                metricTitleText: .white.opacity(0.54),
                metricBackground: .white.opacity(0.10),
                metricBorder: .white.opacity(0),
                trendHighlight: .white,
                trendStrokeOpacity: 0.38,
                trendHighlightOpacity: 0.14,
                trendLayerOpacity: 0.56
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
        trendHighlight: Color,
        trendStrokeOpacity: Double,
        trendHighlightOpacity: Double,
        trendLayerOpacity: Double
    ) {
        self.backgroundColors = backgroundColors
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.metricTitleText = metricTitleText
        self.metricBackground = metricBackground
        self.metricBorder = metricBorder
        self.trendHighlight = trendHighlight
        self.trendStrokeOpacity = trendStrokeOpacity
        self.trendHighlightOpacity = trendHighlightOpacity
        self.trendLayerOpacity = trendLayerOpacity
    }
}

private struct AssetPositionSharePerformance {
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

private struct AssetPositionSharePriceMetric: View {
    let title: String
    let value: String
    let style: AssetPositionShareCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(style.metricTitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(style.metricBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style.metricBorder)
        }
    }
}

private struct AssetPositionShareTrendBackground: View {
    let isPositive: Bool
    let tint: Color
    let highlight: Color
    let strokeOpacity: Double
    let highlightOpacity: Double

    var body: some View {
        Canvas { context, size in
            let points = Self.trendPoints(isPositive: isPositive, in: size)
            guard let first = points.first, let last = points.last, points.count > 1 else {
                return
            }

            var trendPath = Path()
            trendPath.move(to: first)
            points.dropFirst().forEach { trendPath.addLine(to: $0) }

            context.stroke(
                trendPath,
                with: .color(tint.opacity(strokeOpacity)),
                style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                trendPath,
                with: .color(highlight.opacity(highlightOpacity)),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )

            let previous = points[points.count - 2]
            let angle = atan2(last.y - previous.y, last.x - previous.x)
            let headLength: CGFloat = 52
            let spread = CGFloat.pi / 7

            var arrowHead = Path()
            arrowHead.move(to: last)
            arrowHead.addLine(
                to: CGPoint(
                    x: last.x - cos(angle - spread) * headLength,
                    y: last.y - sin(angle - spread) * headLength
                )
            )
            arrowHead.move(to: last)
            arrowHead.addLine(
                to: CGPoint(
                    x: last.x - cos(angle + spread) * headLength,
                    y: last.y - sin(angle + spread) * headLength
                )
            )

            context.stroke(
                arrowHead,
                with: .color(tint.opacity(strokeOpacity + 0.14)),
                style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
            )
        }
        .blur(radius: 0.2)
    }

    private static func trendPoints(isPositive: Bool, in size: CGSize) -> [CGPoint] {
        let wave: [CGFloat] = [0.10, -0.06, 0.14, -0.10, 0.05, -0.03, 0.09, -0.04]
        let startY: CGFloat = isPositive ? 0.74 : 0.26
        let endY: CGFloat = isPositive ? 0.22 : 0.78

        return wave.enumerated().map { index, offset in
            let progress = CGFloat(index) / CGFloat(max(wave.count - 1, 1))
            let y = startY + (endY - startY) * progress + offset
            return CGPoint(
                x: size.width * (0.08 + 0.84 * progress),
                y: size.height * y
            )
        }
    }
}
