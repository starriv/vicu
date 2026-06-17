import RxSwift
import SwiftUI

struct MarketsView: View {
    @Environment(AppModel.self) private var app
    @State private var overview: MarketOverview?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedMarketList: MarketListMode = .favorites

    var body: some View {
        BasicLayout(L10n.Markets.title, style: .scroll(spacing: 18)) {
            MarketTitleActions {
                Task { await loadMarketData() }
            }
        } content: {
            if !app.hasCredentials {
                AppEmptyStateView(
                    title: L10n.Common.noData,
                    systemImage: AppIcon.More.alpaca
                )
            } else if let overview = overview ?? app.cachedMarketOverview {
                if let errorMessage {
                    ErrorBanner(message: errorMessage) {
                        Task { await loadMarketData() }
                    }
                }

                MarketStatusCard(overview: overview)
                MarketListModePicker(selection: $selectedMarketList)
                if selectedMarketList == .favorites, let favoritesError = app.favoriteMarketSymbolsError {
                    ErrorBanner(message: favoritesError) {
                        Task { await app.refreshFavoriteMarketSymbols() }
                    }
                }
                MarketSymbolSection(mode: selectedMarketList, overview: overview)
            } else if isLoading || errorMessage == nil {
                MarketOverviewSkeleton()
            } else {
                AppEmptyStateView(
                    title: L10n.Common.noData,
                    systemImage: AppIcon.Tab.markets
                )
            }
        }
        .task {
            await loadMarketDataIfNeeded()
            await app.refreshFavoriteMarketSymbols()
        }
        .task(id: marketBoundaryRefreshID) {
            await refreshMarketDataAtNextBoundary()
        }
        .refreshable {
            await loadMarketData()
            await app.refreshFavoriteMarketSymbols()
        }
    }

    private var marketBoundaryRefreshID: String {
        guard let overview else {
            return "none"
        }

        let snapshot = MarketSessionSnapshot.current(for: overview)
        let boundary = snapshot.nextBoundary?.timeIntervalSince1970 ?? 0
        return "\(snapshot.session)-\(boundary)"
    }

    private func loadMarketDataIfNeeded() async {
        if overview == nil, let cachedOverview = app.cachedMarketOverview {
            overview = cachedOverview
        }

        await loadMarketData()
    }

    private func loadMarketData() async {
        guard app.hasCredentials else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let latestOverview = try await app.fetchMarketOverview()
            overview = latestOverview
        } catch where error.isRequestCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
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
            await loadMarketData()
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

        await loadMarketData()
    }
}

private struct MarketIndexRealtimePrice {
    let symbol: String
    let price: Double

    init?(event: AssetRealtimeEvent) {
        switch event {
        case .trade(let trade):
            guard let price = trade.price, Self.isValidMarketPrice(price) else {
                return nil
            }
            symbol = Self.normalizedSymbol(trade.symbol)
            self.price = price
        case .quote(let quote):
            guard let price = Self.quotePrice(quote) else {
                return nil
            }
            symbol = Self.normalizedSymbol(quote.symbol)
            self.price = price
        case .minuteBar(let bar), .updatedBar(let bar), .dailyBar(let bar):
            guard let price = bar.close, Self.isValidMarketPrice(price) else {
                return nil
            }
            symbol = Self.normalizedSymbol(bar.symbol)
            self.price = price
        case .connection, .status:
            return nil
        }
    }

    private static func quotePrice(_ quote: AlpacaRealtimeQuote) -> Double? {
        let prices = [quote.bidPrice, quote.askPrice]
            .compactMap { price -> Double? in
                guard let price, isValidMarketPrice(price) else {
                    return nil
                }
                return price
            }

        guard !prices.isEmpty else {
            return nil
        }

        return prices.reduce(0, +) / Double(prices.count)
    }

    private static func normalizedSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func isValidMarketPrice(_ price: Double) -> Bool {
        price.isFinite && price > 0
    }
}

private enum MarketIndexRealtimeReducer {
    static func latestPrices(from events: [AssetRealtimeEvent]) -> [MarketIndexRealtimePrice]? {
        var latestBySymbol: [String: MarketIndexRealtimePrice] = [:]
        for event in events {
            guard let update = MarketIndexRealtimePrice(event: event) else {
                continue
            }

            latestBySymbol[update.symbol] = update
        }

        return latestBySymbol.isEmpty ? nil : Array(latestBySymbol.values)
    }
}

private struct MarketTitleActions: View {
    let refresh: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            glassActions
        } else {
            fallbackActions
        }
    }

    @available(iOS 26.0, *)
    private var glassActions: some View {
        actions
            .glassEffect(
                .regular.tint(Color.white.opacity(0.10)).interactive(),
                in: .capsule
            )
    }

    private var fallbackActions: some View {
        actions
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color(.separator).opacity(0.16))
            }
    }

    private var actions: some View {
        HStack(spacing: 14) {
            NavigationLink {
                MarketSearchView()
            } label: {
                Image(systemName: AppIcon.Market.search)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 30, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Markets.searchTitle)

            Menu {
                Button {
                    refresh()
                } label: {
                    Label(L10n.Common.refresh, systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: AppIcon.Market.more)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 30, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(width: 112, height: 44)
        .contentShape(Capsule())
    }
}

private struct MarketSearchSortMenu: View {
    @Binding var selection: MarketMostActiveSort

    var body: some View {
        if #available(iOS 26.0, *) {
            glassMenu
        } else {
            fallbackMenu
        }
    }

    @available(iOS 26.0, *)
    private var glassMenu: some View {
        menu
            .glassEffect(
                .regular.tint(Color.white.opacity(0.10)).interactive(),
                in: .capsule
            )
    }

    private var fallbackMenu: some View {
        menu
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color(.separator).opacity(0.16))
            }
    }

    private var menu: some View {
        Menu {
            ForEach(MarketMostActiveSort.displayCases) { sort in
                Button {
                    selection = sort
                } label: {
                    Label(sort.title, systemImage: selection == sort ? "checkmark" : sort.icon)
                }
            }
        } label: {
            Image(systemName: selection.icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
            .foregroundStyle(.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Markets.searchPopularTitle)
    }
}

enum MarketSearchPresentation {
    case marketNavigation
    case globalTab

    var showsPageTitle: Bool {
        self == .globalTab
    }

    var usesSystemSearchField: Bool {
        self == .globalTab
    }

    var hidesTabBar: Bool {
        self == .marketNavigation
    }

    var hidesNavigationBar: Bool {
        self == .globalTab
    }
}

struct MarketSearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Binding private var externalQuery: String
    private let usesExternalQuery: Bool
    private let presentation: MarketSearchPresentation
    @State private var localQuery = ""
    @State private var results: [MarketSearchResult] = []
    @State private var popularSymbols: [MarketActiveSymbol] = []
    @State private var popularSort: MarketMostActiveSort = .trades
    @State private var isSearching = false
    @State private var isLoadingPopularSymbols = false
    @State private var errorMessage: String?
    @State private var popularSymbolsErrorMessage: String?
    @State private var searchPlaceholderSymbol = AppModel.searchPlaceholderFallbackSymbol
    @State private var searchPipeline = MarketSearchPipeline()
    @FocusState private var isSearchFocused: Bool

    private var query: String {
        usesExternalQuery ? externalQuery : localQuery
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { query },
            set: { updateQuery($0) }
        )
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        query: Binding<String>? = nil,
        presentation: MarketSearchPresentation = .marketNavigation
    ) {
        _externalQuery = query ?? .constant("")
        usesExternalQuery = query != nil
        self.presentation = presentation
    }

    var body: some View {
        Group {
            if presentation.showsPageTitle {
                titledBody
            } else {
                immersiveBody
            }
        }
        .toolbar(presentation.hidesTabBar ? .hidden : .automatic, for: .tabBar)
        .toolbar(presentation.hidesNavigationBar ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if !presentation.showsPageTitle, normalizedQuery.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    popularSortPicker
                }
            }
        }
        .task {
            if !presentation.usesSystemSearchField {
                isSearchFocused = true
            }
            bindSearchPipelineIfNeeded()
            await app.refreshFavoriteMarketSymbols()
        }
        .task(id: popularSort) {
            await loadPopularSymbols()
        }
        .onChange(of: normalizedQuery) { _, newValue in
            searchPipeline.accept(newValue)
        }
        .onDisappear {
            searchPipeline.cancel()
        }
    }

    private var titledBody: some View {
        BasicLayout(L10n.Markets.searchTitle, style: .scroll(spacing: 16)) {
            if normalizedQuery.isEmpty {
                popularSortPicker
            }
        } content: {
            searchContent
        }
    }

    private var immersiveBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.top, AppTheme.Spacing.pageTop)
            .padding(.bottom, AppTheme.Spacing.pageBottom + 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomSearchField
        }
    }

    private var popularSortPicker: some View {
        MarketSearchSortMenu(selection: $popularSort)
    }

    private func updateQuery(_ newValue: String) {
        if usesExternalQuery {
            externalQuery = newValue
        } else {
            localQuery = newValue
        }
    }

    private var bottomSearchField: some View {
        Group {
            if #available(iOS 26.0, *) {
                glassSearchField
            } else {
                fallbackSearchField
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    @available(iOS 26.0, *)
    private var glassSearchField: some View {
        GlassEffectContainer(spacing: 10) {
            searchFieldContent(usesGlass: true)
        }
    }

    private var fallbackSearchField: some View {
        searchFieldContent(usesGlass: false)
    }

    private func searchFieldContent(usesGlass: Bool) -> some View {
        HStack(spacing: 10) {
            searchInputCapsule(usesGlass: usesGlass)
                .frame(maxWidth: .infinity)

            if !query.isEmpty || !presentation.usesSystemSearchField {
                searchExitButton(usesGlass: usesGlass)
            }
        }
        .animation(.snappy(duration: 0.18), value: query.isEmpty)
    }

    @ViewBuilder
    private func searchInputCapsule(usesGlass: Bool) -> some View {
        let content = HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(searchIconColor)
                .frame(width: 24, height: 24)

            TextField("", text: queryBinding, prompt: Text(searchPlaceholderSymbol).foregroundStyle(searchPlaceholderColor))
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(searchTextColor)
                .tint(AppTheme.ColorToken.brand)
                .submitLabel(.search)
                .onSubmit {
                    searchPipeline.submit(normalizedQuery)
                }
        }
        .font(.title2.weight(.medium))
        .padding(.horizontal, 14)
        .frame(height: 52)

        if usesGlass {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(
                        .regular.tint(searchGlassTint).interactive(),
                        in: .capsule
                    )
            } else {
                content
            }
        } else {
            content
                .background(searchFieldBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(searchFieldBorder)
                }
                .shadow(color: searchFieldShadowColor, radius: 12, y: 5)
        }
    }

    @ViewBuilder
    private func searchExitButton(usesGlass: Bool) -> some View {
        let button = Button {
            if query.isEmpty {
                dismiss()
            } else {
                updateQuery("")
                isSearchFocused = true
            }
        } label: {
            Image(systemName: query.isEmpty ? "chevron.down" : "xmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(clearButtonForeground)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(query.isEmpty ? L10n.Common.close : L10n.Common.clear)
        .contentTransition(.symbolEffect(.replace))

        if usesGlass {
            if #available(iOS 26.0, *) {
                button
                    .glassEffect(
                        .regular.tint(searchGlassTint).interactive(),
                        in: .circle
                    )
            } else {
                button
            }
        } else {
            button
                .background(searchFieldBackground, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(searchFieldBorder)
                }
                .shadow(color: searchFieldShadowColor, radius: 10, y: 4)
        }
    }

    private var searchFieldBackground: Color {
        colorScheme == .light ? Color(.systemBackground) : Color(.secondarySystemGroupedBackground)
    }

    private var searchFieldBorder: Color {
        colorScheme == .light ? Color(.separator).opacity(0.18) : Color(.separator).opacity(0.22)
    }

    private var searchFieldShadowColor: Color {
        .black.opacity(colorScheme == .light ? 0.05 : 0.18)
    }

    private var searchIconColor: Color {
        colorScheme == .light ? Color(.secondaryLabel) : Color(.label)
    }

    private var searchPlaceholderColor: Color {
        colorScheme == .light ? Color(.secondaryLabel) : Color(.tertiaryLabel)
    }

    private var searchTextColor: Color {
        Color(.label)
    }

    private var clearButtonForeground: Color {
        colorScheme == .light ? Color(.label) : Color(.label)
    }

    private var searchGlassTint: Color {
        colorScheme == .light ? Color.white.opacity(0.14) : Color.white.opacity(0.08)
    }

    @ViewBuilder
    private var searchContent: some View {
        if !app.hasCredentials {
            AppEmptyStateView(
                title: L10n.Common.noData,
                systemImage: AppIcon.More.alpaca
            )
        } else if normalizedQuery.isEmpty && isLoadingPopularSymbols && popularSymbols.isEmpty {
            MarketSearchPopularSkeleton(rowCount: 7)
        } else if normalizedQuery.isEmpty {
            MarketSearchPopularView(
                symbols: popularSymbols,
                sort: popularSort,
                isLoading: isLoadingPopularSymbols,
                errorMessage: popularSymbolsErrorMessage
            ) {
                Task { await loadPopularSymbols(forceReload: true) }
            }
        } else if let errorMessage {
            ErrorBanner(message: errorMessage) {
                searchPipeline.submit(normalizedQuery)
            }
        } else if isSearching && results.isEmpty {
            MarketSearchResultsSkeleton(rowCount: 7)
        } else if results.isEmpty {
            AppEmptyStateView(
                title: L10n.Common.noData,
                systemImage: "magnifyingglass"
            )
        } else {
            MarketSearchPlainList {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    MarketSearchResultRow(result: result)

                    if index < results.count - 1 {
                        MarketSearchDivider()
                    }
                }
            }
        }
    }

    @MainActor
    private func loadPopularSymbols(forceReload: Bool = false) async {
        guard app.hasCredentials else {
            popularSymbols = []
            popularSymbolsErrorMessage = nil
            isLoadingPopularSymbols = false
            return
        }

        if !forceReload, isLoadingPopularSymbols {
            return
        }

        isLoadingPopularSymbols = true
        popularSymbolsErrorMessage = nil
        defer { isLoadingPopularSymbols = false }

        do {
            popularSymbols = try await app.fetchSearchPopularMarketSymbols(limit: 12, sort: popularSort)
            searchPlaceholderSymbol = AppModel.searchPlaceholderSymbol(from: popularSymbols)
        } catch where error.isRequestCancellation {
            return
        } catch {
            popularSymbolsErrorMessage = error.localizedDescription
        }
    }

    private func bindSearchPipelineIfNeeded() {
        searchPipeline.bind(
            hasCredentials: { app.hasCredentials },
            search: { query in
                try await app.searchMarketSymbols(query, limit: 20)
            },
            apply: applySearchState
        )
        searchPipeline.accept(normalizedQuery)
    }

    private func applySearchState(_ state: MarketSearchPipeline.State) {
        switch state {
        case .idle:
            results = []
            errorMessage = nil
            isSearching = false
        case .searching(_):
            errorMessage = nil
            isSearching = true
        case .success(let query, let searchResults):
            guard query == normalizedQuery else {
                return
            }

            results = searchResults
            errorMessage = nil
            isSearching = false
        case .failure(let query, let message):
            guard query == normalizedQuery else {
                return
            }

            results = []
            errorMessage = message
            isSearching = false
        }
    }
}

@MainActor
private final class MarketSearchPipeline {
    enum State {
        case idle
        case searching(String)
        case success(String, [MarketSearchResult])
        case failure(String, String)
    }

    private struct SearchEvent {
        let query: String
        let force: Bool
    }

    private let inputSubject = PublishSubject<String>()
    private let submitSubject = PublishSubject<String>()
    private let disposeBag = DisposeBag()
    private var searchTask: Task<Void, Never>?
    private var isBound = false
    private var activeQuery: String?
    private var lastStartedQuery: String?
    private var lastStartedAt: Date?
    private var hasCredentials: (@MainActor () -> Bool)?
    private var search: (@MainActor (String) async throws -> [MarketSearchResult])?
    private var apply: (@MainActor (State) -> Void)?

    func bind(
        hasCredentials: @escaping @MainActor () -> Bool,
        search: @escaping @MainActor (String) async throws -> [MarketSearchResult],
        apply: @escaping @MainActor (State) -> Void
    ) {
        guard !isBound else {
            return
        }

        isBound = true
        self.hasCredentials = hasCredentials
        self.search = search
        self.apply = apply

        let debouncedInput = inputSubject
            .map(Self.normalizedQuery)
            .distinctUntilChanged()
            .debounce(.milliseconds(240), scheduler: MainScheduler.instance)
            .map { SearchEvent(query: $0, force: false) }

        let immediateSubmit = submitSubject
            .map(Self.normalizedQuery)
            .map { SearchEvent(query: $0, force: true) }

        Observable.merge(debouncedInput, immediateSubmit)
            .subscribe(onNext: { [weak self] event in
                Task { @MainActor in
                    self?.startSearch(event.query, force: event.force)
                }
            })
            .disposed(by: disposeBag)
    }

    func accept(_ query: String) {
        inputSubject.onNext(query)
    }

    func submit(_ query: String) {
        submitSubject.onNext(query)
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        activeQuery = nil
    }

    private static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startSearch(_ query: String, force: Bool = false) {
        guard let hasCredentials, let search, let apply else {
            return
        }

        guard !query.isEmpty, hasCredentials() else {
            searchTask?.cancel()
            activeQuery = nil
            lastStartedQuery = nil
            apply(.idle)
            return
        }

        if !force, shouldSkipDuplicateSearch(query) {
            return
        }

        searchTask?.cancel()
        activeQuery = query
        lastStartedQuery = query
        lastStartedAt = Date()
        apply(.searching(query))
        searchTask = Task { @MainActor in
            do {
                let results = try await search(query)
                try Task.checkCancellation()
                if self.activeQuery == query {
                    self.activeQuery = nil
                }
                apply(.success(query, results))
            } catch where error.isRequestCancellation {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                if self.activeQuery == query {
                    self.activeQuery = nil
                }
                apply(.failure(query, error.localizedDescription))
            }
        }
    }

    private func shouldSkipDuplicateSearch(_ query: String) -> Bool {
        if activeQuery == query {
            return true
        }

        guard lastStartedQuery == query, let lastStartedAt else {
            return false
        }

        return Date().timeIntervalSince(lastStartedAt) < 0.35
    }
}

private struct MarketSearchPopularView: View {
    let symbols: [MarketActiveSymbol]
    let sort: MarketMostActiveSort
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: AppIcon.Market.popular)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.ColorToken.warning)
                        .accessibilityHidden(true)

                    Text(L10n.Markets.searchPopularTitle)
                        .font(AppTypography.rowTitle.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Text(sort.searchPopularSubtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if isLoading && symbols.isEmpty {
                MarketSearchResultsSkeleton(rowCount: 7)
            } else if symbols.isEmpty, let errorMessage {
                ErrorBanner(message: errorMessage) {
                    retry()
                }
            } else if symbols.isEmpty {
                EmptyMarketRow(text: L10n.Markets.searchPopularUnavailable)
            } else {
                MarketSearchPlainList {
                    ForEach(Array(symbols.enumerated()), id: \.element.id) { index, symbol in
                        MarketSearchPopularRow(symbol: symbol)

                        if index < symbols.count - 1 {
                            MarketSearchDivider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarketSearchPlainList<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
    }
}

private struct MarketSearchDivider: View {
    var body: some View {
        Divider()
    }
}

private struct MarketSearchPopularRow: View {
    let symbol: MarketActiveSymbol
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 14) {
            NavigationLink {
                AssetDetailView(symbol: symbol.symbol)
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: symbol.symbol)
                            .font(AppTypography.rowTitle.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(AppFormatter.displayText(symbol.companyName))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(AppFormatter.money(symbol.price))
                            .font(AppTypography.rowValue)
                            .lineLimit(1)

                        Text(AppFormatter.signedPercent(symbol.percentChange))
                            .font(AppTypography.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(symbol.isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await app.toggleFavoriteMarketSymbol(symbol.symbol) }
            } label: {
                Image(systemName: app.isFavoriteMarketSymbol(symbol.symbol) ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(app.isFavoriteMarketSymbol(symbol.symbol) ? AppTheme.ColorToken.brand : AppTheme.ColorToken.icon)
                    .frame(width: 42, height: 42)
                    .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 64)
        .padding(.vertical, 10)
    }
}

private struct MarketSearchResultRow: View {
    let result: MarketSearchResult
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 14) {
            NavigationLink {
                AssetDetailView(symbol: result.symbol)
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: result.symbol)
                            .font(AppTypography.rowTitle.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(result.companyName)
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(AppFormatter.money(result.price))
                            .font(AppTypography.rowValue)
                            .lineLimit(1)

                        Text(AppFormatter.signedPercent(result.percentChange))
                            .font(AppTypography.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(result.isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await app.toggleFavoriteMarketSymbol(result.symbol) }
            } label: {
                Image(systemName: app.isFavoriteMarketSymbol(result.symbol) ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(app.isFavoriteMarketSymbol(result.symbol) ? AppTheme.ColorToken.brand : AppTheme.ColorToken.icon)
                    .frame(width: 42, height: 42)
                    .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 64)
        .padding(.vertical, 10)
    }
}

enum MarketListMode: String, CaseIterable, Identifiable {
    case favorites
    case popular

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .favorites:
            L10n.Markets.favorites
        case .popular:
            L10n.Markets.popular
        }
    }

    var icon: String {
        switch self {
        case .favorites:
            AppIcon.Market.favorites
        case .popular:
            AppIcon.Market.popular
        }
    }
}

struct MarketListModePicker: View {
    @Binding var selection: MarketListMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(iOS 26.0, *) {
                glassContent
            } else {
                fallbackContent
            }
        }
        .scrollClipDisabled()
    }

    @available(iOS 26.0, *)
    private var glassContent: some View {
        GlassEffectContainer(spacing: 10) {
            pickerButtons(usesGlass: true)
        }
        .padding(.vertical, 2)
    }

    private var fallbackContent: some View {
        pickerButtons(usesGlass: false)
            .padding(.vertical, 2)
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

    private var sessionSnapshot: MarketSessionSnapshot {
        MarketSessionSnapshot.current(for: overview)
    }

    var body: some View {
        let session = sessionSnapshot.session

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(session.tint.opacity(0.16))
                    Image(systemName: session.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(session.tint)
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

                NextMarketBoundaryBadge(label: nextMarketTimeLabel, time: nextMarketTime)
            }

            MarketSessionTimelineView(timeline: sessionTimeline, selectedDate: nil)
                .frame(height: 25)

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
        let referenceDate = AlpacaDateParser.date(overview.clock.timestamp) ?? Date()
        let intervals = MarketSessionSchedule.intervals(
            from: overview.calendar,
            overnightDays: overview.overnightCalendar
        )
        let targetInterval = MarketSessionSchedule.activeInterval(
            at: referenceDate,
            in: overview.calendar,
            overnightDays: overview.overnightCalendar
        )
            ?? intervals.first { $0.end > referenceDate }
            ?? intervals.last

        guard let targetInterval else {
            return nil
        }

        return MarketSessionTimeline(
            progress: MarketSessionSchedule.progress(
                for: targetInterval,
                in: overview.calendar,
                overnightDays: overview.overnightCalendar,
                at: referenceDate
            )
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

private enum MarketSession {
    case regular
    case preMarket
    case afterHours
    case overnight
    case closed

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
        case .closed:
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
        case .closed:
            AppTheme.ColorToken.icon
        }
    }

    var activePriority: Int {
        switch self {
        case .regular:
            0
        case .preMarket:
            1
        case .afterHours:
            2
        case .overnight:
            3
        case .closed:
            4
        }
    }
}

private struct MarketSessionSnapshot {
    let session: MarketSession
    let nextBoundary: Date?

    static func current(for overview: MarketOverview) -> MarketSessionSnapshot {
        let referenceDate = AlpacaDateParser.date(overview.clock.timestamp) ?? Date()
        let intervals = MarketTradingInterval.intervals(
            from: overview.calendar,
            overnightDays: overview.overnightCalendar
        )

        if let activeInterval = intervals.activeInterval(at: referenceDate) {
            return MarketSessionSnapshot(session: activeInterval.session, nextBoundary: activeInterval.end)
        }

        guard !intervals.isEmpty else {
            if let clockSession = MarketSession.session(forPhase: overview.clock.phase),
               clockSession != .closed {
                return MarketSessionSnapshot(
                    session: clockSession,
                    nextBoundary: clockBoundary(for: clockSession, clock: overview.clock)
                )
            }

            return MarketSessionSnapshot(
                session: .closed,
                nextBoundary: AlpacaDateParser.date(overview.clock.nextOpen)
            )
        }

        let nextOpen = intervals
            .filter { $0.start > referenceDate }
            .min { $0.start < $1.start }?
            .start
            ?? AlpacaDateParser.date(overview.clock.nextOpen)

        return MarketSessionSnapshot(session: .closed, nextBoundary: nextOpen)
    }

    private static func clockBoundary(for session: MarketSession, clock: AlpacaMarketClock) -> Date? {
        AlpacaDateParser.date(clock.phaseUntil)
            ?? AlpacaDateParser.date(session == .closed ? clock.nextOpen : clock.nextClose)
    }
}

private struct MarketTradingInterval {
    let session: MarketSession
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }

    static func intervals(
        from days: [AlpacaCalendarDay],
        overnightDays: [AlpacaCalendarDay]
    ) -> [MarketTradingInterval] {
        MarketSessionSchedule.intervals(from: days, overnightDays: overnightDays)
            .map { interval in
                MarketTradingInterval(
                    session: MarketSession.session(for: interval.session),
                    start: interval.start,
                    end: interval.end
                )
            }
    }
}

private extension Array where Element == MarketTradingInterval {
    func activeInterval(at date: Date) -> MarketTradingInterval? {
        filter { $0.contains(date) }
            .min { lhs, rhs in
                if lhs.session.activePriority == rhs.session.activePriority {
                    return lhs.start < rhs.start
                }

                return lhs.session.activePriority < rhs.session.activePriority
            }
    }
}

private struct MarketIndexProxyPanel: View {
    private static let realtimeVisualRefreshInterval = RxTimeInterval.milliseconds(1_000)
    private static let realtimeVisualRefreshMaxBatchSize = 512
    private static let snapshotFallbackInitialDelay: UInt64 = 5_000_000_000
    private static let snapshotFallbackInterval: UInt64 = 15_000_000_000
    private static let streamQuietThreshold: TimeInterval = 10

    @Environment(AppModel.self) private var app
    let overview: MarketOverview
    @State private var liveQuotes: [MarketIndexQuote] = []
    @State private var realtimeDisposeBag = DisposeBag()
    @State private var lastRealtimeUpdateAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.Markets.indexProxySource)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(symbolSummary)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            IndexProxyList(quotes: displayedQuotes)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: baselineID) {
            liveQuotes = overview.indexQuotes
        }
        .task(id: realtimeStreamID) {
            bindRealtime()
        }
        .task(id: snapshotFallbackID) {
            await runSnapshotFallback()
        }
        .onDisappear {
            stopRealtime()
        }
    }

    private var displayedQuotes: [MarketIndexQuote] {
        liveQuotes.isEmpty ? overview.indexQuotes : liveQuotes
    }

    private var baselineID: String {
        overview.indexQuotes
            .map { quote in
                [
                    quote.symbol,
                    quote.price.map(String.init(describing:)) ?? "",
                    quote.change.map(String.init(describing:)) ?? "",
                    quote.percentChange.map(String.init(describing:)) ?? ""
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private var realtimeStreamID: String {
        guard app.hasCredentials, !overview.indexQuotes.isEmpty else {
            return "none"
        }

        return "\(realtimeFeed.rawValue):\(symbolSummary)"
    }

    private var snapshotFallbackID: String {
        guard app.hasCredentials, !overview.indexQuotes.isEmpty else {
            return "none"
        }

        return "snapshot:\(realtimeFeed.rawValue):\(symbolSummary)"
    }

    private var symbolSummary: String {
        overview.indexQuotes
            .map { $0.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var realtimeFeed: AlpacaMarketDataFeed {
        MarketSessionSnapshot.current(for: overview).session == .overnight ? .overnight : .iex
    }

    private func bindRealtime() {
        guard app.hasCredentials, !overview.indexQuotes.isEmpty else {
            stopRealtime()
            return
        }

        do {
            let source = try app.streamAssetMarketData(
                symbols: overview.indexQuotes.map(\.symbol),
                feed: realtimeFeed,
                channels: AlpacaRealtimeChannel.tradeQuote
            )
            let disposeBag = DisposeBag()
            source
                .buffer(
                    timeSpan: Self.realtimeVisualRefreshInterval,
                    count: Self.realtimeVisualRefreshMaxBatchSize,
                    scheduler: MainScheduler.instance
                )
                .compactMap(MarketIndexRealtimeReducer.latestPrices)
                .observe(on: MainScheduler.instance)
                .subscribe(
                    onNext: { updates in
                        Task { @MainActor in
                            apply(updates)
                        }
                    },
                    onError: { _ in }
                )
                .disposed(by: disposeBag)
            realtimeDisposeBag = disposeBag
        } catch {
            stopRealtime()
        }
    }

    private func stopRealtime() {
        realtimeDisposeBag = DisposeBag()
    }

    private func runSnapshotFallback() async {
        guard snapshotFallbackID != "none" else {
            return
        }

        do {
            try await Task.sleep(nanoseconds: Self.snapshotFallbackInitialDelay)
        } catch {
            return
        }

        while !Task.isCancelled {
            if shouldFetchSnapshotFallback {
                await fetchSnapshotFallback()
            }

            do {
                try await Task.sleep(nanoseconds: Self.snapshotFallbackInterval)
            } catch {
                return
            }
        }
    }

    private var shouldFetchSnapshotFallback: Bool {
        guard let lastRealtimeUpdateAt else {
            return true
        }

        return Date().timeIntervalSince(lastRealtimeUpdateAt) >= Self.streamQuietThreshold
    }

    private func fetchSnapshotFallback() async {
        do {
            let quotes = try await app.fetchMarketIndexQuotes(feed: realtimeFeed)
            apply(quotes)
        } catch where error.isRequestCancellation {
            return
        } catch {
            return
        }
    }

    private func apply(_ updates: [MarketIndexRealtimePrice]) {
        var nextQuotes = displayedQuotes
        var didChange = false

        for update in updates {
            guard let index = nextQuotes.firstIndex(where: { $0.symbol == update.symbol }) else {
                continue
            }

            let updatedQuote = nextQuotes[index].updating(price: update.price)
            guard updatedQuote != nextQuotes[index] else {
                continue
            }

            nextQuotes[index] = updatedQuote
            didChange = true
        }

        if didChange {
            liveQuotes = nextQuotes
            lastRealtimeUpdateAt = Date()
        }
    }

    private func apply(_ quotes: [MarketIndexQuote]) {
        var nextQuotes = displayedQuotes
        var didChange = false

        for quote in quotes {
            guard let index = nextQuotes.firstIndex(where: { $0.symbol == quote.symbol }) else {
                continue
            }

            let currentQuote = nextQuotes[index]
            let nextQuote = quote.price == nil && currentQuote.price != nil ? currentQuote : quote
            guard nextQuote != currentQuote else {
                continue
            }

            nextQuotes[index] = nextQuote
            didChange = true
        }

        if didChange {
            liveQuotes = nextQuotes
        }
    }
}

private struct IndexProxyList: View {
    let quotes: [MarketIndexQuote]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(quotes.enumerated()), id: \.element.id) { index, quote in
                IndexProxyRow(quote: quote)
                    .equatable()

                if index < quotes.count - 1 {
                    Divider()
                        .overlay(Color(.separator).opacity(0.5))
                }
            }
        }
    }
}

private struct IndexProxyRow: Equatable, View {
    let quote: MarketIndexQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(quote.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(verbatim: quote.symbol)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                AppPriceText(
                    quote.price,
                    font: .system(size: 22, weight: .semibold, design: .rounded),
                    minimumScaleFactor: 0.78,
                    isAnimated: true
                )

                Text(AppFormatter.signedPercent(quote.percentChange))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(percentTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
    }

    private var percentTint: Color {
        guard quote.percentChange != nil else {
            return .secondary
        }

        return quote.isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
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
                if app.isLoadingFavoriteMarketSymbols && app.favoriteMarketSymbols.isEmpty {
                    MarketSymbolRowsSkeleton(rowCount: 3)
                } else if items.isEmpty {
                    EmptyFavoriteView()
                } else {
                    ForEach(items) { item in
                        MarketSymbolRow(item: item)
                    }
                }
            case .popular:
                if items.isEmpty {
                    EmptyMarketRow(text: L10n.Markets.noActivityData)
                } else {
                    ForEach(items) { item in
                        MarketSymbolRow(item: item)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var displayedItems: [MarketSymbolItem] {
        switch mode {
        case .favorites:
            favoriteItems
        case .popular:
            overview.mostActive.map(MarketSymbolItem.init(activeSymbol:))
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
            let asset = app.favoriteMarketAssetBySymbol[normalizedSymbol]

            if let favoriteQuote = app.favoriteMarketQuotesBySymbol[normalizedSymbol] {
                return MarketSymbolItem(activeSymbol: favoriteQuote, companyName: asset?.name)
            }

            if let activeSymbol = activeBySymbol[normalizedSymbol] {
                return MarketSymbolItem(activeSymbol: activeSymbol, companyName: asset?.name)
            }

            if let indexQuote = indexBySymbol[normalizedSymbol] {
                return MarketSymbolItem(indexQuote: indexQuote, companyName: asset?.name)
            }

            return MarketSymbolItem(symbol: normalizedSymbol, companyName: asset?.name, price: nil, percentChange: nil, isPositive: true)
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
                SymbolLogoView(symbol: item.symbol, size: 38)

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

private struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.ColorToken.warning)

            Text(message)
                .font(AppTypography.detail)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: retry) {
                Text(L10n.Markets.retry)
            }
            .font(AppTypography.control)
        }
        .padding(14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    }
}
