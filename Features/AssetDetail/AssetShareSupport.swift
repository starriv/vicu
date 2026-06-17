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
