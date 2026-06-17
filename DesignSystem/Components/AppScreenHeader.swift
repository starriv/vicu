import SwiftUI

struct AppScreenHeader<Leading: View, Center: View, Trailing: View>: View {
    let background: Color
    let showsDivider: Bool
    private let leading: Leading
    private let center: Center
    private let trailing: Trailing

    init(
        background: Color = Color(.systemBackground),
        showsDivider: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.background = background
        self.showsDivider = showsDivider
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            HStack {
                leading

                Spacer(minLength: 12)

                trailing
            }

            center
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal - 8)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(background.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(showsDivider ? 0.16 : 0)
        }
    }
}

extension AppScreenHeader where Trailing == EmptyView {
    init(
        background: Color = Color(.systemBackground),
        showsDivider: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center
    ) {
        self.init(
            background: background,
            showsDivider: showsDivider,
            leading: leading,
            center: center,
            trailing: { EmptyView() }
        )
    }
}

struct AppGlassIconButton: View {
    let systemImage: String
    var foregroundColor: Color = .primary
    var fontSize: CGFloat = 20
    var fontWeight: Font.Weight = .semibold
    var symbolRenderingMode: SymbolRenderingMode?
    var verticalOffset: CGFloat = 0
    var accessibilityLabel: LocalizedStringKey?
    let action: () -> Void

    var body: some View {
        if let accessibilityLabel {
            button
                .accessibilityLabel(accessibilityLabel)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: fontWeight))
                .symbolRenderingMode(symbolRenderingMode)
                .foregroundStyle(foregroundColor)
                .frame(width: 44, height: 44)
                .offset(y: verticalOffset)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(AppGlassCircleModifier())
    }
}

struct AppGlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.10)).interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color(.separator).opacity(0.16))
                }
        }
    }
}
