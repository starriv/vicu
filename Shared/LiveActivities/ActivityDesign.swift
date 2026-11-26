import SwiftUI

// Shared visual language for every Live Activity card. Values mirror `AppTheme`
// in the app target; duplicated here because the widget extension does not
// compile the app's design system.
enum ActivityDesign {
    static let brand = Color(red: 0.988, green: 0.843, blue: 0.169)
    static let brandInk = Color(red: 0.220, green: 0.259, blue: 0.282)
    static let positive = Color.green
    static let negative = Color.red
    static let warning = Color.orange
    static let info = Color.blue
    static let neutral = Color.secondary

    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 14
    static let progressHeight: CGFloat = 4
}

extension OrderActivityPhase {
    var tint: Color {
        switch self {
        case .submitted, .canceled, .expired, .replaced:
            ActivityDesign.neutral
        case .working:
            ActivityDesign.info
        case .partiallyFilled, .cancelRequested:
            ActivityDesign.warning
        case .filled:
            ActivityDesign.positive
        case .rejected:
            ActivityDesign.negative
        }
    }

    var systemImage: String {
        switch self {
        case .submitted:
            "paperplane.fill"
        case .working:
            "clock.fill"
        case .partiallyFilled:
            "circle.lefthalf.filled"
        case .cancelRequested:
            "hourglass"
        case .filled:
            "checkmark.circle.fill"
        case .canceled:
            "xmark.circle.fill"
        case .rejected:
            "exclamationmark.triangle.fill"
        case .expired:
            "clock.badge.xmark"
        case .replaced:
            "arrow.triangle.2.circlepath"
        }
    }
}

extension OrderActivitySide {
    var tint: Color {
        switch self {
        case .buy:
            ActivityDesign.positive
        case .sell:
            ActivityDesign.negative
        case .other:
            ActivityDesign.neutral
        }
    }
}

// MARK: - Building blocks

/// Subtle monochrome Vicu alpaca glyph used as a lightweight brand anchor on
/// Lock Screen cards and Dynamic Island without competing with primary data.
struct ActivityBrandMark: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var size: CGFloat = 14
    var tint: Color = .secondary

    var body: some View {
        Image("AlpacaTabIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(isLuminanceReduced ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Circular tinted SF Symbol badge used as the leading visual anchor on Lock Screen cards.
struct ActivitySymbolBadge: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let symbol: String
    let tint: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(isLuminanceReduced ? .secondary : tint)
            .widgetAccentable()
            .frame(width: size, height: size)
            .background(
                (isLuminanceReduced ? Color.primary : tint).opacity(0.14),
                in: Circle()
            )
    }
}

/// Minimal 4pt linear progress track for determinate order fills.
struct ActivityProgressBar: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let progress: Double
    let tint: Color
    var height: CGFloat = ActivityDesign.progressHeight

    private var clamped: Double {
        max(0, min(1, progress))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.14))

                if clamped > 0 {
                    Capsule()
                        .fill(isLuminanceReduced ? Color.primary.opacity(0.6) : tint)
                        .widgetAccentable()
                        .frame(width: max(height, clamped * geometry.size.width))
                }
            }
        }
        .frame(height: height)
    }
}

/// Self-updating linear progress bar for the active trading session.
/// Driven by `ProgressView(timerInterval:)`, so it advances smoothly while the app
/// is suspended and aligns 1-to-1 with the session countdown.
struct ActivitySessionProgressBar: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let start: Date
    let end: Date

    private var range: ClosedRange<Date>? {
        guard end > start else {
            return nil
        }

        return min(start, Date())...max(end, Date().addingTimeInterval(1))
    }

    var body: some View {
        if let range {
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(isLuminanceReduced ? Color.primary.opacity(0.6) : ActivityDesign.brand)
            .widgetAccentable()
            .labelsHidden()
            .scaleEffect(x: 1, y: 0.85, anchor: .center)
            .frame(height: ActivityDesign.progressHeight)
        } else {
            ActivityProgressBar(progress: 0, tint: ActivityDesign.brand)
        }
    }
}

/// Countdown that the system keeps ticking on its own. Live Activities cannot be
/// woken in the background, so anything time-based must come from `Text(timerInterval:)`.
struct ActivityCountdownText: View {
    let target: Date
    var showsHours: Bool = true
    var countsDown: Bool = true

    var body: some View {
        if target > Date() {
            Text(
                timerInterval: Date()...target,
                countsDown: countsDown,
                showsHours: showsHours
            )
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: countsDown))
        } else {
            Text("--:--")
                .monospacedDigit()
        }
    }
}

/// Compact translucent capsule action for secondary Live Activity actions (e.g., Cancel).
/// Follows Apple HIG: tapping the card itself handles primary navigation via `.widgetURL`,
/// so inline controls stay lightweight and never dominate the card.
struct ActivityCompactAction: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Minimal circular fill progress ring for Dynamic Island compact trailing.
struct ActivityProgressRing: View {
    let progress: Double
    let tint: Color
    var size: CGFloat = 18

    private var clamped: Double {
        max(0, min(1, progress))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .widgetAccentable()
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
