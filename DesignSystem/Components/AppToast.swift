import Observation
import SwiftUI

enum AppToastTone: Equatable {
    case success
    case error
    case warning
}

struct AppToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let systemImage: String
    let tone: AppToastTone
}

@MainActor
@Observable
final class AppToastCenter {
    var toast: AppToastMessage?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(
        _ message: String,
        systemImage: String = "checkmark.circle.fill",
        tone: AppToastTone = .success,
        duration: Duration = .seconds(1.7)
    ) {
        dismissTask?.cancel()
        toast = AppToastMessage(message: message, systemImage: systemImage, tone: tone)

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else {
                return
            }
            toast = nil
        }
    }
}

struct AppToastOverlay: View {
    @Environment(AppToastCenter.self) private var toastCenter

    var body: some View {
        VStack {
            if let toast = toastCenter.toast {
                AppToastCapsule(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: toastCenter.toast)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .allowsHitTesting(false)
    }
}

private struct AppToastCapsule: View {
    let toast: AppToastMessage

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.14)), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(0.16))
                }
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(iconTint)

            Text(toast.message)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private var iconTint: Color {
        switch toast.tone {
        case .success:
            AppTheme.ColorToken.positive
        case .error:
            AppTheme.ColorToken.negative
        case .warning:
            AppTheme.ColorToken.warning
        }
    }
}
