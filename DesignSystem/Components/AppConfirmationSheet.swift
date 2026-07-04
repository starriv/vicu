import SwiftUI

struct AppConfirmationSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let title: String
    let isSubmitting: Bool
    let detents: Set<PresentationDetent>
    let contentSpacing: CGFloat
    let contentBottomPadding: CGFloat
    let content: () -> Content

    init(
        title: String,
        isSubmitting: Bool,
        detents: Set<PresentationDetent> = [.large],
        contentSpacing: CGFloat = 16,
        contentBottomPadding: CGFloat = AppTheme.Spacing.pageBottom,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isSubmitting = isSubmitting
        self.detents = detents
        self.contentSpacing = contentSpacing
        self.contentBottomPadding = contentBottomPadding
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    content()
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, 8)
                .padding(.bottom, contentBottomPadding)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .presentationDetents(detents)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 58, height: 5)
                .padding(.top, 10)

            HStack {
                Button(L10n.Common.cancelText(locale: locale)) {
                    dismiss()
                }
                .font(AppTypography.control)
                .foregroundStyle(.secondary)
                .disabled(isSubmitting)

                Spacer(minLength: 12)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 12)

                Color.clear
                    .frame(width: 52, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

struct AppConfirmationActionButton: View {
    let title: String
    let submittingTitle: String
    let tint: Color
    let isSubmitting: Bool
    var accessibilityTitle: String? = nil
    let action: () async -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            glassButton
        } else {
            fallbackButton
        }
    }

    @available(iOS 26.0, *)
    private var glassButton: some View {
        Button {
            Task { await action() }
        } label: {
            label(foregroundColor: .white, progressTint: .white)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(tint)
        .disabled(isSubmitting)
        .accessibilityLabel(isSubmitting ? submittingTitle : (accessibilityTitle ?? title))
    }

    private var fallbackButton: some View {
        Button {
            Task { await action() }
        } label: {
            label(foregroundColor: tint, progressTint: tint)
        }
        .buttonStyle(.plain)
        .background(tint.opacity(isSubmitting ? 0.06 : 0.10), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(isSubmitting ? 0.18 : 0.34), lineWidth: 0.75)
        }
        .shadow(color: tint.opacity(0.12), radius: 18, y: 7)
        .disabled(isSubmitting)
        .accessibilityLabel(isSubmitting ? submittingTitle : (accessibilityTitle ?? title))
    }

    private func label(foregroundColor: Color, progressTint: Color) -> some View {
        ZStack {
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .opacity(isSubmitting ? 0 : 1)

            if isSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(progressTint)

                    Text(submittingTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(Capsule())
    }
}

struct AppConfirmationInfoItem {
    let title: Text
    let value: String
    var tint: Color

    init(title: LocalizedStringKey, value: String, tint: Color = .primary) {
        self.title = Text(title)
        self.value = value
        self.tint = tint
    }

    init(title: String, value: String, tint: Color = .primary) {
        self.title = Text(title)
        self.value = value
        self.tint = tint
    }
}

struct AppConfirmationInfoRow: View {
    let item: AppConfirmationInfoItem

    var body: some View {
        LabeledContent {
            Text(item.value)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        } label: {
            item.title
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
    }
}

struct AppConfirmationWarningRow: View {
    let message: String
    var systemImage = "exclamationmark.circle.fill"
    var tint = AppTheme.ColorToken.warning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)

            Text(message)
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    func appConfirmationCard(
        padding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
        cornerRadius: CGFloat = AppTheme.CornerRadius.groupedSurface
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.ColorToken.groupedSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}
