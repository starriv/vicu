import SwiftUI

struct MarketsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @State private var isLoading = false
    @State private var hasLoadError = false
    @State private var selectedMarketList: MarketListMode = .favorites
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var searchStore = MarketSearchStore()
    @State private var selectedSymbolDestination: MarketAssetDestination?

    private var overview: MarketOverview? {
        app.cachedMarketOverview
    }

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingSearchResults: Bool {
        !normalizedSearchQuery.isEmpty
    }

    private var marketContextID: String {
        "\(app.pageCacheScopeID ?? "none")-\(app.environment.rawValue)-\(app.hasCredentials)"
    }

    var body: some View {
        BasicLayout(L10n.Markets.title, style: .scroll(spacing: 18)) {
            if !app.hasCredentials {
                AppEmptyStateView(
                    title: L10n.Common.noData,
                    systemImage: AppIcon.More.alpaca
                )
            } else if isShowingSearchResults {
                MarketSearchResultsView(
                    query: normalizedSearchQuery,
                    store: searchStore,
                    favoriteSymbols: favoriteSymbolSet,
                    onSelectScope: { searchStore.updateScope($0, app: app) },
                    onOpenAsset: { openAssetDetail($0, recordRecent: true) },
                    onToggleFavorite: toggleFavorite(_:)
                )
            } else if isSearchPresented {
                MarketSearchLandingView(
                    store: searchStore,
                    favoriteSymbols: favoriteSymbolSet,
                    ownedSymbols: ownedSymbolSet,
                    onSelectRecent: { openAssetDetail($0, recordRecent: true) },
                    onRemoveRecent: { searchStore.removeRecentSymbol($0, app: app) },
                    onClearRecents: { searchStore.clearRecentSymbols(app: app) },
                    onChangePopularSort: { searchStore.updatePopularSort($0, app: app) },
                    onExpandPopular: {
                        withAnimation(.snappy(duration: 0.2)) {
                            searchStore.showsAllPopular = true
                        }
                    },
                    onSelectPopular: { openAssetDetail($0, recordRecent: false) },
                    onToggleFavorite: toggleFavorite(_:)
                )
            } else {
                marketDiscoveryContent
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(searchStore.defaultSearchSymbol)
        )
        .keyboardType(.asciiCapable)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .onSubmit(of: .search) {
            handleSearchSubmit()
        }
        .navigationDestination(item: $selectedSymbolDestination) { destination in
            AssetDetailView(symbol: destination.symbol)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        WatchlistsView()
                    } label: {
                        Label(L10n.Watchlists.title, systemImage: AppIcon.Market.watchlists)
                    }

                    Button {
                        Task {
                            await refreshAll(forceRefresh: true)
                        }
                    } label: {
                        Label(L10n.Common.refresh, systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: AppIcon.Market.more)
                }
            }
        }
        .task(id: marketContextID) {
            // Local-only read; safe to do before the transition delay so recents are never stale.
            searchStore.syncRecentSymbols(app: app)

            // Let the tab-switch Liquid Glass transition settle before kicking off
            // search prompt/cache mutations and network revalidation.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else {
                return
            }

            async let marketsLoad: Void = loadInitialOrRevalidate()
            async let searchLoad: Void = searchStore.handleContextAppearance(contextID: marketContextID, app: app)
            _ = await (marketsLoad, searchLoad)
            if !normalizedSearchQuery.isEmpty {
                searchStore.updateQuery(normalizedSearchQuery, app: app, immediate: true)
            }
        }
        .task(id: app.cachedMarketOverviewAt) {
            await refreshMarketDataAtNextBoundary()
        }
        .onDisappear {
            searchStore.onDisappear()
        }
        .refreshable {
            await refreshAll(forceRefresh: true)
        }
        .onChange(of: normalizedSearchQuery) { _, newValue in
            searchStore.updateQuery(newValue, app: app, immediate: false)
        }
        .onChange(of: isSearchPresented) { _, presented in
            if presented {
                searchStore.syncRecentSymbols(app: app)
            }
        }
        .onChange(of: app.favoriteMarketSymbolsError) { _, message in
            showErrorMessage(message)
        }
        .onChange(of: searchStore.lastCatalogErrorMessage) { _, _ in
            if let message = searchStore.consumeCatalogErrorMessage() {
                toastCenter.showErrorMessage(message)
            }
        }
    }

    @ViewBuilder
    private var marketDiscoveryContent: some View {
        if let overview {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                MarketStatusCard(
                    overview: overview,
                    referenceDate: context.date,
                    cachedAt: app.cachedMarketOverviewAt,
                    cacheIsStale: app.isMarketOverviewFromStaleCache
                )
            }

            MarketListModePicker(selection: $selectedMarketList)

            switch selectedMarketList {
            case .favorites, .leaders:
                MarketSymbolSection(mode: selectedMarketList, overview: overview)
            case .trending:
                if searchStore.shouldShowTrendingSection {
                    SearchTrendingSection(
                        symbols: searchStore.displayedPopularSymbols,
                        sort: searchStore.popularSort,
                        showsSkeleton: searchStore.shouldShowPopularSkeleton,
                        canExpand: searchStore.canExpandPopularSymbols,
                        favoriteSymbols: favoriteSymbolSet,
                        ownedSymbols: ownedSymbolSet,
                        onChangeSort: { searchStore.updatePopularSort($0, app: app) },
                        onExpand: {
                            withAnimation(.snappy(duration: 0.2)) {
                                searchStore.showsAllPopular = true
                            }
                        },
                        onSelect: { openAssetDetail($0, recordRecent: false) },
                        onToggleFavorite: toggleFavorite(_:)
                    )
                }
            }
        } else if isLoading || !hasLoadError {
            MarketOverviewSkeleton()
        } else {
            AppEmptyStateView(
                title: L10n.Common.noData,
                systemImage: AppIcon.Market.overviewEmpty
            )
        }
    }

    private var favoriteSymbolSet: Set<String> {
        Set(app.favoriteMarketSymbols.map { $0.uppercased() })
    }

    private var ownedSymbolSet: Set<String> {
        Set(app.portfolio.positions.map { $0.symbol.uppercased() })
    }

    private func handleSearchSubmit() {
        let trimmed = normalizedSearchQuery
        guard !trimmed.isEmpty else { return }

        let upper = trimmed.uppercased()
        if let exact = searchStore.results.first(where: { $0.symbol == upper }) {
            openAssetDetail(exact.symbol, recordRecent: true)
            return
        }
        searchStore.updateQuery(trimmed, app: app, immediate: true)
    }

    private func openAssetDetail(_ symbol: String, recordRecent: Bool) {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else { return }

        if recordRecent {
            searchStore.recordRecentSelection(normalizedSymbol, app: app)
        }
        isSearchPresented = false
        selectedSymbolDestination = MarketAssetDestination(symbol: normalizedSymbol)
    }

    private func toggleFavorite(_ symbol: String) {
        Task {
            await app.toggleFavoriteMarketSymbol(symbol)
        }
    }

    private func loadInitialOrRevalidate() async {
        guard app.hasCredentials else {
            return
        }

        if app.cachedMarketOverview == nil || !app.hasLoadedFavoriteMarketSymbols {
            await app.hydrateCachedMarketsFromDisk()
        }

        await refreshAll(forceRefresh: false)
    }

    private func refreshAll(forceRefresh: Bool) async {
        async let overviewTask: Void = loadMarketData(forceRefresh: forceRefresh)
        async let favoritesTask: Void = app.refreshFavoriteMarketSymbols(forceReload: forceRefresh)
        async let searchRefreshTask: Void = refreshSearchIfNeeded(forceRefresh: forceRefresh)
        _ = await (overviewTask, favoritesTask, searchRefreshTask)
    }

    private func refreshSearchIfNeeded(forceRefresh: Bool) async {
        guard forceRefresh else { return }
        await searchStore.refresh(app: app)
    }

    private func loadMarketData(forceRefresh: Bool) async {
        guard app.hasCredentials else {
            return
        }

        if app.cachedMarketOverview == nil {
            isLoading = true
        }
        hasLoadError = false
        defer { isLoading = false }

        do {
            _ = try await app.fetchMarketOverview(forceRefresh: forceRefresh)
        } catch where error.isRequestCancellation {
            return
        } catch {
            if app.cachedMarketOverview == nil {
                hasLoadError = true
            }
            toastCenter.showError(error, locale: app.appLanguage.locale)
        }
    }

    private func refreshMarketDataAtNextBoundary() async {
        guard let overview else {
            return
        }

        let snapshot = MarketSessionSnapshot.current(for: overview)
        guard let nextBoundary = snapshot.nextBoundary else {
            return
        }

        let delay = nextBoundary.timeIntervalSinceNow + 2
        guard delay > 0 else {
            await loadMarketData(forceRefresh: true)
            return
        }

        do {
            let cappedDelay = min(delay, 24 * 60 * 60)
            try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
        } catch {
            return
        }

        guard !Task.isCancelled else {
            return
        }

        await loadMarketData(forceRefresh: true)
    }
}

private extension MarketsView {
    func showErrorMessage(_ message: String?) {
        guard let message else {
            return
        }

        toastCenter.showErrorMessage(message)
    }
}


private struct MarketAssetDestination: Identifiable, Hashable {
    let symbol: String
    var id: String { symbol }
}

enum MarketListMode: String, CaseIterable, Identifiable {
    case favorites
    case trending
    case leaders

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .favorites:
            L10n.Markets.favorites
        case .trending:
            L10n.Markets.popular
        case .leaders:
            L10n.Markets.leaders
        }
    }

    var icon: String {
        switch self {
        case .favorites:
            AppIcon.Market.favorites
        case .trending:
            AppIcon.Market.popular
        case .leaders:
            AppIcon.Market.leaders
        }
    }
}

struct MarketListModePicker: View {
    @Binding var selection: MarketListMode

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    pickerButtons(usesGlass: true)
                        .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                pickerButtons(usesGlass: false)
                    .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func pickerButtons(usesGlass: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(MarketListMode.allCases) { mode in
                pickerButton(mode, usesGlass: usesGlass)
            }
        }
    }

    @ViewBuilder
    private func pickerButton(_ mode: MarketListMode, usesGlass: Bool) -> some View {
        let isSelected = selection == mode
        let button = Button {
            selection = mode
        } label: {
            Label {
                Text(mode.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            } icon: {
                Image(systemName: mode.icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.ColorToken.brand : AppTheme.ColorToken.icon)
                    .frame(width: 18, height: 18)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)

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
                        .strokeBorder(Color(.separator).opacity(isSelected ? 0.18 : 0.10))
                }
                .shadow(color: .black.opacity(isSelected ? 0.10 : 0.05), radius: 8, y: 3)
        }
    }

    private func glassTint(isSelected: Bool) -> Color {
        isSelected ? AppTheme.ColorToken.brand.opacity(0.18) : Color.white.opacity(0.08)
    }
}

struct MarketStatusCard: View {
    let overview: MarketOverview
    @Environment(\.locale) private var locale
    var referenceDate = Date()
    var cachedAt: Date?
    var cacheIsStale = false
    var usesSkeletonStyle = false

    private var sessionSnapshot: MarketSessionSnapshot {
        MarketSessionSnapshot.current(for: overview, now: referenceDate)
    }

    var body: some View {
        let session = sessionSnapshot.session
        let sessionAccent = usesSkeletonStyle ? Color(.tertiarySystemFill) : session.tint
        let sessionBackground = usesSkeletonStyle ? Color(.secondarySystemFill) : session.tint.opacity(0.16)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(sessionBackground)
                    Image(systemName: session.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(sessionAccent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(session.detail)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if session != .unknown {
                    NextMarketBoundaryBadge(label: nextMarketTimeLabel, time: nextMarketTime)
                }
            }

            MarketSessionTimelineView(
                timeline: sessionTimeline,
                selectedDate: nil,
                usesSkeletonStyle: usesSkeletonStyle
            )
                .frame(height: 25)

            if let cachedAt, cacheIsStale || referenceDate.timeIntervalSince(cachedAt) >= PageCachePolicy.marketOverview.freshTimeToLive {
                Text(L10n.format("markets.cached_as_of_format", locale: locale,
                                 cachedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            MarketIndexProxyPanel(overview: overview)

            Label {
                Text(L10n.Markets.indexProxyDescription)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous)
                .fill(AppTheme.ColorToken.groupedSurface)
        }
    }

    private var nextMarketTimeLabel: LocalizedStringKey {
        sessionSnapshot.session == .closed ? L10n.Markets.nextOpen : L10n.Markets.nextClose
    }

    private var nextMarketTime: String {
        MarketDateFormatter.shortDateTime(sessionSnapshot.nextBoundary) ?? AppFormatter.placeholder
    }

    private var sessionTimeline: MarketSessionTimeline? {
        let intervals = MarketSessionSchedule.intervals(
            from: overview.calendar,
            overnightDays: overview.overnightCalendar
        )
        let targetInterval = MarketSessionSchedule.activeInterval(at: referenceDate, in: intervals)
            ?? intervals.first { $0.end > referenceDate }

        guard let targetInterval else {
            return nil
        }

        return MarketSessionTimeline(
            progress: MarketSessionSchedule.progress(for: targetInterval, in: intervals, at: referenceDate)
        )
    }
}

private struct NextMarketBoundaryBadge: View {
    let label: LocalizedStringKey
    let time: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(time)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum MarketSession {
    case regular
    case preMarket
    case afterHours
    case overnight
    case closed
    case unknown

    static func session(forPhase phase: String?) -> MarketSession? {
        switch normalizedPhase(phase) {
        case "open":
            .regular
        case "pre_market", "premarket":
            .preMarket
        case "post_market", "postmarket", "after_hours":
            .afterHours
        case "overnight":
            .overnight
        case "closed", "close":
            .closed
        default:
            nil
        }
    }

    static func session(for kind: MarketSessionKind) -> MarketSession {
        switch kind {
        case .overnight:
            .overnight
        case .preMarket:
            .preMarket
        case .regular:
            .regular
        case .afterHours:
            .afterHours
        }
    }

    private static func normalizedPhase(_ phase: String?) -> String {
        phase?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_") ?? ""
    }

    var title: LocalizedStringKey {
        switch self {
        case .regular:
            L10n.Markets.open
        case .preMarket:
            L10n.Markets.preMarket
        case .afterHours:
            L10n.Markets.afterHours
        case .overnight:
            L10n.Markets.overnight
        case .unknown:
            "markets.session_unavailable"
        case .closed:
            L10n.Markets.closed
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .regular:
            L10n.Markets.regularSession
        case .preMarket, .afterHours, .overnight:
            L10n.Markets.extendedSession
        case .unknown:
            "markets.schedule_unavailable"
        case .closed:
            L10n.Markets.marketClosed
        }
    }

    var icon: String {
        switch self {
        case .regular:
            AppIcon.Market.regular
        case .preMarket:
            AppIcon.Market.preMarket
        case .afterHours:
            AppIcon.Market.afterHours
        case .overnight:
            AppIcon.Market.overnight
        case .closed, .unknown:
            AppIcon.Market.closed
        }
    }

    var tint: Color {
        switch self {
        case .regular:
            AppTheme.ColorToken.brand
        case .preMarket:
            AppTheme.ColorToken.brand
        case .afterHours:
            Color.orange
        case .overnight:
            Color.indigo
        case .closed, .unknown:
            AppTheme.ColorToken.icon
        }
    }
}

struct MarketSessionSnapshot {
    let session: MarketSession
    let nextBoundary: Date?

    static func current(for overview: MarketOverview, now referenceDate: Date = Date()) -> MarketSessionSnapshot {
        let nextClockOpen = AlpacaDateParser.date(overview.clock.nextOpen).flatMap { $0 > referenceDate ? $0 : nil }
        let intervals = MarketSessionSchedule.intervals(
            from: overview.calendar,
            overnightDays: overview.overnightCalendar
        )

        if let activeInterval = MarketSessionSchedule.activeInterval(at: referenceDate, in: intervals) {
            return MarketSessionSnapshot(
                session: MarketSession.session(for: activeInterval.session),
                nextBoundary: activeInterval.end
            )
        }

        if intervals.isEmpty {
            let clock = overview.clock
            if let clockDate = AlpacaDateParser.date(clock.timestamp),
               let session = MarketSession.session(forPhase: clock.phase) {
                let age = referenceDate.timeIntervalSince(clockDate)
                let boundary = clockBoundary(for: session, clock: clock)
                if age >= 0, let boundary, boundary > referenceDate {
                    return MarketSessionSnapshot(session: session, nextBoundary: boundary)
                }
                if abs(age) < PageCachePolicy.marketOverview.freshTimeToLive, boundary == nil {
                    return MarketSessionSnapshot(session: session, nextBoundary: nil)
                }
            }
            return MarketSessionSnapshot(session: .unknown, nextBoundary: nextClockOpen)
        }

        let nextOpen = intervals
            .filter { $0.start > referenceDate }
            .min { $0.start < $1.start }?
            .start
            ?? nextClockOpen

        return MarketSessionSnapshot(session: nextOpen == nil ? .unknown : .closed, nextBoundary: nextOpen)
    }

    private static func clockBoundary(for session: MarketSession, clock: AlpacaMarketClock) -> Date? {
        if let phaseEnd = AlpacaDateParser.date(clock.phaseUntil) { return phaseEnd }
        switch session {
        case .regular: return AlpacaDateParser.date(clock.nextClose)
        case .closed: return AlpacaDateParser.date(clock.nextOpen)
        default: return nil
        }
    }
}

private struct MarketSymbolSection: View {
    let mode: MarketListMode
    let overview: MarketOverview
    @Environment(AppModel.self) private var app

    var body: some View {
        let items = displayedItems

        VStack(spacing: 0) {
            switch mode {
            case .favorites:
                if !app.hasLoadedFavoriteMarketSymbols && app.isLoadingFavoriteMarketSymbols && app.favoriteMarketSymbols.isEmpty {
                    MarketSymbolRowsSkeleton(rowCount: 3)
                } else if items.isEmpty {
                    EmptyFavoriteView()
                } else {
                    ForEach(items) { item in
                        MarketSymbolRow(item: item)
                    }
                }
            case .leaders:
                if items.isEmpty {
                    EmptyMarketRow(text: L10n.Markets.noActivityData)
                } else {
                    ForEach(items) { item in
                        MarketSymbolRow(item: item)
                    }
                }
            case .trending:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var displayedItems: [MarketSymbolItem] {
        switch mode {
        case .favorites:
            favoriteItems
        case .leaders:
            overview.mostActive.map(MarketSymbolItem.init(activeSymbol:))
        case .trending:
            []
        }
    }

    private var favoriteItems: [MarketSymbolItem] {
        let favoriteSymbols = app.favoriteMarketSymbols
        guard !favoriteSymbols.isEmpty else {
            return []
        }

        let activeBySymbol = overview.mostActive.reduce(into: [String: MarketActiveSymbol]()) { result, symbol in
            result[Self.normalizedSymbol(symbol.symbol)] = symbol
        }
        let indexBySymbol = overview.indexQuotes.reduce(into: [String: MarketIndexQuote]()) { result, quote in
            result[Self.normalizedSymbol(quote.symbol)] = quote
        }

        return favoriteSymbols.map { symbol in
            let normalizedSymbol = Self.normalizedSymbol(symbol)
            let resolvedCompanyName = app.favoriteMarketAssetBySymbol[normalizedSymbol]?.name
                ?? app.lookupSearchAsset(symbol: normalizedSymbol)?.displayName

            if let favoriteQuote = app.favoriteMarketQuotesBySymbol[normalizedSymbol] {
                return MarketSymbolItem(activeSymbol: favoriteQuote, companyName: resolvedCompanyName)
            }

            if let activeSymbol = activeBySymbol[normalizedSymbol] {
                return MarketSymbolItem(activeSymbol: activeSymbol, companyName: resolvedCompanyName)
            }

            if let indexQuote = indexBySymbol[normalizedSymbol] {
                return MarketSymbolItem(indexQuote: indexQuote, companyName: resolvedCompanyName)
            }

            return MarketSymbolItem(symbol: normalizedSymbol, companyName: resolvedCompanyName, price: nil, percentChange: nil, isPositive: true)
        }
    }

    private static func normalizedSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

struct MarketSymbolRow: View {
    let item: MarketSymbolItem

    var body: some View {
        NavigationLink {
            AssetDetailView(symbol: item.symbol)
        } label: {
            HStack(spacing: 14) {
                SymbolLogoView(symbol: item.symbol, size: 38, usesGlass: false)

                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: item.symbol)
                        .font(AppTypography.rowTitle.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(item.companyName)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(AppFormatter.money(item.price))
                        .font(AppTypography.rowValue)
                        .lineLimit(1)
                    Text(AppFormatter.signedPercent(item.percentChange))
                        .font(AppTypography.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(percentTint)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 62)
        .padding(.vertical, 12)
    }

    private var percentTint: Color {
        guard item.percentChange != nil else {
            return .secondary
        }

        return item.isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }
}

struct MarketSymbolItem: Identifiable, Equatable {
    let symbol: String
    let companyName: String
    let price: Double?
    let percentChange: Double?
    let isPositive: Bool

    var id: String {
        symbol
    }

    init(symbol: String, companyName: String? = nil, price: Double?, percentChange: Double?, isPositive: Bool) {
        self.symbol = symbol
        self.companyName = AppFormatter.displayText(companyName)
        self.price = price
        self.percentChange = percentChange
        self.isPositive = isPositive
    }

    init(activeSymbol: MarketActiveSymbol) {
        self.symbol = activeSymbol.symbol
        self.companyName = AppFormatter.displayText(activeSymbol.companyName)
        self.price = activeSymbol.price
        self.percentChange = activeSymbol.percentChange
        self.isPositive = activeSymbol.isPositive
    }

    init(activeSymbol: MarketActiveSymbol, companyName fallbackCompanyName: String?) {
        self.symbol = activeSymbol.symbol
        self.companyName = AppFormatter.displayText(activeSymbol.companyName ?? fallbackCompanyName)
        self.price = activeSymbol.price
        self.percentChange = activeSymbol.percentChange
        self.isPositive = activeSymbol.isPositive
    }

    init(indexQuote: MarketIndexQuote, companyName fallbackCompanyName: String?) {
        self.symbol = indexQuote.symbol
        self.companyName = fallbackCompanyName ?? indexQuote.title
        self.price = indexQuote.price
        self.percentChange = indexQuote.percentChange
        self.isPositive = indexQuote.isPositive
    }
}

private struct EmptyMarketRow: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(AppTypography.detail)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
    }
}

private struct EmptyFavoriteView: View {
    var body: some View {
        AppEmptyStateView(
            title: L10n.Common.noData,
            systemImage: AppIcon.Market.favorites,
            style: .inline
        )
    }
}

private enum MarketDateFormatter {
    static func date(_ text: String?) -> Date? {
        AlpacaDateParser.date(text)
    }

    static func shortDateTime(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func shortDateTime(_ text: String?) -> String? {
        let date = date(text)
        guard let date else {
            return nil
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    NavigationStack {
        MarketsView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
