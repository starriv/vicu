import SwiftUI

struct AppSettingsIconBadge: View {
    let systemImage: String
    let color: Color
    var symbolColor: Color = .white

    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 15

    private var clampedBadgeSize: CGFloat {
        min(max(badgeSize, 28), 38)
    }

    private var clampedIconSize: CGFloat {
        min(max(iconSize, 14), 20)
    }

    var body: some View {
        let cornerRadius = clampedBadgeSize * 0.28

        Image(systemName: systemImage)
            .font(.system(size: clampedIconSize, weight: .semibold))
            .foregroundStyle(symbolColor)
            .frame(width: clampedBadgeSize, height: clampedBadgeSize)
            .background(
                color.gradient,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

struct AppSettingsCompactBadge: View {
    let systemImage: String
    let color: Color

    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 13

    private var clampedBadgeSize: CGFloat {
        min(max(badgeSize, 24), 34)
    }

    private var clampedIconSize: CGFloat {
        min(max(iconSize, 12), 18)
    }

    var body: some View {
        let cornerRadius = clampedBadgeSize * 0.28

        Image(systemName: systemImage)
            .font(.system(size: clampedIconSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: clampedBadgeSize, height: clampedBadgeSize)
            .background(
                color.opacity(0.14),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

struct AppSettingsStatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .strokeBorder(color.opacity(0.28), lineWidth: 2)
                    .padding(-1.5)
            }
            .accessibilityHidden(true)
    }
}

struct AppSettingsRow: View {
    let title: LocalizedStringKey
    let subtitle: String?
    let detail: String?
    let detailColor: Color
    let detailDotColor: Color?
    let systemImage: String
    let badgeColor: Color

    init(
        title: LocalizedStringKey,
        subtitle: String? = nil,
        detail: String? = nil,
        detailColor: Color = .secondary,
        detailDotColor: Color? = nil,
        systemImage: String,
        badgeColor: Color
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.detailColor = detailColor
        self.detailDotColor = detailDotColor
        self.systemImage = systemImage
        self.badgeColor = badgeColor
    }

    var body: some View {
        HStack(spacing: 12) {
            AppSettingsIconBadge(systemImage: systemImage, color: badgeColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTypography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let detail, !detail.isEmpty {
                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    if let detailDotColor {
                        AppSettingsStatusDot(color: detailDotColor, size: 7)
                    }

                    Text(detail)
                        .font(AppTypography.rowMeta)
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct AppSettingsLinkRow: View {
    let title: LocalizedStringKey
    let destination: URL
    let systemImage: String
    let badgeColor: Color

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                AppSettingsIconBadge(systemImage: systemImage, color: badgeColor)

                Text(title)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }
}

enum AppVersionInfo {
    static var formattedVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
                buildNumber?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "1.0"
        }
    }
}
