import SwiftUI

struct AssetDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var store: AssetDetailStore
    @State private var scrollChrome = AssetDetailScrollChromeState()
    @State private var hasPerformedInitialScroll = false
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

                    AssetDetailTradeBarBottomSpacer(store: store)
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, AppTheme.Spacing.pageTop)
                .padding(.bottom, AppTheme.Spacing.pageBottom)
            }
            .onScrollPhaseChange { _, newPhase in
                scrollChrome.updateScrollPhase(newPhase)
            }
            .onScrollGeometryChange(for: AssetDetailScrollMetrics.self) { geometry in
                AssetDetailScrollMetrics(geometry: geometry)
            } action: { _, metrics in
                scrollChrome.update(metrics: metrics)
            }
            .onAppear {
                scrollChrome.reset()
                if !hasPerformedInitialScroll {
                    hasPerformedInitialScroll = true
                    proxy.scrollTo(Self.topAnchorID, anchor: .top)
                }
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
            AssetDetailHeaderContainer(
                store: store,
                scrollChrome: scrollChrome,
                isPreparingShare: isPreparingAssetShare,
                dismiss: { dismiss() },
                share: prepareAssetShare
            )
        }
        .overlay(alignment: .bottom) {
            AssetDetailTradeBarContainer(
                store: store,
                scrollChrome: scrollChrome,
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
        }
        .navigationDestination(item: $tradeDestination) { destination in
            TradeView(
                symbol: destination.symbol,
                side: destination.side,
                seed: destination.seed,
                onSubmittedOrder: showSubmittedOrder(_:)
            )
        }
        .onAppear {
            store.setShowsTradeMarkers(app.showsChartTradeMarkers)
            store.start(service: app)
        }
        .onChange(of: app.showsChartTradeMarkers) { _, isEnabled in
            store.setShowsTradeMarkers(isEnabled)
        }
        .onChange(of: store.errorMessage) { _, message in
            showErrorMessage(message)
        }
        .refreshable {
            await store.refresh(service: app)
        }
        .onDisappear {
            assetSharePreparationTask?.cancel()
            assetSharePreparationTask = nil
            store.stop()
        }
        .sheet(isPresented: $showsQuoteHistory) {
            AssetQuoteHistorySheetContainer(store: store)
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
                .presentationDetents([.height(700)])
                .presentationDragIndicator(.visible)
        }
    }

    private static let topAnchorID = "asset-detail-top"
    private static let newsSheetCompactFraction = 0.67

    private func showSubmittedOrder(_: AlpacaOrder) {
        tradeDestination = nil
        store.invalidateTradeExecutions()
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
}

private struct AssetDetailTradeBarBottomSpacer: View {
    let store: AssetDetailStore

    var body: some View {
        Color.clear
            .frame(height: store.canShowTradeActions ? 68 : 0)
    }
}

/// Isolates observation of `store.quote` and `store.feed` inside the sheet presentation
/// so live ticks never invalidate `AssetDetailView.body`.
private struct AssetQuoteHistorySheetContainer: View {
    let store: AssetDetailStore

    var body: some View {
        AssetQuoteHistorySheet(
            symbol: store.symbol,
            feed: store.feed,
            latestQuote: store.quote
        )
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
