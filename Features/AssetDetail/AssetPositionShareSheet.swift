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
    @Environment(\.dismiss) private var dismiss
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
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Share position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                shareActionBar
            }
            .task(id: payload.id) {
                renderShareImage()
            }
            .alert(item: $saveAlert) { alert in
                if alert.showsSettingsButton {
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        primaryButton: .default(Text("Open Settings")) {
                            openAppSettings()
                        },
                        secondaryButton: .cancel()
                    )
                } else {
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
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
                .accessibilityLabel("Position share preview")
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
    private var shareActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.4)

            if let renderedImage, let shareItem = AssetPositionShareImage(image: renderedImage) {
                HStack(spacing: 12) {
                    Button {
                        saveImage(renderedImage)
                    } label: {
                        AssetPositionShareButtonLabel(
                            title: isSavingImage ? "Saving" : didSaveImage ? "Saved" : "Save",
                            systemImage: didSaveImage ? "checkmark" : "square.and.arrow.down",
                            isEnabled: !isSavingImage
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingImage)

                    ShareLink(
                        item: shareItem,
                        preview: SharePreview(
                            "\(payload.symbol) position",
                            image: Image(uiImage: renderedImage)
                        )
                    ) {
                        AssetPositionShareButtonLabel(
                            title: "Share",
                            systemImage: "square.and.arrow.up",
                            isEnabled: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                AssetPositionShareButtonLabel(
                    title: "Preparing image",
                    systemImage: "photo",
                    isEnabled: false
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.thinMaterial)
    }

    @MainActor
    private func renderShareImage() {
        let content = AssetPositionShareCard(payload: payload)
            .frame(width: 540, height: 675)

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
            saveAlert = AssetPositionShareSaveAlert(
                title: "Save failed",
                message: "The image could not be prepared for Photos.",
                showsSettingsButton: false
            )
            return
        }

        let authorizationStatus = await AssetPositionPhotoLibraryWriter.requestAddAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            saveAlert = .photoAuthorization(status: authorizationStatus)
            return
        }

        do {
            try await AssetPositionPhotoLibraryWriter.writePNGData(imageData)
            didSaveImage = true
        } catch {
            saveAlert = AssetPositionShareSaveAlert(
                title: "Save failed",
                message: error.localizedDescription,
                showsSettingsButton: false
            )
        }
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

    static func photoAuthorization(status: PHAuthorizationStatus) -> AssetPositionShareSaveAlert {
        switch status {
        case .denied:
            AssetPositionShareSaveAlert(
                title: "Photo access is off",
                message: "Open Settings and allow vicu to add images to Photos, then try saving again.",
                showsSettingsButton: true
            )
        case .restricted:
            AssetPositionShareSaveAlert(
                title: "Photo access restricted",
                message: "This device does not allow vicu to add images to Photos.",
                showsSettingsButton: false
            )
        default:
            AssetPositionShareSaveAlert(
                title: "Photo access needed",
                message: "Allow vicu to add images to Photos, then try saving again.",
                showsSettingsButton: false
            )
        }
    }
}

private enum AssetPositionShareSaveError: LocalizedError {
    case failed

    var errorDescription: String? {
        "The image could not be saved to Photos."
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
                        .strokeBorder(Color.white.opacity(0.16))
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        }
    }
}

private struct AssetPositionShareCard: View {
    let payload: AssetPositionSharePayload

    private var intradayPerformance: AssetPositionSharePerformance {
        AssetPositionSharePerformance.intraday(position: payload.position)
    }

    private var isPositive: Bool {
        intradayPerformance.isPositive
    }

    private var tint: Color {
        isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.055, green: 0.055, blue: 0.065),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            AssetPositionShareTrendBackground(isPositive: isPositive, tint: tint)
                .opacity(0.56)
                .padding(34)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(payload.symbol)
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .monospaced()
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if payload.exchange != AppFormatter.placeholder {
                        Text(payload.exchange)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)
                }

                Text(payload.displayName)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
                    .padding(.top, 8)

                Spacer(minLength: 26)

                Text(AppFormatter.signedPercent(intradayPerformance.percent, fractionLength: 2))
                    .font(.system(size: 86, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
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
                        title: "Entry price",
                        value: AppFormatter.money(payload.position.averageEntryPrice)
                    )

                    AssetPositionSharePriceMetric(
                        title: "Latest price",
                        value: AppFormatter.money(payload.position.currentPrice)
                    )
                }

                HStack {
                    Text("vicu")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ColorToken.brand)

                    Spacer()

                    Text(Date.now.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.46))
                }
                .padding(.top, 28)
            }
            .padding(42)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct AssetPositionShareTrendBackground: View {
    let isPositive: Bool
    let tint: Color

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
                with: .color(tint.opacity(0.38)),
                style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                trendPath,
                with: .color(.white.opacity(0.14)),
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
                with: .color(tint.opacity(0.52)),
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
