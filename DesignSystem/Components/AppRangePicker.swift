import SwiftUI

enum AppRangePickerLayout {
    case fill
    case compact

    var spacing: CGFloat {
        switch self {
        case .fill:
            7
        case .compact:
            8
        }
    }

    var height: CGFloat {
        switch self {
        case .fill:
            36
        case .compact:
            30
        }
    }

    var fixedWidth: CGFloat? {
        switch self {
        case .fill:
            nil
        case .compact:
            42
        }
    }

    var maxWidth: CGFloat? {
        switch self {
        case .fill:
            .infinity
        case .compact:
            nil
        }
    }

    var font: Font {
        switch self {
        case .fill:
            AppTypography.control
        case .compact:
            .footnote.weight(.semibold)
        }
    }
}

struct AppRangePicker<Option: Identifiable & Equatable>: View {
    let options: [Option]
    let selection: Option
    let layout: AppRangePickerLayout
    let isDisabled: Bool
    let title: (Option) -> String
    let accessibilityLabel: (Option) -> String
    let select: (Option) -> Void

    init(
        options: [Option],
        selection: Option,
        layout: AppRangePickerLayout = .fill,
        isDisabled: Bool = false,
        title: @escaping (Option) -> String,
        accessibilityLabel: ((Option) -> String)? = nil,
        select: @escaping (Option) -> Void
    ) {
        self.options = options
        self.selection = selection
        self.layout = layout
        self.isDisabled = isDisabled
        self.title = title
        self.accessibilityLabel = accessibilityLabel ?? title
        self.select = select
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: layout.spacing) {
                buttons(usesGlass: true)
            }
        } else {
            buttons(usesGlass: false)
        }
    }

    private func buttons(usesGlass: Bool) -> some View {
        HStack(spacing: layout.spacing) {
            ForEach(options) { option in
                button(for: option, usesGlass: usesGlass)
            }
        }
        .opacity(isDisabled ? 0.58 : 1)
        .animation(.snappy(duration: 0.16), value: selection.id)
    }

    @ViewBuilder
    private func button(for option: Option, usesGlass: Bool) -> some View {
        let isSelected = selection == option
        let button = Button {
            select(option)
        } label: {
            Text(title(option))
                .font(layout.font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: layout.fixedWidth, height: layout.height)
                .frame(maxWidth: layout.maxWidth)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AppTheme.ColorToken.brand : .secondary)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel(option))

        if usesGlass {
            if #available(iOS 26.0, *) {
                button
                    .glassEffect(
                        .regular.tint(glassTint(isSelected: isSelected)).interactive(),
                        in: .capsule
                    )
            } else {
                button
            }
        } else {
            button
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(isSelected ? 0.18 : 0.08))
                }
        }
    }

    private func glassTint(isSelected: Bool) -> Color {
        isSelected ? AppTheme.ColorToken.brand.opacity(0.18) : Color.white.opacity(0.08)
    }
}
