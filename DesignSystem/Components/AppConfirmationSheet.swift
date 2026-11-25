import SwiftUI

struct AppSheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var isDisabled: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close) {
                performDismiss()
            }
            .disabled(isDisabled)
        } else {
            Button {
                performDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(L10n.Common.close)
            .disabled(isDisabled)
        }
    }

    private func performDismiss() {
        if let action {
            action()
        } else {
            dismiss()
        }
    }
}

struct AppSheetDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.18))
            .frame(height: 0.5)
    }
}

struct AppSheetBadgePill: View {
    let title: String
    let tint: Color
    var horizontalPadding: CGFloat = 12
    var backgroundOpacity: Double = 0.13

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(height: 26)
            .background(tint.opacity(backgroundOpacity), in: Capsule())
    }
}

struct AppSheetInfoItem {
    let title: Text
    let value: String
    var tint: Color
    var isMonospaced: Bool
    var showsStatusDot: Bool

    init(
        title: LocalizedStringKey,
        value: String,
        tint: Color = .primary,
        isMonospaced: Bool = false,
        showsStatusDot: Bool = false
    ) {
        self.title = Text(title)
        self.value = value
        self.tint = tint
        self.isMonospaced = isMonospaced
        self.showsStatusDot = showsStatusDot
    }

    init(
        title: String,
        value: String,
        tint: Color = .primary,
        isMonospaced: Bool = false,
        showsStatusDot: Bool = false
    ) {
        self.title = Text(title)
        self.value = value
        self.tint = tint
        self.isMonospaced = isMonospaced
        self.showsStatusDot = showsStatusDot
    }
}

struct AppSheetInfoRow: View {
    let item: AppSheetInfoItem

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                if item.showsStatusDot {
                    Circle()
                        .fill(item.tint)
                        .frame(width: 7, height: 7)
                }

                Text(item.value)
                    .font(valueFont)
                    .foregroundStyle(item.showsStatusDot ? .primary : item.tint)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        } label: {
            item.title
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 13)
    }

    private var valueFont: Font {
        if item.isMonospaced {
            return .subheadline.weight(.semibold).monospaced()
        }
        return .subheadline.weight(.semibold).monospacedDigit()
    }
}

struct AppSheetInfoCard: View {
    let items: [AppSheetInfoItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                AppSheetInfoRow(item: items[index])

                if index < items.count - 1 {
                    AppSheetDivider()
                }
            }
        }
        .appSheetCard(horizontalPadding: 18, verticalPadding: 4)
    }
}

struct AppSheetWarningBanner: View {
    let messages: [String]
    var systemImage: String = "exclamationmark.circle.fill"
    var tint: Color = AppTheme.ColorToken.warning

    init(message: String, systemImage: String = "exclamationmark.circle.fill", tint: Color = AppTheme.ColorToken.warning) {
        self.messages = [message]
        self.systemImage = systemImage
        self.tint = tint
    }

    init(messages: [String], systemImage: String = "exclamationmark.circle.fill", tint: Color = AppTheme.ColorToken.warning) {
        self.messages = messages
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages, id: \.self) { message in
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tint.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.24), lineWidth: 0.75)
        }
    }
}

struct AppSheetActionButton: View {
    let titleText: Text
    var accessibilityTitle: Text? = nil
    var submittingTitle: Text? = nil
    let tint: Color
    var isEnabled: Bool = true
    var isSubmitting: Bool = false
    let action: () async -> Void

    init(
        title: String,
        accessibilityTitle: String? = nil,
        submittingTitle: String? = nil,
        tint: Color,
        isEnabled: Bool = true,
        isSubmitting: Bool = false,
        action: @escaping () async -> Void
    ) {
        self.titleText = Text(title)
        self.accessibilityTitle = accessibilityTitle.map { Text($0) }
        self.submittingTitle = submittingTitle.map { Text($0) }
        self.tint = tint
        self.isEnabled = isEnabled
        self.isSubmitting = isSubmitting
        self.action = action
    }

    init(
        title: LocalizedStringKey,
        accessibilityTitle: LocalizedStringKey? = nil,
        submittingTitle: String? = nil,
        tint: Color,
        isEnabled: Bool = true,
        isSubmitting: Bool = false,
        action: @escaping () async -> Void
    ) {
        self.titleText = Text(title)
        self.accessibilityTitle = accessibilityTitle.map { Text($0) }
        self.submittingTitle = submittingTitle.map { Text($0) }
        self.tint = tint
        self.isEnabled = isEnabled
        self.isSubmitting = isSubmitting
        self.action = action
    }

    private var canInteract: Bool {
        isEnabled && !isSubmitting
    }

    var body: some View {
        Button {
            guard canInteract else { return }
            Task { await action() }
        } label: {
            ZStack {
                titleText
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .opacity(isSubmitting ? 0 : 1)

                if isSubmitting {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .foregroundStyle(isEnabled ? Color.white : Color(.tertiaryLabel))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isEnabled ? tint : Color(.tertiarySystemFill),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(AppSheetPressButtonStyle())
        .disabled(!canInteract)
        .accessibilityLabel(isSubmitting ? (submittingTitle ?? titleText) : (accessibilityTitle ?? titleText))
    }
}

struct AppSheetPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct AppActionSheetContainer<Content: View>: View {
    let title: Text
    var isSubmitting: Bool = false
    var minHeight: CGFloat = 380
    var maxHeight: CGFloat = 720
    var fallbackHeight: CGFloat = 460
    var allowsLargeDetent: Bool = false
    var navBarAllowance: CGFloat = 68
    let content: () -> Content

    @State private var measuredContentHeight: CGFloat?

    init(
        title: String,
        isSubmitting: Bool = false,
        minHeight: CGFloat = 380,
        maxHeight: CGFloat = 720,
        fallbackHeight: CGFloat = 460,
        allowsLargeDetent: Bool = false,
        navBarAllowance: CGFloat = 68,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = Text(title)
        self.isSubmitting = isSubmitting
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.fallbackHeight = fallbackHeight
        self.allowsLargeDetent = allowsLargeDetent
        self.navBarAllowance = navBarAllowance
        self.content = content
    }

    init(
        title: LocalizedStringKey,
        isSubmitting: Bool = false,
        minHeight: CGFloat = 380,
        maxHeight: CGFloat = 720,
        fallbackHeight: CGFloat = 460,
        allowsLargeDetent: Bool = false,
        navBarAllowance: CGFloat = 68,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = Text(title)
        self.isSubmitting = isSubmitting
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.fallbackHeight = fallbackHeight
        self.allowsLargeDetent = allowsLargeDetent
        self.navBarAllowance = navBarAllowance
        self.content = content
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                content()
                    .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { _, height in
                        let rounded = ceil(height)
                        if rounded > 0, measuredContentHeight != rounded {
                            measuredContentHeight = rounded
                        }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppSheetCloseButton(isDisabled: isSubmitting)
                }
            }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var resolvedSheetHeight: CGFloat {
        let target = (measuredContentHeight.map { $0 + navBarAllowance }) ?? fallbackHeight
        return min(max(target, minHeight), maxHeight)
    }

    private var detents: Set<PresentationDetent> {
        if allowsLargeDetent {
            return [.height(resolvedSheetHeight), .large]
        }
        return [.height(resolvedSheetHeight)]
    }
}

extension View {
    func appSheetCard(
        horizontalPadding: CGFloat = 18,
        verticalPadding: CGFloat = 14,
        cornerRadius: CGFloat = 20
    ) -> some View {
        self
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.ColorToken.groupedSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.12), lineWidth: 0.75)
            }
    }
}
