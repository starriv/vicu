import SwiftUI
import UIKit

struct AssetDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @State private var store: AssetDetailStore
    @State private var showsHeaderTitle = false
    @State private var showsQuoteHistory = false
    @State private var showsNews = false
    @State private var showsOptions = false
    @State private var newsSheetDetent: PresentationDetent = .fraction(Self.newsSheetCompactFraction)
    @State private var assetSharePayload: AssetSharePayload?
    @State private var assetSharePreparationTask: Task<Void, Never>?
    @State private var isPreparingAssetShare = false
    @State private var positionSharePayload: AssetPositionSharePayload?
    @State private var tradeDestination: AssetTradeDestination?

    init(symbol: String) {
        _store = State(initialValue: AssetDetailStore(symbol: symbol))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchorID)

                    AssetIdentityHeader(store: store)

                    if store.errorMessage != nil, store.asset == nil {
                        ContentUnavailableView(
                            "Asset data unavailable",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        AssetDetailMarketDataContent(
                            store: store,
                            showQuoteHistory: { showsQuoteHistory = true },
                            showOptions: { showsOptions = true },
                            sharePosition: { position in
                                positionSharePayload = AssetPositionSharePayload(
                                    symbol: store.symbol,
                                    displayName: store.displayName,
                                    exchange: store.exchangeText,
                                    position: position
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, AppTheme.Spacing.pageTop)
                .padding(.bottom, AppTheme.Spacing.pageBottom + (store.canShowTradeActions ? 88 : 0))
            }
            .onScrollGeometryChange(for: AssetDetailHeaderRevealRegion.self) { geometry in
                Self.headerRevealRegion(for: geometry.contentOffset.y)
            } action: { _, region in
                updateHeaderTitleVisibility(for: region)
            }
            .onAppear {
                proxy.scrollTo(Self.topAnchorID, anchor: .top)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .restoreInteractivePopGesture()
        .safeAreaInset(edge: .top, spacing: 0) {
            AssetDetailFixedHeader(
                symbol: store.symbol,
                showsTitle: showsHeaderTitle,
                connectionStatus: headerConnectionStatus,
                isFavorite: app.isFavoriteMarketSymbol(store.symbol),
                isPreparingShare: isPreparingAssetShare,
                dismiss: { dismiss() },
                share: prepareAssetShare,
                toggleFavorite: {
                    Task { await app.toggleFavoriteMarketSymbol(store.symbol) }
                }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.canShowTradeActions && showsHeaderTitle {
                AssetDetailTradeBar(
                    symbol: store.symbol,
                    supportsOptions: store.asset?.attributes?.contains("has_options") == true,
                    showOrders: {
                        app.openOrdersList(symbol: store.symbol, reason: .assetDetail)
                    },
                    showNews: {
                        showsNews = true
                    },
                    showOptions: {
                        showsOptions = true
                    },
                    openTrade: openTrade(_:)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationDestination(item: $tradeDestination) { destination in
            TradeView(
                symbol: destination.symbol,
                side: destination.side,
                seed: destination.seed,
                onSubmittedOrder: showSubmittedOrder(_:)
            )
        }
        .task {
            store.start(app: app)
        }
        .onChange(of: store.errorMessage) { _, message in
            showErrorMessage(message)
        }
        .refreshable {
            store.reload(app: app)
        }
        .onDisappear {
            assetSharePreparationTask?.cancel()
            assetSharePreparationTask = nil
            store.stop()
        }
        .sheet(isPresented: $showsQuoteHistory) {
            AssetQuoteHistorySheet(
                symbol: store.symbol,
                feed: store.feed,
                latestQuote: store.quote
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsNews) {
            AssetNewsSheet(
                symbol: store.symbol,
                displayName: store.displayName
            )
            .presentationDetents([.fraction(Self.newsSheetCompactFraction), .large], selection: $newsSheetDetent)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsOptions) {
            AssetOptionsSheet(
                symbol: store.symbol,
                displayName: store.displayName
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $assetSharePayload) { payload in
            AssetShareSheet(payload: payload)
                .presentationDetents([.height(680)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $positionSharePayload) { payload in
            AssetPositionShareSheet(payload: payload)
                .presentationDetents([.height(680)])
                .presentationDragIndicator(.visible)
        }
    }

    private static let topAnchorID = "asset-detail-top"
    private static let headerTitleRevealOffset: CGFloat = 56
    private static let headerTitleHideOffset: CGFloat = 18
    private static let newsSheetCompactFraction = 0.67

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

    private func showSubmittedOrder(_: AlpacaOrder) {
        tradeDestination = nil
    }

    private func prepareAssetShare() {
        guard !isPreparingAssetShare else {
            return
        }

        assetSharePreparationTask?.cancel()
        assetSharePreparationTask = Task { @MainActor in
            isPreparingAssetShare = true
            defer {
                isPreparingAssetShare = false
                assetSharePreparationTask = nil
            }

            guard await store.waitForShareableChartData() else {
                guard !Task.isCancelled else {
                    return
                }

                toastCenter.showErrorMessage(
                    L10n.AssetPositionShare.prepareFailed(locale: app.appLanguage.locale)
                )
                return
            }

            guard !Task.isCancelled else {
                return
            }

            assetSharePayload = AssetSharePayload(store: store)
        }
    }

    private func openTrade(_ side: OrderSide) {
        tradeDestination = AssetTradeDestination(
            symbol: store.symbol,
            side: side,
            seed: TradeSeedContext(
                account: app.portfolio.account,
                asset: store.asset,
                position: store.position,
                latestQuote: store.quote,
                latestTrade: store.latestTrade,
                feed: store.feed
            )
        )
    }

    private func showErrorMessage(_ message: String?) {
        guard let message else {
            return
        }

        toastCenter.showErrorMessage(message)
    }

    private var headerConnectionStatus: AssetRealtimeConnectionStatus? {
        store.headerConnectionStatus
    }
}

private enum AssetDetailHeaderRevealRegion: Equatable {
    case hidden
    case hold
    case visible
}

private extension View {
    func restoreInteractivePopGesture() -> some View {
        background {
            InteractivePopGestureRestorer()
                .frame(width: 0, height: 0)
        }
    }
}

private struct InteractivePopGestureRestorer: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> RestorerViewController {
        let controller = RestorerViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: RestorerViewController, context: Context) {
        controller.coordinator = context.coordinator
        controller.restoreInteractivePopGesture()
    }

    static func dismantleUIViewController(_ controller: RestorerViewController, coordinator: Coordinator) {
        coordinator.detach(from: controller.navigationController)
    }

    final class RestorerViewController: UIViewController {
        weak var coordinator: Coordinator?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            restoreInteractivePopGesture()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreInteractivePopGesture()
        }

        func restoreInteractivePopGesture() {
            DispatchQueue.main.async { [weak self] in
                self?.coordinator?.attach(to: self?.navigationController)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var navigationController: UINavigationController?
        private weak var originalDelegate: UIGestureRecognizerDelegate?
        private var originalIsEnabled: Bool?

        func attach(to navigationController: UINavigationController?) {
            guard let navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer else {
                return
            }

            if self.navigationController !== navigationController {
                detach(from: self.navigationController)
                self.navigationController = navigationController
                originalDelegate = gesture.delegate
                originalIsEnabled = gesture.isEnabled
            }

            gesture.delegate = self
            gesture.isEnabled = navigationController.viewControllers.count > 1
        }

        func detach(from navigationController: UINavigationController?) {
            guard let navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer else {
                clear()
                return
            }

            if gesture.delegate === self {
                gesture.delegate = originalDelegate
            }

            if let originalIsEnabled {
                gesture.isEnabled = originalIsEnabled
            }

            clear()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController,
                  navigationController.viewControllers.count > 1 else {
                return false
            }

            if navigationController.transitionCoordinator?.isAnimated == true {
                return false
            }

            return true
        }

        private func clear() {
            navigationController = nil
            originalDelegate = nil
            originalIsEnabled = nil
        }
    }
}

private struct AssetTradeDestination: Identifiable, Hashable {
    let symbol: String
    let side: OrderSide
    let seed: TradeSeedContext

    var id: String {
        "\(symbol)-\(side.rawValue)"
    }

    static func == (lhs: AssetTradeDestination, rhs: AssetTradeDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct AssetDetailMarketDataContent: View {
    let store: AssetDetailStore
    let showQuoteHistory: () -> Void
    let showOptions: () -> Void
    let sharePosition: (AlpacaPosition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AssetHeroChartInteractionSection(store: store)
            AssetLevelOnePanel(
                store: store,
                showQuoteHistory: showQuoteHistory
            )
            if let position = store.position {
                PositionOverviewPanel(
                    position: position,
                    onShare: { sharePosition(position) }
                )
            }
            AssetDayStatsPanel(store: store)
            AssetAboutPanel(store: store, showOptions: showOptions)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssetHeroChartInteractionSection: View {
    let store: AssetDetailStore
    @State private var chartSelection: AssetChartSelection?
    @State private var isChartScrubbing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AssetPriceHeroSection(store: store, chartSelection: $chartSelection)
            AssetChartSection(
                store: store,
                chartSelection: $chartSelection,
                isChartScrubbing: $isChartScrubbing
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssetIdentityHeader: View {
    let store: AssetDetailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 7) {
                Text(verbatim: store.symbol)
                    .font(.title.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.primary)

                if let exchangeText {
                    Text("·")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(.tertiaryLabel))

                    Text(verbatim: exchangeText)
                        .font(.subheadline.weight(.bold))
                }

                MarketSessionTimelineView(
                    timeline: MarketSessionTimeline(progress: store.sessionProgress),
                    selectedDate: nil,
                    style: .dot,
                    dotSize: 9
                )
                .padding(.leading, 2)
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)

            AppMarqueeText(
                store.displayName,
                font: .title2.weight(.semibold),
                foregroundColor: .primary
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exchangeText: String? {
        store.exchangeText == AppFormatter.placeholder ? nil : store.exchangeText
    }
}

private struct AssetPriceHeroSection: View {
    let store: AssetDetailStore
    @Binding var chartSelection: AssetChartSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AppPriceText(
                displayedPrice,
                font: .system(size: 48, weight: .medium, design: .rounded),
                minimumScaleFactor: 0.72,
                isAnimated: chartSelection == nil
            )

            VStack(alignment: .leading, spacing: 2) {
                if let chartSelection {
                    let selectedChange = store.selectedPriceChange(for: chartSelection)
                    AssetPriceChangeLine(
                        change: selectedChange.change,
                        percent: selectedChange.percentChange,
                        label: nil,
                        isPositive: selectedChange.isPositive
                    )
                } else if store.selectedRange != .oneDay, let periodChange = store.chartRenderModels.line.periodPriceChange {
                    AssetPriceChangeLine(
                        change: periodChange.change,
                        percent: periodChange.percentChange,
                        label: store.selectedRange.performanceLabel,
                        isPositive: periodChange.isPositive
                    )
                } else if !(store.selectedRange == .oneDay && store.activeExtendedSession == .overnight) {
                    AssetPriceChangeLine(
                        change: store.todayPriceChange,
                        percent: store.todayPercentChange,
                        label: "Today",
                        isPositive: store.isTodayPositive
                    )
                }

                if chartSelection == nil,
                   store.selectedRange == .oneDay,
                   let extendedSession = store.extendedSession,
                   store.extendedPriceChange != nil {
                    AssetPriceChangeLine(
                        change: store.extendedPriceChange,
                        percent: store.extendedPercentChange,
                        label: store.extendedSessionTitle ?? extendedSession.title,
                        isPositive: store.isExtendedPositive
                    )
                } else {
                    AssetPriceChangeLine(
                        change: nil,
                        percent: nil,
                        label: "Placeholder",
                        isPositive: true
                    )
                    .hidden()
                }
            }
            .frame(height: 38, alignment: .top)
        }
        .redacted(reason: store.isLoading ? .placeholder : [])
    }

    private var displayedPrice: Double? {
        chartSelection?.point.close ?? store.currentPrice
    }
}

private struct AssetChartSection: View {
    let store: AssetDetailStore
    @Binding var chartSelection: AssetChartSelection?
    @Binding var isChartScrubbing: Bool

    private static let chartHeight: CGFloat = 330
    private static let timelineHeight: CGFloat = 24
    private static let scrubTimelineClearance: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottom) {
                AssetPriceChart(
                    model: store.chartRenderModels.model(for: store.effectiveChartMode),
                    isLoading: store.isLoadingChart,
                    range: store.selectedRange,
                    selection: $chartSelection,
                    isScrubbing: $isChartScrubbing
                )
                .padding(.bottom, chartBottomClearance)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(!store.isLoadingChart)

                AssetPeriodChartSkeleton(
                    mode: store.effectiveChartMode,
                    tint: AppTheme.ColorToken.positive,
                    showsMockSeries: false
                )
                .padding(.bottom, chartBottomClearance)
                .opacity(store.isLoadingChart ? 1 : 0)
                .animation(.snappy(duration: 0.18), value: store.isLoadingChart)
                .allowsHitTesting(false)

                if store.selectedRange == .oneDay {
                    MarketSessionTimelineView(
                        timeline: MarketSessionTimeline(progress: store.sessionProgress),
                        selectedDate: chartSelection?.point.date
                    )
                    .frame(height: Self.timelineHeight)
                    .padding(.horizontal, 4)
                    .opacity(isChartScrubbing ? 1 : 0)
                    .animation(.snappy(duration: 0.16), value: isChartScrubbing)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: Self.chartHeight)

            HStack(spacing: 12) {
                AssetRangePicker(selection: store.selectedRange) { range in
                    chartSelection = nil
                    isChartScrubbing = false
                    store.selectRange(range)
                }

                Spacer(minLength: 8)

                if store.selectedRange != .oneDay {
                    AssetChartModePicker(
                        selection: Binding(
                            get: { store.chartMode },
                            set: { store.selectChartMode($0) }
                        )
                    )
                }
            }
        }
    }

    private var chartBottomClearance: CGFloat {
        store.selectedRange == .oneDay ? Self.scrubTimelineClearance : 0
    }
}

private struct AssetLevelOnePanel: View {
    let store: AssetDetailStore
    let showQuoteHistory: () -> Void

    var body: some View {
        AssetLevelOneBook(
            bidPrice: store.bidPrice,
            askPrice: store.askPrice,
            bidSize: store.quote?.bidSize,
            askSize: store.quote?.askSize,
            bidExchange: store.quote?.bidExchange,
            askExchange: store.quote?.askExchange,
            spread: store.spread,
            quoteTime: store.quote?.timestamp,
            showHistory: showQuoteHistory
        )
    }
}

private struct AssetDayStatsPanel: View {
    let store: AssetDetailStore

    var body: some View {
        AssetDetailSection(title: "Key statistics") {
            AssetTodayStatsGrid(
                open: store.dayOpen,
                high: store.dayHigh,
                low: store.dayLow,
                volume: store.dayVolume,
                vwap: store.dailyBar?.vwap,
                trades: store.dailyBar?.tradeCount
            )
        }
    }
}

private struct AssetAboutPanel: View {
    let store: AssetDetailStore
    let showOptions: () -> Void

    var body: some View {
        AssetDetailSection(title: "About") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    AssetInfoRow(title: "Name", value: store.displayName)
                    AssetInfoRow(title: "Exchange", value: store.exchangeText)
                    AssetInfoRow(title: "Type", value: AssetDetailText.assetClass(store.asset?.assetClass))
                    AssetInfoRow(title: "Status", value: AssetDetailText.status(store.asset?.status))
                }

                AssetCapabilitiesDisclosure(asset: store.asset, showOptions: showOptions)
            }
        }
    }
}

struct AssetPriceChangeLine: View {
    let change: Double?
    let percent: Double?
    let label: String?
    let isPositive: Bool

    private var tint: Color {
        isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 12, weight: .bold))

            Text(AppFormatter.signedMoney(change))
            Text("(\(AppFormatter.signedPercent(percent)))")
            if let label {
                Text(label)
                    .foregroundStyle(.primary)
            }
        }
        .font(.callout.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.76)
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
            HStack(spacing: 8) {
                AssetDetailHeaderShareButton(
                    isPreparing: isPreparingShare,
                    action: share
                )

                AppGlassIconButton(
                    systemImage: isFavorite ? "heart.fill" : "heart",
                    foregroundColor: isFavorite ? AppTheme.ColorToken.brand : .primary,
                    accessibilityLabel: L10n.Markets.favorites,
                    action: toggleFavorite
                )
            }
        }
        .animation(.smooth(duration: 0.18), value: showsTitle)
        .animation(.snappy(duration: 0.18), value: connectionStatus?.title)
    }
}

private struct AssetDetailHeaderShareButton: View {
    let isPreparing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.primary)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
        .modifier(AppGlassCircleModifier())
        .accessibilityLabel(L10n.Common.share)
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

private struct AssetTodayStatsGrid: View {
    let open: Double?
    let high: Double?
    let low: Double?
    let volume: Double?
    let vwap: Double?
    let trades: Double?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            AssetDenseMetric(title: "Volume", value: AssetDetailNumber.compact(volume))
            AssetDenseMetric(title: "Open", value: AppFormatter.money(open))
            AssetDenseMetric(title: "VWAP", value: AppFormatter.money(vwap))
            AssetDenseMetric(title: "High", value: AppFormatter.money(high))
            AssetDenseMetric(title: "Low", value: AppFormatter.money(low))
            AssetDenseMetric(title: "Trades", value: AssetDetailNumber.compact(trades))
        }
        .padding(14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AssetDenseMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AssetDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum AssetDetailGrid {
    static let twoColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
}

struct AssetMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(AppTypography.rowValue.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AssetCapabilitiesDisclosure: View {
    let asset: AlpacaAsset?
    let showOptions: () -> Void
    @State private var isExpanded = false

    private var enabledCount: Int {
        [
            asset?.tradable == true,
            asset?.fractionable == true,
            asset?.hasAttribute("has_options") == true,
            asset?.hasAttribute("fractional_eh_enabled") == true,
            asset?.hasAttribute("overnight_tradable") == true,
            asset?.marginable == true,
            asset?.shortable == true,
            asset?.easyToBorrow == true
        ].filter { $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.brand)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trading capabilities")
                            .font(AppTypography.detail.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("\(enabledCount) available")
                            .font(AppTypography.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trading capabilities")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                LazyVGrid(columns: AssetDetailGrid.twoColumns, spacing: 10) {
                    AssetCapabilityChip(
                        title: "Tradable",
                        value: AssetDetailText.boolean(asset?.tradable),
                        systemImage: "arrow.left.arrow.right",
                        isEnabled: asset?.tradable == true
                    )

                    AssetCapabilityChip(
                        title: "Fractional",
                        value: AssetDetailText.boolean(asset?.fractionable),
                        systemImage: "chart.pie",
                        isEnabled: asset?.fractionable == true
                    )

                    AssetCapabilityChip(
                        title: "Options",
                        value: AssetDetailText.boolean(asset?.hasAttribute("has_options")),
                        systemImage: "square.stack.3d.up",
                        isEnabled: asset?.hasAttribute("has_options") == true,
                        action: asset?.hasAttribute("has_options") == true ? showOptions : nil
                    )

                    AssetCapabilityChip(
                        title: "Extended hours",
                        value: AssetDetailText.boolean(asset?.hasAttribute("fractional_eh_enabled")),
                        systemImage: "clock",
                        isEnabled: asset?.hasAttribute("fractional_eh_enabled") == true
                    )

                    AssetCapabilityChip(
                        title: "Overnight",
                        value: AssetDetailText.boolean(asset?.hasAttribute("overnight_tradable")),
                        systemImage: "moon",
                        isEnabled: asset?.hasAttribute("overnight_tradable") == true
                    )

                    AssetCapabilityChip(
                        title: "Margin",
                        value: AssetDetailText.boolean(asset?.marginable),
                        systemImage: "creditcard",
                        isEnabled: asset?.marginable == true
                    )

                    AssetCapabilityChip(
                        title: "Shortable",
                        value: AssetDetailText.boolean(asset?.shortable),
                        systemImage: "arrow.down.right",
                        isEnabled: asset?.shortable == true
                    )

                    AssetCapabilityChip(
                        title: "Borrow",
                        value: AssetDetailText.borrowStatus(asset),
                        systemImage: "arrow.down.circle",
                        isEnabled: asset?.easyToBorrow == true
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(AppTheme.ColorToken.groupedSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.10))
        }
    }
}

private struct AssetCapabilityChip: View {
    let title: String
    let value: String
    let systemImage: String
    let isEnabled: Bool
    let action: (() -> Void)?

    init(
        title: String,
        value: String,
        systemImage: String,
        isEnabled: Bool,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    private var tint: Color {
        isEnabled ? AppTheme.ColorToken.positive : Color(.tertiaryLabel)
    }

    var body: some View {
        if let action {
            Button(action: action) {
                chipContent
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens options")
        } else {
            chipContent
        }
    }

    private var chipContent: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(isEnabled ? 0.10 : 0.06))
        }
    }
}

private struct AssetInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(AppTypography.detail.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
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
        .modifier(AssetTradePillModifier(style: .glass, usesGlass: usesGlass))
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
        .modifier(AssetTradePillModifier(style: .glass, usesGlass: usesGlass))
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

private enum AssetTradePillStyle {
    case brand
    case glass
}

private struct AssetTradePillModifier: ViewModifier {
    let style: AssetTradePillStyle
    let usesGlass: Bool

    func body(content: Content) -> some View {
        switch style {
        case .brand:
            content
                .background(AppTheme.ColorToken.brand, in: Capsule())
                .shadow(color: AppTheme.ColorToken.brand.opacity(0.20), radius: 12, y: 5)
        case .glass:
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
}

private enum AssetDetailNumber {
    static func format(_ value: Double?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func compact(_ value: Double?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...2)))
    }

    static func percentValue(_ value: Double?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return AppFormatter.percent(value / 100)
    }
}

private enum AssetDetailText {
    static func assetClass(_ value: String?) -> String {
        title(value) ?? AppFormatter.placeholder
    }

    static func status(_ value: String?) -> String {
        title(value) ?? AppFormatter.placeholder
    }

    static func borrowStatus(_ asset: AlpacaAsset?) -> String {
        guard let asset else {
            return AppFormatter.placeholder
        }

        if let status = title(asset.borrowStatus) {
            return status
        }

        if asset.easyToBorrow == true {
            return "Easy"
        }

        return asset.shortable == true ? "Available" : "Unavailable"
    }

    static func boolean(_ value: Bool?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value ? "Yes" : "No"
    }

    private static func title(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let words = value
            .split(separator: "_")
            .map { word in
                let lowercased = word.lowercased()
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }

        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}

private extension AlpacaAsset {
    func hasAttribute(_ attribute: String) -> Bool {
        attributes?.contains(attribute) == true
    }
}
