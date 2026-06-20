import SwiftUI

struct WatchlistsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var store = WatchlistsStore()
    @State private var presentedSheet: WatchlistsSheet?
    @State private var pendingDelete: AlpacaWatchlist?
    @State private var editMode: EditMode = .inactive

    private var selectedWatchlist: AlpacaWatchlist? {
        store.selectedWatchlist
    }

    private var selectedWatchlistIDBinding: Binding<String> {
        Binding(
            get: { store.selectedWatchlistID ?? store.watchlists.first?.id ?? "" },
            set: { watchlistID in
                store.select(watchlistID)
                editMode = .inactive
            }
        )
    }

    private var canReorderSelectedAssets: Bool {
        guard let selectedWatchlist else {
            return false
        }

        return (selectedWatchlist.assets ?? []).count > 1 && !store.isMutating(selectedWatchlist)
    }

    var body: some View {
        VStack(spacing: 0) {
            WatchlistsHeader(
                title: L10n.Watchlists.title,
                selectedWatchlist: selectedWatchlist,
                isEditingAssets: editMode.isEditing,
                canReorderAssets: canReorderSelectedAssets,
                back: { dismiss() },
                add: presentPrimaryAdd,
                toggleReorder: toggleAssetEditing,
                create: { presentedSheet = .create },
                edit: presentSelectedWatchlistEditor,
                delete: presentSelectedWatchlistDelete,
                refresh: { Task { await store.load(app: app, forceReload: true) } }
            )

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.editMode, $editMode)
        .task {
            await store.load(app: app)
        }
        .onChange(of: store.loadError) { _, message in
            guard let message else {
                return
            }

            toastCenter.showErrorMessage(message)
        }
        .onChange(of: store.selectedWatchlistID) { _, _ in
            editMode = .inactive
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .create:
                WatchlistEditorSheet(store: store, mode: .create)
            case .edit(let watchlist):
                WatchlistEditorSheet(store: store, mode: .edit(watchlist))
            case .addSymbol(let watchlist):
                WatchlistSymbolSheet(store: store, watchlist: watchlist)
            }
        }
        .confirmationDialog(
            L10n.Watchlists.deleteConfirmTitle,
            isPresented: isDeleteConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { watchlist in
            Button(role: .destructive) {
                pendingDelete = nil
                Task { await delete(watchlist) }
            } label: {
                Text(L10n.Watchlists.deleteAction)
            }
        } message: { watchlist in
            Text(L10n.Watchlists.deleteConfirmMessage(name: watchlist.name, locale: locale))
        }
    }

    @ViewBuilder
    private var content: some View {
        if !app.hasCredentials {
            paddedEmptyState {
                AppEmptyStateView(
                    title: L10n.Markets.apiNotConnected,
                    message: L10n.Markets.apiNotConnectedDescription,
                    systemImage: AppIcon.More.alpaca
                )
            }
        } else if store.isLoading && store.watchlists.isEmpty {
            WatchlistsLoadingView()
                .refreshable {
                    await store.load(app: app, forceReload: true)
                }
        } else if let loadError = store.loadError, store.watchlists.isEmpty {
            paddedEmptyState {
                AppEmptyStateView(
                    title: L10n.Markets.dataUnavailable,
                    message: LocalizedStringKey(loadError),
                    systemImage: AppIcon.Market.watchlists
                ) {
                    Button {
                        Task { await store.load(app: app, forceReload: true) }
                    } label: {
                        AppEmptyStateActionButton(L10n.Common.retry, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if store.watchlists.isEmpty {
            paddedEmptyState {
                AppEmptyStateView(
                    title: L10n.Watchlists.emptyTitle,
                    message: L10n.Watchlists.emptyDescription,
                    systemImage: AppIcon.Market.watchlists
                ) {
                    Button {
                        presentedSheet = .create
                    } label: {
                        AppEmptyStateActionButton(L10n.Watchlists.createAction, systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            watchlistPages
        }
    }

    private var watchlistPages: some View {
        VStack(spacing: 0) {
            WatchlistTabBar(
                watchlists: store.watchlists,
                selectedWatchlistID: store.selectedWatchlistID,
                select: { watchlistID in
                    store.select(watchlistID)
                    editMode = .inactive
                }
            )

            TabView(selection: selectedWatchlistIDBinding) {
                ForEach(store.watchlists) { watchlist in
                    WatchlistAssetsPage(
                        store: store,
                        watchlist: watchlist,
                        editMode: editMode,
                        refresh: { await store.load(app: app, forceReload: true) },
                        addAsset: { presentedSheet = .addSymbol(watchlist) },
                        removeAsset: { asset in remove(asset, from: watchlist) },
                        moveAssets: { source, destination in moveAssets(source, destination, in: watchlist) }
                    )
                    .tag(watchlist.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paddedEmptyState<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, AppTheme.Spacing.pageTop)
                .padding(.bottom, AppTheme.Spacing.pageBottom)
        }
        .refreshable {
            await store.load(app: app, forceReload: true)
        }
    }

    private var isDeleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDelete = nil
                }
            }
        )
    }

    private func presentPrimaryAdd() {
        if let selectedWatchlist {
            presentedSheet = .addSymbol(selectedWatchlist)
        } else {
            presentedSheet = .create
        }
    }

    private func presentSelectedWatchlistEditor() {
        guard let selectedWatchlist else {
            return
        }

        presentedSheet = .edit(selectedWatchlist)
    }

    private func presentSelectedWatchlistDelete() {
        guard let selectedWatchlist else {
            return
        }

        pendingDelete = selectedWatchlist
    }

    private func toggleAssetEditing() {
        guard canReorderSelectedAssets || editMode.isEditing else {
            return
        }

        withAnimation(.snappy(duration: 0.18)) {
            editMode = editMode.isEditing ? .inactive : .active
        }
    }

    private func delete(_ watchlist: AlpacaWatchlist) async {
        do {
            try await store.delete(watchlist, app: app)
            editMode = .inactive
            toastCenter.show(
                L10n.Watchlists.deletedToast(name: watchlist.name, locale: locale),
                systemImage: "trash"
            )
        } catch {
            toastCenter.showError(error, locale: locale)
        }
    }

    private func remove(_ asset: AlpacaAsset, from watchlist: AlpacaWatchlist) {
        Task { @MainActor in
            do {
                _ = try await store.removeSymbol(asset.symbol, from: watchlist, app: app)
                toastCenter.show(
                    L10n.Watchlists.symbolRemovedToast(symbol: asset.symbol, locale: locale),
                    systemImage: "minus.circle.fill"
                )
            } catch {
                toastCenter.showError(error, locale: locale)
            }
        }
    }

    private func moveAssets(_ source: IndexSet, _ destination: Int, in watchlist: AlpacaWatchlist) {
        guard let reorder = store.reorderAssetsLocally(in: watchlist, from: source, to: destination) else {
            return
        }

        Task { @MainActor in
            do {
                _ = try await store.persistReorderedAssets(reorder, app: app)
            } catch {
                toastCenter.showError(error, locale: locale)
            }
        }
    }
}

private struct WatchlistsHeader: View {
    let title: LocalizedStringKey
    let selectedWatchlist: AlpacaWatchlist?
    let isEditingAssets: Bool
    let canReorderAssets: Bool
    let back: () -> Void
    let add: () -> Void
    let toggleReorder: () -> Void
    let create: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let refresh: () -> Void

    var body: some View {
        AppScreenHeader(background: AppTheme.ColorToken.pageBackground) {
            AppGlassIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: L10n.Common.back,
                action: back
            )
        } center: {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        } trailing: {
            WatchlistsMenuButton(
                selectedWatchlist: selectedWatchlist,
                isEditingAssets: isEditingAssets,
                canReorderAssets: canReorderAssets,
                add: add,
                toggleReorder: toggleReorder,
                create: create,
                edit: edit,
                delete: delete,
                refresh: refresh
            )
        }
    }
}

private struct WatchlistsMenuButton: View {
    let selectedWatchlist: AlpacaWatchlist?
    let isEditingAssets: Bool
    let canReorderAssets: Bool
    let add: () -> Void
    let toggleReorder: () -> Void
    let create: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let refresh: () -> Void

    var body: some View {
        Menu {
            if selectedWatchlist != nil {
                Button(action: add) {
                    Label(L10n.Watchlists.addSymbolTitle, systemImage: "plus")
                }

                Button(action: toggleReorder) {
                    Label(
                        isEditingAssets ? L10n.Watchlists.reorderDoneAction : L10n.Watchlists.reorderAction,
                        systemImage: isEditingAssets ? "checkmark" : "arrow.up.arrow.down"
                    )
                }
                .disabled(!canReorderAssets && !isEditingAssets)

                Divider()

                Button(action: create) {
                    Label(L10n.Watchlists.createTitle, systemImage: "plus.rectangle.on.rectangle")
                }

                Button(action: edit) {
                    Label(L10n.Watchlists.editTitle, systemImage: "pencil")
                }

                Button(role: .destructive, action: delete) {
                    Label(L10n.Watchlists.deleteAction, systemImage: "trash")
                }
            } else {
                Button(action: create) {
                    Label(L10n.Watchlists.createTitle, systemImage: "plus")
                }
            }

            Divider()

            Button(action: refresh) {
                Label(L10n.Common.refresh, systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: AppIcon.Market.more)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isEditingAssets ? AppTheme.ColorToken.brand : .primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Watchlists.actionsTitle)
        .modifier(AppGlassCircleModifier())
    }
}

private struct WatchlistTabBar: View {
    let watchlists: [AlpacaWatchlist]
    let selectedWatchlistID: String?
    let select: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(watchlists) { watchlist in
                        WatchlistTabButton(
                            watchlist: watchlist,
                            isSelected: watchlist.id == selectedWatchlistID,
                            select: { select(watchlist.id) }
                        )
                        .id(watchlist.id)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .scrollClipDisabled()
            .onChange(of: selectedWatchlistID) { _, watchlistID in
                guard let watchlistID else {
                    return
                }

                withAnimation(.snappy(duration: 0.2)) {
                    proxy.scrollTo(watchlistID, anchor: .center)
                }
            }
        }
    }
}

private struct WatchlistTabButton: View {
    let watchlist: AlpacaWatchlist
    let isSelected: Bool
    let select: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let button = Button(action: select) {
            HStack(spacing: isFavoritesTab ? 8 : 0) {
                if isFavoritesTab {
                    Image(systemName: "heart.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: watchlist.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Text(L10n.Watchlists.assetCount(watchlist.symbols.count, locale: locale))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)

        if #available(iOS 26.0, *) {
            button
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(isSelected ? 0.18 : 0.08))
                }
        } else {
            button
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(isSelected ? 0.20 : 0.10))
                }
                .shadow(color: .black.opacity(isSelected ? 0.10 : 0.05), radius: 8, y: 3)
        }
    }

    private var isFavoritesTab: Bool {
        watchlist.name.caseInsensitiveCompare(AppModel.favoritesWatchlistName) == .orderedSame
    }
}

private struct WatchlistAssetsPage: View {
    let store: WatchlistsStore
    let watchlist: AlpacaWatchlist
    let editMode: EditMode
    let refresh: () async -> Void
    let addAsset: () -> Void
    let removeAsset: (AlpacaAsset) -> Void
    let moveAssets: (IndexSet, Int) -> Void

    private var currentWatchlist: AlpacaWatchlist {
        store.watchlist(id: watchlist.id) ?? watchlist
    }

    private var assets: [AlpacaAsset] {
        currentWatchlist.assets ?? []
    }

    var body: some View {
        if assets.isEmpty {
            ScrollView {
                AppEmptyStateView(
                    title: L10n.Watchlists.noAssetsTitle,
                    message: L10n.Watchlists.noAssetsDescription,
                    systemImage: AppIcon.Market.watchlists
                ) {
                    Button(action: addAsset) {
                        AppEmptyStateActionButton(L10n.Watchlists.addSymbolTitle, systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, AppTheme.Spacing.pageTop)
                .padding(.bottom, AppTheme.Spacing.pageBottom)
            }
            .refreshable {
                await refresh()
            }
        } else {
            List {
                Section {
                    ForEach(assets) { asset in
                        NavigationLink {
                            AssetDetailView(symbol: asset.symbol)
                        } label: {
                            WatchlistAssetRow(
                                asset: asset,
                                isMutating: store.isMutatingSymbol(asset.symbol, in: currentWatchlist)
                            )
                        }
                        .moveDisabled(store.isMutating(currentWatchlist))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                removeAsset(asset)
                            } label: {
                                Label(L10n.Watchlists.removeSymbolAction, systemImage: "minus.circle")
                            }
                            .tint(AppTheme.ColorToken.negative)
                        }
                        .disabled(store.isMutatingSymbol(asset.symbol, in: currentWatchlist))
                    }
                    .onMove(perform: moveAssets)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 12, for: .scrollContent)
            .refreshable {
                await refresh()
            }
            .animation(.snappy(duration: 0.18), value: editMode)
        }
    }
}

private struct WatchlistEditorSheet: View {
    let store: WatchlistsStore
    let mode: WatchlistEditorMode
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var name: String
    @State private var selectedAssets: [WatchlistEditorAsset]
    @State private var assetSearchText = ""
    @State private var assetSearchResults: [AlpacaAsset] = []
    @State private var assetSearchError: String?
    @State private var isSearchingAssets = false
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private var normalizedAssetSearchQuery: String {
        assetSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedSymbols: [String] {
        selectedAssets.map(\.symbol)
    }

    private var selectedSymbolSet: Set<String> {
        Set(selectedSymbols)
    }

    private var visibleAssetSearchResults: [AlpacaAsset] {
        assetSearchResults.filter { asset in
            !selectedSymbolSet.contains(WatchlistSymbolParser.symbol(from: asset.symbol))
        }
    }

    private var visibleSelectedAssets: [WatchlistEditorAsset] {
        guard !normalizedAssetSearchQuery.isEmpty else {
            return selectedAssets
        }

        return selectedAssets.filter { asset in
            asset.matches(normalizedAssetSearchQuery)
        }
    }

    init(store: WatchlistsStore, mode: WatchlistEditorMode) {
        self.store = store
        self.mode = mode

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _selectedAssets = State(initialValue: [])
        case .edit(let watchlist):
            _name = State(initialValue: watchlist.name)
            _selectedAssets = State(initialValue: WatchlistEditorAsset.assets(from: watchlist))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.Watchlists.namePlaceholder, text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                } header: {
                    Text(L10n.Watchlists.nameTitle)
                }

                Section {
                    if selectedAssets.isEmpty {
                        Text(L10n.Watchlists.noAssetsTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if visibleSelectedAssets.isEmpty {
                        Text(L10n.Common.noData)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleSelectedAssets) { asset in
                            WatchlistEditorAssetRow(asset: asset)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        removeSelectedAsset(asset)
                                    } label: {
                                        Label(L10n.Watchlists.removeSymbolAction, systemImage: "trash")
                                    }
                                    .tint(AppTheme.ColorToken.negative)
                                }
                                .disabled(isSaving)
                        }
                    }
                } header: {
                    Text(L10n.Watchlists.currentAssetsTitle)
                }

                if !normalizedAssetSearchQuery.isEmpty {
                    WatchlistAssetSearchResultsSection(
                        isSearching: isSearchingAssets,
                        errorMessage: assetSearchError,
                        results: visibleAssetSearchResults,
                        isSaving: isSaving,
                        select: addAsset
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $assetSearchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.Watchlists.assetSearchPrompt
            )
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(mode.actionTitle) {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .tint(AppTheme.ColorToken.brand)
            .onAppear {
                if case .create = mode {
                    isNameFocused = true
                }
            }
            .task(id: normalizedAssetSearchQuery) {
                await searchAssets()
            }
        }
    }

    private func save() async {
        guard canSave else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            switch mode {
            case .create:
                let watchlist = try await store.create(name: name, symbols: selectedSymbols, app: app)
                toastCenter.show(L10n.Watchlists.createdToast(name: watchlist.name, locale: locale))
            case .edit(let watchlist):
                let updatedWatchlist = try await store.update(
                    id: watchlist.id,
                    name: name,
                    symbols: selectedSymbols,
                    app: app
                )
                toastCenter.show(L10n.Watchlists.updatedToast(name: updatedWatchlist.name, locale: locale))
            }

            dismiss()
        } catch where error.isRequestCancellation {
            return
        } catch {
            toastCenter.showError(error, locale: locale)
        }
    }

    private func searchAssets() async {
        let query = normalizedAssetSearchQuery
        guard !query.isEmpty else {
            assetSearchResults = []
            assetSearchError = nil
            isSearchingAssets = false
            return
        }

        isSearchingAssets = true
        assetSearchError = nil

        do {
            try await Task.sleep(nanoseconds: 240_000_000)
            let results = try await app.searchWatchlistAssets(query: query)
            guard !Task.isCancelled else {
                return
            }

            assetSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            assetSearchResults = []
            assetSearchError = error.localizedDescription
        }

        isSearchingAssets = false
    }

    private func addAsset(_ asset: AlpacaAsset) {
        let editorAsset = WatchlistEditorAsset(asset: asset)
        guard !selectedSymbolSet.contains(editorAsset.symbol) else {
            toastCenter.show(
                L10n.Watchlists.duplicateSymbol(symbol: editorAsset.symbol, locale: locale),
                systemImage: "exclamationmark.triangle.fill"
            )
            return
        }

        selectedAssets.append(editorAsset)
        assetSearchError = nil
    }

    private func removeSelectedAsset(_ asset: WatchlistEditorAsset) {
        selectedAssets.removeAll { $0.id == asset.id }
    }
}

private struct WatchlistEditorAsset: Identifiable, Equatable {
    let id: String
    let symbol: String
    let name: String?
    let exchange: String?

    init(asset: AlpacaAsset) {
        symbol = WatchlistSymbolParser.symbol(from: asset.symbol)
        id = symbol
        name = asset.name
        exchange = asset.exchange
    }

    init(symbol: String, name: String? = nil, exchange: String? = nil) {
        self.symbol = WatchlistSymbolParser.symbol(from: symbol)
        id = self.symbol
        self.name = name
        self.exchange = exchange
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return true
        }

        let foldedQuery = normalizedQuery.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let foldedName = (name ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return symbol.localizedCaseInsensitiveContains(normalizedQuery)
            || foldedName.localizedCaseInsensitiveContains(foldedQuery)
            || (exchange ?? "").localizedCaseInsensitiveContains(normalizedQuery)
    }

    static func assets(from watchlist: AlpacaWatchlist) -> [WatchlistEditorAsset] {
        let assetsBySymbol = (watchlist.assets ?? []).reduce(into: [String: AlpacaAsset]()) { result, asset in
            let symbol = WatchlistSymbolParser.symbol(from: asset.symbol)
            guard !symbol.isEmpty else {
                return
            }

            result[symbol] = asset
        }

        return watchlist.symbols.compactMap { symbol in
            let normalizedSymbol = WatchlistSymbolParser.symbol(from: symbol)
            guard !normalizedSymbol.isEmpty else {
                return nil
            }

            if let asset = assetsBySymbol[normalizedSymbol] {
                return WatchlistEditorAsset(asset: asset)
            }

            return WatchlistEditorAsset(symbol: normalizedSymbol)
        }
    }
}

private struct WatchlistEditorAssetRow: View {
    let asset: WatchlistEditorAsset

    var body: some View {
        HStack(spacing: 14) {
            SymbolLogoView(symbol: asset.symbol, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: asset.symbol)
                    .font(AppTypography.rowTitle.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(AppFormatter.displayText(asset.name))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let exchange = asset.exchange, !exchange.isEmpty {
                Text(verbatim: exchange)
                    .font(AppTypography.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 56)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct WatchlistEditorAssetSearchRow: View {
    let asset: AlpacaAsset

    var body: some View {
        HStack(spacing: 14) {
            SymbolLogoView(symbol: asset.symbol, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: asset.symbol)
                    .font(AppTypography.rowTitle.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(AppFormatter.displayText(asset.name))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "plus.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.brand)
        }
        .frame(minHeight: 56)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct WatchlistSymbolSheet: View {
    let store: WatchlistsStore
    let watchlist: AlpacaWatchlist
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var assetSearchText = ""
    @State private var assetSearchResults: [AlpacaAsset] = []
    @State private var assetSearchError: String?
    @State private var isSearchingAssets = false
    @State private var isSaving = false

    private var currentWatchlist: AlpacaWatchlist {
        store.watchlist(id: watchlist.id) ?? watchlist
    }

    private var normalizedAssetSearchQuery: String {
        assetSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentSymbolSet: Set<String> {
        Set(currentWatchlist.symbols.map(WatchlistSymbolParser.symbol(from:)))
    }

    private var visibleAssetSearchResults: [AlpacaAsset] {
        assetSearchResults.filter { asset in
            !currentSymbolSet.contains(WatchlistSymbolParser.symbol(from: asset.symbol))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if normalizedAssetSearchQuery.isEmpty {
                    Section {
                        Text(L10n.Watchlists.noAssetsDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    WatchlistAssetSearchResultsSection(
                        isSearching: isSearchingAssets,
                        errorMessage: assetSearchError,
                        results: visibleAssetSearchResults,
                        isSaving: isSaving,
                        select: addAsset
                    )
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
            .navigationTitle(L10n.Watchlists.addSymbolTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $assetSearchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.Watchlists.assetSearchPrompt
            )
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .tint(AppTheme.ColorToken.brand)
            .task(id: normalizedAssetSearchQuery) {
                await searchAssets()
            }
        }
    }

    private func searchAssets() async {
        let query = normalizedAssetSearchQuery
        guard !query.isEmpty else {
            assetSearchResults = []
            assetSearchError = nil
            isSearchingAssets = false
            return
        }

        isSearchingAssets = true
        assetSearchError = nil

        do {
            try await Task.sleep(nanoseconds: 240_000_000)
            let results = try await app.searchWatchlistAssets(query: query)
            guard !Task.isCancelled else {
                return
            }

            assetSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            assetSearchResults = []
            assetSearchError = error.localizedDescription
        }

        isSearchingAssets = false
    }

    private func addAsset(_ asset: AlpacaAsset) {
        let normalizedSymbol = WatchlistSymbolParser.symbol(from: asset.symbol)
        guard !currentSymbolSet.contains(normalizedSymbol) else {
            toastCenter.show(
                L10n.Watchlists.duplicateSymbol(symbol: normalizedSymbol, locale: locale),
                systemImage: "exclamationmark.triangle.fill"
            )
            return
        }

        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }

            do {
                _ = try await store.addSymbol(normalizedSymbol, to: currentWatchlist, app: app)
                toastCenter.show(
                    L10n.Watchlists.symbolAddedToast(symbol: normalizedSymbol, locale: locale),
                    systemImage: "plus.circle.fill"
                )
                dismiss()
            } catch where error.isRequestCancellation {
                return
            } catch {
                toastCenter.showError(error, locale: locale)
            }
        }
    }
}

private struct WatchlistAssetSearchResultsSection: View {
    let isSearching: Bool
    let errorMessage: String?
    let results: [AlpacaAsset]
    let isSaving: Bool
    let select: (AlpacaAsset) -> Void

    var body: some View {
        Section {
            if isSearching {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.Markets.searchTitle)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ColorToken.negative)
            } else if results.isEmpty {
                Text(L10n.Common.noData)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { asset in
                    Button {
                        select(asset)
                    } label: {
                        WatchlistEditorAssetSearchRow(asset: asset)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
        } header: {
            Text(L10n.Watchlists.availableAssetsTitle)
        }
    }
}

private enum WatchlistsSheet: Identifiable {
    case create
    case edit(AlpacaWatchlist)
    case addSymbol(AlpacaWatchlist)

    var id: String {
        switch self {
        case .create:
            "create"
        case .edit(let watchlist):
            "edit-\(watchlist.id)"
        case .addSymbol(let watchlist):
            "add-symbol-\(watchlist.id)"
        }
    }
}

private enum WatchlistEditorMode {
    case create
    case edit(AlpacaWatchlist)

    var title: LocalizedStringKey {
        switch self {
        case .create:
            L10n.Watchlists.createTitle
        case .edit:
            L10n.Watchlists.editTitle
        }
    }

    var actionTitle: LocalizedStringKey {
        switch self {
        case .create:
            L10n.Watchlists.createAction
        case .edit:
            L10n.Watchlists.saveAction
        }
    }
}

private struct WatchlistAssetRow: View {
    let asset: AlpacaAsset
    let isMutating: Bool

    var body: some View {
        HStack(spacing: 14) {
            SymbolLogoView(symbol: asset.symbol, size: 38)

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: asset.symbol)
                    .font(AppTypography.rowTitle.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(AppFormatter.displayText(asset.name))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isMutating {
                ProgressView()
            } else if let exchange = asset.exchange, !exchange.isEmpty {
                Text(verbatim: exchange)
                    .font(AppTypography.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 62)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        WatchlistsView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
