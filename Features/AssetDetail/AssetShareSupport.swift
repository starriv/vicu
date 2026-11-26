import CoreTransferable
import Photos
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AssetRenderedShareImage {
    let image: UIImage
    let pngData: Data

    init?(image: UIImage) {
        guard let pngData = image.pngData() else {
            return nil
        }

        self.image = image
        self.pngData = pngData
    }
}

enum AssetSharePhotoLibraryWriter {
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
                    continuation.resume(throwing: AssetShareSaveError.failed)
                }
            }
        }
    }
}

struct AssetShareSaveAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let showsSettingsButton: Bool

    static func photoAuthorization(status: PHAuthorizationStatus, locale: Locale) -> AssetShareSaveAlert {
        switch status {
        case .denied:
            AssetShareSaveAlert(
                title: L10n.AssetPositionShare.photoAccessOffTitle(locale: locale),
                message: L10n.AssetPositionShare.photoAccessOffMessage(locale: locale),
                showsSettingsButton: true
            )
        case .restricted:
            AssetShareSaveAlert(
                title: L10n.AssetPositionShare.photoAccessRestrictedTitle(locale: locale),
                message: L10n.AssetPositionShare.photoAccessRestrictedMessage(locale: locale),
                showsSettingsButton: false
            )
        default:
            AssetShareSaveAlert(
                title: L10n.AssetPositionShare.photoAccessNeededTitle(locale: locale),
                message: L10n.AssetPositionShare.photoAccessNeededMessage(locale: locale),
                showsSettingsButton: false
            )
        }
    }
}

enum AssetShareSaveError: LocalizedError {
    case failed

    var errorDescription: String? {
        L10n.AssetPositionShare.saveFailed(locale: AppLocale.current)
    }
}

struct AssetShareImage: Transferable {
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            image.pngData
        }
    }
}

struct AssetShareButtonLabel: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool

    var body: some View {
        label
            .modifier(AssetShareGlassButton(isEnabled: isEnabled))
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

struct AssetShareGlassButton: ViewModifier {
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

struct ShareCardStyle {
    let backgroundColors: [Color]
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let badgeText: Color
    let badgeBackground: Color
    let pillBackground: Color
    let metricTitleText: Color
    let metricBackground: Color
    let metricBorder: Color
    let divider: Color
    let ambientGlowOpacity: Double
    let dotGridColor: Color
    let dotGridOpacity: Double
    let chartGrid: Color
    let chartHighlight: Color
    let chartFillOpacity: Double

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .light:
            self.init(
                backgroundColors: [
                    Color(red: 0.992, green: 0.993, blue: 0.996),
                    Color(red: 0.957, green: 0.961, blue: 0.969)
                ],
                primaryText: Color(red: 0.060, green: 0.065, blue: 0.075),
                secondaryText: Color(red: 0.310, green: 0.330, blue: 0.360),
                tertiaryText: Color(red: 0.480, green: 0.500, blue: 0.530),
                badgeText: Color(red: 0.250, green: 0.270, blue: 0.300),
                badgeBackground: Color.black.opacity(0.055),
                pillBackground: Color.white.opacity(0.76),
                metricTitleText: Color(red: 0.450, green: 0.470, blue: 0.505),
                metricBackground: Color.white.opacity(0.78),
                metricBorder: Color.black.opacity(0.065),
                divider: Color.black.opacity(0.075),
                ambientGlowOpacity: 0.085,
                dotGridColor: Color.black,
                dotGridOpacity: 0.055,
                chartGrid: Color.black.opacity(0.055),
                chartHighlight: Color.white.opacity(0.82),
                chartFillOpacity: 0.16
            )
        case .dark:
            self.init(
                backgroundColors: [
                    Color(red: 0.072, green: 0.076, blue: 0.086),
                    Color(red: 0.024, green: 0.026, blue: 0.032)
                ],
                primaryText: .white,
                secondaryText: .white.opacity(0.76),
                tertiaryText: .white.opacity(0.42),
                badgeText: .white.opacity(0.76),
                badgeBackground: .white.opacity(0.09),
                pillBackground: .white.opacity(0.075),
                metricTitleText: .white.opacity(0.48),
                metricBackground: .white.opacity(0.065),
                metricBorder: .white.opacity(0.085),
                divider: .white.opacity(0.09),
                ambientGlowOpacity: 0.14,
                dotGridColor: .white,
                dotGridOpacity: 0.07,
                chartGrid: .white.opacity(0.055),
                chartHighlight: .white.opacity(0.22),
                chartFillOpacity: 0.18
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
        pillBackground: Color,
        metricTitleText: Color,
        metricBackground: Color,
        metricBorder: Color,
        divider: Color,
        ambientGlowOpacity: Double,
        dotGridColor: Color,
        dotGridOpacity: Double,
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
        self.pillBackground = pillBackground
        self.metricTitleText = metricTitleText
        self.metricBackground = metricBackground
        self.metricBorder = metricBorder
        self.divider = divider
        self.ambientGlowOpacity = ambientGlowOpacity
        self.dotGridColor = dotGridColor
        self.dotGridOpacity = dotGridOpacity
        self.chartGrid = chartGrid
        self.chartHighlight = chartHighlight
        self.chartFillOpacity = chartFillOpacity
    }
}

struct ShareCardBackground: View {
    let accentTint: Color
    let style: ShareCardStyle

    var body: some View {
        ZStack {
            LinearGradient(
                colors: style.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    accentTint.opacity(style.ambientGlowOpacity),
                    accentTint.opacity(style.ambientGlowOpacity * 0.32),
                    .clear
                ],
                center: UnitPoint(x: 0.92, y: 0.14),
                startRadius: 10,
                endRadius: 360
            )

            Canvas { context, size in
                let spacing: CGFloat = 24
                let radius: CGFloat = 1.25
                let focal = CGPoint(x: size.width * 0.88, y: size.height * 0.22)
                let maxDistance = hypot(size.width * 0.72, size.height * 0.56)

                var y = spacing * 0.5
                while y < size.height {
                    var x = spacing * 0.5
                    while x < size.width {
                        let distance = hypot(x - focal.x, y - focal.y)
                        let normalized = max(0, 1 - distance / maxDistance)
                        let falloff = normalized * normalized
                        if falloff > 0.02 {
                            let rect = CGRect(
                                x: x - radius,
                                y: y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(style.dotGridColor.opacity(style.dotGridOpacity * falloff))
                            )
                        }
                        x += spacing
                    }
                    y += spacing
                }
            }
        }
    }
}

struct ShareCardFooter: View {
    let timestampText: String
    let style: ShareCardStyle

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Circle()
                    .fill(AppTheme.ColorToken.brand)
                    .frame(width: 8, height: 8)

                Text("@Vicu")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(style.primaryText)
            }

            Spacer()

            Text(timestampText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(style.tertiaryText)
                .lineLimit(1)
        }
    }
}
