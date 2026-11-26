import Observation
import SwiftUI

/// Scoped observable state for scroll-driven chrome visibility so toggling header title or
/// bottom trade bar never invalidates the parent `AssetDetailView`, `ScrollView`, or chart.
@MainActor
@Observable
final class AssetDetailScrollChromeState {
    private static let headerTitleRevealOffset: CGFloat = 56
    private static let headerTitleHideOffset: CGFloat = 18

    private(set) var showsHeaderTitle = false
    private(set) var isTradeBarVisible = true

    @ObservationIgnored private let tradeBarScrollTracker = AssetDetailTradeBarScrollTracker()

    func reset() {
        tradeBarScrollTracker.reset()
        if !isTradeBarVisible {
            isTradeBarVisible = true
        }
    }

    func updateScrollPhase(_ phase: ScrollPhase) {
        tradeBarScrollTracker.updateScrollPhase(phase)
    }

    func update(metrics: AssetDetailScrollMetrics) {
        updateHeaderTitleVisibility(for: Self.headerRevealRegion(for: metrics.rawOffsetY))
        updateTradeBarVisibility(for: metrics)
    }

    private static func headerRevealRegion(for offset: CGFloat) -> AssetDetailHeaderRevealRegion {
        if offset >= headerTitleRevealOffset {
            return .visible
        }

        if offset <= headerTitleHideOffset {
            return .hidden
        }

        return .hold
    }

    private func updateHeaderTitleVisibility(for region: AssetDetailHeaderRevealRegion) {
        let nextValue: Bool?
        switch region {
        case .hidden:
            nextValue = false
        case .hold:
            nextValue = nil
        case .visible:
            nextValue = true
        }

        guard let nextValue, showsHeaderTitle != nextValue else {
            return
        }

        withAnimation(.easeOut(duration: 0.16)) {
            showsHeaderTitle = nextValue
        }
    }

    private func updateTradeBarVisibility(for metrics: AssetDetailScrollMetrics) {
        guard let nextVisible = tradeBarScrollTracker.update(
            offsetY: metrics.normalizedOffsetY,
            maxOffsetY: metrics.maxOffsetY
        ), nextVisible != isTradeBarVisible else {
            return
        }

        let animation: Animation = nextVisible
            ? .spring(response: 0.36, dampingFraction: 0.80)
            : .spring(response: 0.30, dampingFraction: 0.92)

        withAnimation(animation) {
            isTradeBarVisible = nextVisible
        }
    }
}

private enum AssetDetailHeaderRevealRegion: Equatable {
    case hidden
    case hold
    case visible
}

struct AssetDetailScrollMetrics: Equatable {
    let rawOffsetY: CGFloat
    let normalizedOffsetY: CGFloat
    let maxOffsetY: CGFloat

    init(geometry: ScrollGeometry) {
        let raw = geometry.contentOffset.y
        let normalized = raw + geometry.contentInsets.top
        let maxOffset = max(
            0,
            geometry.contentSize.height
                - geometry.containerSize.height
                + geometry.contentInsets.top
                + geometry.contentInsets.bottom
        )

        rawOffsetY = raw.rounded()
        normalizedOffsetY = normalized.rounded()
        maxOffsetY = maxOffset.rounded()
    }
}

final class AssetDetailTradeBarScrollTracker {
    private static let topRevealThreshold: CGFloat = 12
    private static let minimumScrollableDistance: CGFloat = 24
    private static let hideStartOffset: CGFloat = 36
    private static let hideDeltaThreshold: CGFloat = 22
    private static let showDeltaThreshold: CGFloat = 14

    private var lastClampedOffsetY: CGFloat?
    private var accumulatedDelta: CGFloat = 0
    private var scrollPhase: ScrollPhase = .idle
    private(set) var isVisible = true

    func reset() {
        lastClampedOffsetY = nil
        accumulatedDelta = 0
        scrollPhase = .idle
        isVisible = true
    }

    func updateScrollPhase(_ phase: ScrollPhase) {
        scrollPhase = phase
        if phase == .idle {
            accumulatedDelta = 0
        }
    }

    func update(offsetY: CGFloat, maxOffsetY: CGFloat, isUserDriven: Bool? = nil) -> Bool? {
        let userDriven = isUserDriven ?? (scrollPhase == .interacting || scrollPhase == .decelerating)
        if maxOffsetY <= Self.minimumScrollableDistance || offsetY <= Self.topRevealThreshold {
            lastClampedOffsetY = max(offsetY, 0)
            accumulatedDelta = 0
            guard !isVisible else { return nil }
            isVisible = true
            return true
        }

        let clampedY = min(max(offsetY, 0), maxOffsetY)
        defer { lastClampedOffsetY = clampedY }

        guard userDriven, let previousY = lastClampedOffsetY else {
            accumulatedDelta = 0
            return nil
        }

        let delta = clampedY - previousY
        guard delta != 0 else {
            return nil
        }

        if (delta > 0 && accumulatedDelta < 0) || (delta < 0 && accumulatedDelta > 0) {
            accumulatedDelta = delta
        } else {
            accumulatedDelta += delta
        }

        if accumulatedDelta >= Self.hideDeltaThreshold, clampedY >= Self.hideStartOffset {
            accumulatedDelta = 0
            guard isVisible else { return nil }
            isVisible = false
            return false
        }

        if accumulatedDelta <= -Self.showDeltaThreshold {
            accumulatedDelta = 0
            guard !isVisible else { return nil }
            isVisible = true
            return true
        }

        return nil
    }
}

/// Isolates observation of `store.headerConnectionStatus`, `app.isFavoriteMarketSymbol`,
/// and `scrollChrome.showsHeaderTitle` away from the root `AssetDetailView`.
struct AssetDetailHeaderContainer: View {
    @Environment(AppModel.self) private var app
    let store: AssetDetailStore
    let scrollChrome: AssetDetailScrollChromeState
    let isPreparingShare: Bool
    let dismiss: () -> Void
    let share: () -> Void

    var body: some View {
        AssetDetailFixedHeader(
            symbol: store.symbol,
            showsTitle: scrollChrome.showsHeaderTitle,
            connectionStatus: store.headerConnectionStatus,
            isFavorite: app.isFavoriteMarketSymbol(store.symbol),
            isPreparingShare: isPreparingShare,
            dismiss: dismiss,
            share: share,
            toggleFavorite: {
                Task { await app.toggleFavoriteMarketSymbol(store.symbol) }
            }
        )
    }
}

private struct AssetDetailFixedHeader: View {
    let symbol: String
    let showsTitle: Bool
    let connectionStatus: AssetRealtimeConnectionStatus?
    let isFavorite: Bool
    let isPreparingShare: Bool
    let dismiss: () -> Void
    let share: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        AppScreenHeader(showsDivider: showsTitle) {
            AppGlassIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: L10n.Common.back,
                action: dismiss
            )
        } center: {
            if let connectionStatus {
                AssetRealtimeStatusPill(status: connectionStatus)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Text(verbatim: symbol)
                    .font(.title3.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.primary)
                    .opacity(showsTitle ? 1 : 0)
                    .scaleEffect(showsTitle ? 1 : 0.96)
            }
        } trailing: {
            AssetDetailHeaderTrailingGroup(
                isFavorite: isFavorite,
                isPreparingShare: isPreparingShare,
                share: share,
                toggleFavorite: toggleFavorite
            )
        }
        .animation(.smooth(duration: 0.18), value: showsTitle)
        .animation(.snappy(duration: 0.18), value: connectionStatus?.title)
    }
}

private struct AssetDetailHeaderTrailingGroup: View {
    let isFavorite: Bool
    let isPreparingShare: Bool
    let share: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: share) {
                ZStack {
                    if isPreparingShare {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.primary)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .offset(y: -1)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isPreparingShare)
            .accessibilityLabel(L10n.Common.share)

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isFavorite ? AppTheme.ColorToken.brand : .primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Markets.favorites)
            .accessibilityAddTraits(isFavorite ? .isSelected : [])
        }
        .padding(.horizontal, 2)
        .modifier(AppGlassCapsuleModifier())
    }
}

private struct AssetRealtimeStatusPill: View {
    let status: AssetRealtimeConnectionStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            Text(status.title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private var tint: Color {
        switch status {
        case .live:
            AppTheme.ColorToken.positive
        case .connecting, .authenticating, .subscribing, .reconnecting:
            AppTheme.ColorToken.brandAlt
        case .disconnected:
            AppTheme.ColorToken.icon
        case .failed:
            AppTheme.ColorToken.negative
        }
    }
}

/// Isolates observation of `store.canShowTradeActions`, `store.supportsOptions`,
/// and `scrollChrome.isTradeBarVisible` away from the root `AssetDetailView`.
struct AssetDetailTradeBarContainer: View {
    let store: AssetDetailStore
    let scrollChrome: AssetDetailScrollChromeState
    let showOrders: () -> Void
    let showNews: () -> Void
    let showOptions: () -> Void
    let openTrade: (OrderSide) -> Void

    var body: some View {
        let isVisible = scrollChrome.isTradeBarVisible

        ZStack {
            if store.canShowTradeActions {
                AssetDetailTradeBar(
                    symbol: store.symbol,
                    supportsOptions: store.supportsOptions,
                    showOrders: showOrders,
                    showNews: showNews,
                    showOptions: showOptions,
                    openTrade: openTrade
                )
                .offset(y: isVisible ? 0 : 104)
                .scaleEffect(isVisible ? 1 : 0.90, anchor: .bottom)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .accessibilityHidden(!isVisible)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.92, anchor: .bottom)),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: store.canShowTradeActions)
    }
}

private struct AssetDetailTradeBar: View {
    let symbol: String
    let supportsOptions: Bool
    let showOrders: () -> Void
    let showNews: () -> Void
    let showOptions: () -> Void
    let openTrade: (OrderSide) -> Void

    var body: some View {
        tradeContent
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private var tradeContent: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                content(usesGlass: true)
            }
        } else {
            content(usesGlass: false)
        }
    }

    @ViewBuilder
    private func content(usesGlass: Bool) -> some View {
        HStack(spacing: 12) {
            AssetTradeMoreButton(
                supportsOptions: supportsOptions,
                usesGlass: usesGlass,
                showOrders: showOrders,
                showNews: showNews,
                showOptions: showOptions
            )

            AssetTradePrimaryGroup(symbol: symbol, usesGlass: usesGlass, openTrade: openTrade)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct AssetTradePrimaryGroup: View {
    let symbol: String
    let usesGlass: Bool
    let openTrade: (OrderSide) -> Void

    var body: some View {
        HStack(spacing: 8) {
            AssetTradeSideButton(side: .buy, usesGlass: usesGlass, openTrade: openTrade)
            AssetTradeSideButton(side: .sell, usesGlass: usesGlass, openTrade: openTrade)
        }
        .padding(4)
        .frame(height: 60)
        .modifier(AssetTradeGlassPillModifier(usesGlass: usesGlass))
    }
}

private struct AssetTradeSideButton: View {
    @Environment(\.locale) private var locale

    let side: OrderSide
    let usesGlass: Bool
    let openTrade: (OrderSide) -> Void

    var body: some View {
        Button {
            openTrade(side)
        } label: {
            Text(side.titleText(locale: locale))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(AssetTradeSideButtonGlassModifier(tint: side.tradeActionTint, usesGlass: usesGlass))
    }
}

private struct AssetTradeSideButtonGlassModifier: ViewModifier {
    let tint: Color
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if usesGlass, #available(iOS 26.0, *) {
            content
                .background {
                    Capsule()
                        .fill(tint.opacity(0.18))
                }
                .glassEffect(.regular.tint(tint.opacity(0.68)).interactive(), in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(tint.opacity(0.46), lineWidth: 0.75)
                }
                .shadow(color: tint.opacity(0.18), radius: 10, y: 4)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .fill(tint.opacity(0.40))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(tint.opacity(0.36), lineWidth: 0.75)
                }
                .shadow(color: tint.opacity(0.14), radius: 10, y: 4)
        }
    }
}

private struct AssetTradeMoreButton: View {
    let supportsOptions: Bool
    let usesGlass: Bool
    let showOrders: () -> Void
    let showNews: () -> Void
    let showOptions: () -> Void

    var body: some View {
        Menu {
            Button(action: showNews) {
                Label("News", systemImage: "newspaper")
            }

            Button(action: showOrders) {
                Label("Orders", systemImage: "doc.text.magnifyingglass")
            }

            Button(action: showOptions) {
                Label("Options", systemImage: "chart.line.uptrend.xyaxis")
            }
            .disabled(!supportsOptions)

            Button {
            } label: {
                Label("Add alert", systemImage: "bell")
            }
            .disabled(true)
        } label: {
            AssetMoreActionsIcon()
                .foregroundStyle(.primary)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(AssetTradeGlassPillModifier(usesGlass: usesGlass))
        .accessibilityLabel("More actions")
    }
}

private struct AssetMoreActionsIcon: View {
    var body: some View {
        Canvas { context, size in
            let color = Color.primary
            let lineWidth = max(2.2, size.width * 0.044)
            let bodyWidth = size.width * 0.48
            let bodyHeight = size.height * 0.38
            let bodyRect = CGRect(
                x: (size.width - bodyWidth) / 2,
                y: size.height * 0.44,
                width: bodyWidth,
                height: bodyHeight
            )
            let cornerRadius = size.width * 0.085

            let bodyPath = Path(roundedRect: bodyRect, cornerRadius: cornerRadius)
            context.stroke(bodyPath, with: .color(color), lineWidth: lineWidth)

            let lowerCapWidth = size.width * 0.40
            let lowerCapRect = CGRect(
                x: (size.width - lowerCapWidth) / 2,
                y: size.height * 0.305,
                width: lowerCapWidth,
                height: lineWidth
            )
            context.fill(Path(roundedRect: lowerCapRect, cornerRadius: lineWidth / 2), with: .color(color))

            let upperCapWidth = size.width * 0.30
            let upperCapRect = CGRect(
                x: (size.width - upperCapWidth) / 2,
                y: size.height * 0.205,
                width: upperCapWidth,
                height: lineWidth
            )
            context.fill(Path(roundedRect: upperCapRect, cornerRadius: lineWidth / 2), with: .color(color))
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

private struct AssetTradeGlassPillModifier: ViewModifier {
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if usesGlass, #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.12)).interactive(), in: .capsule)
        } else {
            content
                .background(AppTheme.ColorToken.groupedSurface, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(0.14))
                }
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        }
    }
}
