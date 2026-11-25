import SwiftUI

enum AppRangePickerLayout {
    case fill
    case compact

    var spacing: CGFloat {
        switch self {
        case .fill:
            4
        case .compact:
            2
        }
    }

    var height: CGFloat {
        switch self {
        case .fill:
            34
        case .compact:
            32
        }
    }

    var font: Font {
        switch self {
        case .fill:
            .subheadline.weight(.semibold)
        case .compact:
            .footnote.weight(.semibold)
        }
    }
}

/// OKX-inspired minimalist range selector:
/// unselected periods render as clean borderless typography, while the active period
/// slides smoothly with a single subtle capsule pill.
struct AppRangePicker<Option: Identifiable & Equatable>: View {
    let options: [Option]
    let selection: Option
    let layout: AppRangePickerLayout
    let isDisabled: Bool
    let title: (Option) -> String
    let accessibilityLabel: (Option) -> String
    let select: (Option) -> Void

    @Namespace private var pillNamespace

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
        HStack(spacing: layout.spacing) {
            ForEach(options) { option in
                button(for: option)
            }
        }
        .opacity(isDisabled ? 0.55 : 1)
        .animation(.snappy(duration: 0.22, extraBounce: 0.04), value: selection.id)
    }

    private func button(for option: Option) -> some View {
        let isSelected = selection == option

        return Button {
            select(option)
        } label: {
            Text(title(option))
                .font(layout.font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.primary : Color(.secondaryLabel))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: layout.height)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(.secondarySystemFill))
                            .matchedGeometryEffect(id: "app-range-picker-pill", in: pillNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel(option))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
