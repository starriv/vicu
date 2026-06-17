import SwiftUI

enum AppEmptyStateStyle {
    case card
    case inline
}

enum AppEmptyStateMetrics {
    static let cardMinHeight: CGFloat = 320
}

struct AppEmptyStateView<Action: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let systemImage: String
    var style: AppEmptyStateStyle = .card
    var minHeight: CGFloat = AppEmptyStateMetrics.cardMinHeight
    var iconTint: Color = AppTheme.ColorToken.icon
    @ViewBuilder let action: Action

    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        systemImage: String,
        style: AppEmptyStateStyle = .card,
        minHeight: CGFloat = AppEmptyStateMetrics.cardMinHeight,
        iconTint: Color = AppTheme.ColorToken.icon,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.style = style
        self.minHeight = minHeight
        self.iconTint = iconTint
        self.action = action()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: style == .card ? minHeight : nil)
            .background {
                if style == .card {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous)
                        .fill(AppTheme.ColorToken.groupedSurface)
                }
            }
            .accessibilityElement(children: .combine)
    }

    private var content: some View {
        VStack(spacing: 12) {
            icon

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(AppTypography.description)
                        .foregroundStyle(.secondary)
                        .lineSpacing(AppTypography.secondaryLineSpacing)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            action
        }
        .frame(maxWidth: 330)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(iconTint)
            .frame(width: iconFrame, height: iconFrame)
            .background(iconBackground, in: Circle())
    }

    private var iconBackground: Color {
        switch style {
        case .card:
            iconTint.opacity(0.14)
        case .inline:
            Color.clear
        }
    }

    private var iconSize: CGFloat {
        switch style {
        case .card:
            24
        case .inline:
            20
        }
    }

    private var iconFrame: CGFloat {
        switch style {
        case .card:
            48
        case .inline:
            28
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .card:
            24
        case .inline:
            18
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .card:
            26
        case .inline:
            18
        }
    }
}

extension AppEmptyStateView where Action == EmptyView {
    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        systemImage: String,
        style: AppEmptyStateStyle = .card,
        minHeight: CGFloat = AppEmptyStateMetrics.cardMinHeight,
        iconTint: Color = AppTheme.ColorToken.icon
    ) {
        self.init(
            title: title,
            message: message,
            systemImage: systemImage,
            style: style,
            minHeight: minHeight,
            iconTint: iconTint
        ) {
            EmptyView()
        }
    }
}

struct AppEmptyStateActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String?

    init(_ title: LocalizedStringKey, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(AppTypography.control)
        .foregroundStyle(AppTheme.ColorToken.brandForeground)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(AppTheme.ColorToken.brand, in: Capsule())
        .padding(.top, 2)
    }
}
