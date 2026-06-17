import SafariServices
import SwiftUI

struct AssetNewsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    let symbol: String
    let displayName: String

    private let lookbackStart: Date

    @State private var rows: [AssetNewsRowModel] = []
    @State private var nextPageToken: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasLoadMoreError = false
    @State private var selectedWebPage: AssetNewsWebPage?

    init(symbol: String, displayName: String) {
        self.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.displayName = displayName
        self.lookbackStart = Self.defaultLookbackStart()
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemBackground))
                .navigationTitle("\(symbol) News")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.Common.close)
                    }
                }
        }
        .background {
            AssetNewsSafariPresenter(
                page: $selectedWebPage,
                detentFraction: Self.webSheetCompactFraction
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .task {
            await loadNews(reset: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !app.hasCredentials {
            ContentUnavailableView(
                L10n.Common.noData,
                systemImage: AppIcon.More.alpaca
            )
        } else if isLoading && rows.isEmpty {
            AssetNewsLoadingView()
        } else {
            newsList
        }
    }

    private var newsList: some View {
        AppInfiniteScrollView(
            alignment: .leading,
            spacing: 0,
            contentMargins: EdgeInsets(
                top: 10,
                leading: AppTheme.Spacing.pageHorizontal,
                bottom: AppTheme.Spacing.pageBottom,
                trailing: AppTheme.Spacing.pageHorizontal
            ),
            canLoadMore: nextPageToken != nil && !hasLoadMoreError,
            isLoadingMore: isLoadingMore,
            loadMoreTrigger: AssetNewsLoadMoreTrigger(pageToken: nextPageToken, count: rows.count),
            loadMore: {
                await loadMoreIfNeeded()
            }
        ) {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No news",
                    systemImage: "newspaper",
                    description: Text("No recent \(symbol) headlines.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                AssetNewsSymbolHeader(symbol: symbol, displayName: displayName, count: rows.count)

                ForEach(rows) { row in
                    AssetNewsRow(row: row) { url in
                        selectedWebPage = AssetNewsWebPage(url: url)
                    }

                    if row.id != rows.last?.id {
                        Divider()
                    }
                }

            }
        }
        .refreshable {
            await loadNews(reset: true, forceReload: true)
        }
    }

    @MainActor
    private func loadNews(reset: Bool, forceReload: Bool = false) async {
        guard app.hasCredentials else {
            rows = []
            nextPageToken = nil
            hasLoadMoreError = false
            isLoading = false
            isLoadingMore = false
            return
        }

        if reset {
            guard !isLoading else {
                return
            }

            isLoading = true
            hasLoadMoreError = false
            nextPageToken = nil
        } else {
            guard !isLoading, !isLoadingMore, nextPageToken != nil else {
                return
            }

            isLoadingMore = true
            hasLoadMoreError = false
        }

        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let page = try await app.fetchAssetNews(
                symbol: symbol,
                start: lookbackStart,
                limit: Self.pageSize,
                pageToken: reset ? nil : nextPageToken,
                forceReload: forceReload
            )

            guard !Task.isCancelled else {
                return
            }

            let pageRows = page.articles.map(AssetNewsRowModel.init(article:))
            nextPageToken = page.nextPageToken

            if reset {
                rows = pageRows
            } else {
                appendUnique(pageRows)
            }
        } catch where error.isRequestCancellation {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            if reset {
                rows = []
                nextPageToken = nil
            } else {
                hasLoadMoreError = true
            }
            toastCenter.showError(error, locale: app.appLanguage.locale)
        }
    }

    @MainActor
    private func loadMoreIfNeeded(force: Bool = false) async {
        guard nextPageToken != nil else {
            return
        }

        if hasLoadMoreError, !force {
            return
        }

        await loadNews(reset: false, forceReload: force)
    }

    private func appendUnique(_ newRows: [AssetNewsRowModel]) {
        var seen = Set(rows.map(\.id))
        rows.append(contentsOf: newRows.filter { seen.insert($0.id).inserted })
    }

    private static let pageSize = 50
    private static let webSheetCompactFraction = 0.67

    private static func defaultLookbackStart() -> Date {
        Date().addingTimeInterval(-30 * 24 * 60 * 60)
    }
}

private struct AssetNewsWebPage: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

private struct AssetNewsLoadMoreTrigger: Equatable {
    let pageToken: String?
    let count: Int
}

private struct AssetNewsRowModel: Identifiable, Equatable {
    let id: String
    let headline: String
    let summary: String?
    let sourceText: String
    let timeText: String
    let symbolsText: String?
    let destinationURL: URL?

    init(article: AlpacaNewsArticle) {
        let date = AlpacaDateParser.date(article.updatedAt ?? article.createdAt)
        let summary = Self.clean(article.summary)
        let headline = Self.clean(article.headline) ?? "Untitled news"
        let symbols = article.symbols
            .prefix(4)
            .map { $0.uppercased() }
            .joined(separator: "  ")

        self.id = article.id
        self.headline = headline
        self.summary = summary == headline ? nil : summary
        self.sourceText = Self.sourceText(article.source)
        self.timeText = Self.timeText(date)
        self.symbolsText = symbols.isEmpty ? nil : symbols
        self.destinationURL = Self.destinationURL(article.url)
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : htmlDecoded(normalized)
    }

    private static func htmlDecoded(_ value: String) -> String {
        guard value.contains("&"),
              let data = value.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return value
        }

        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sourceText(_ value: String?) -> String {
        guard let value = clean(value) else {
            return "News"
        }

        return value.localizedCapitalized
    }

    private static func timeText(_ date: Date?) -> String {
        guard let date else {
            return AppFormatter.placeholder
        }

        let age = abs(date.timeIntervalSinceNow)
        if age < 7 * 24 * 60 * 60 {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .short
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func destinationURL(_ value: String?) -> URL? {
        guard let value = clean(value) else {
            return nil
        }

        return URL(string: value)
    }
}

private struct AssetNewsLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text("Loading news")
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AssetNewsSymbolHeader: View {
    let symbol: String
    let displayName: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(symbol)
                    .font(.title3.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.primary)

                if !displayName.isEmpty, displayName != AppFormatter.placeholder {
                    Text(displayName)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
        .padding(.bottom, 6)
    }
}

private struct AssetNewsRow: View {
    let row: AssetNewsRowModel
    let openURL: (URL) -> Void

    var body: some View {
        Group {
            if let destinationURL = row.destinationURL {
                Button {
                    openURL(destinationURL)
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(row.sourceText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Circle()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 3, height: 3)
                    .accessibilityHidden(true)

                Text(row.timeText)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if row.destinationURL != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .accessibilityHidden(true)
                }
            }

            Text(row.headline)
                .font(AppTypography.rowTitle.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = row.summary {
                Text(summary)
                    .font(AppTypography.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let symbolsText = row.symbolsText {
                Text(symbolsText)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.brand)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

@MainActor
private struct AssetNewsSafariPresenter: UIViewControllerRepresentable {
    @Binding var page: AssetNewsWebPage?
    let detentFraction: CGFloat

    func makeUIViewController(context: Context) -> AssetNewsSafariHostViewController {
        AssetNewsSafariHostViewController()
    }

    func updateUIViewController(_ host: AssetNewsSafariHostViewController, context: Context) {
        context.coordinator.page = $page
        context.coordinator.detentFraction = detentFraction

        guard let page else {
            context.coordinator.dismissIfNeeded(from: host)
            return
        }

        context.coordinator.present(page, from: host)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(page: $page, detentFraction: detentFraction)
    }

    @MainActor
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var page: Binding<AssetNewsWebPage?>
        var detentFraction: CGFloat
        private var presentedPageID: String?
        private static let compactDetentIdentifier = UISheetPresentationController.Detent.Identifier("assetNewsWebCompact")

        init(page: Binding<AssetNewsWebPage?>, detentFraction: CGFloat) {
            self.page = page
            self.detentFraction = detentFraction
        }

        func present(_ page: AssetNewsWebPage, from host: UIViewController) {
            guard host.view.window != nil, presentedPageID != page.id else {
                return
            }

            let presentAction = { [weak self, weak host] in
                guard let self, let host, host.view.window != nil else {
                    return
                }

                let safari = SFSafariViewController(url: page.url)
                safari.dismissButtonStyle = .close
                safari.modalPresentationStyle = .pageSheet
                safari.presentationController?.delegate = self

                if let sheet = safari.sheetPresentationController {
                    let compactIdentifier = Self.compactDetentIdentifier
                    sheet.detents = [
                        .custom(identifier: compactIdentifier) { context in
                            context.maximumDetentValue * self.detentFraction
                        },
                        .large()
                    ]
                    sheet.selectedDetentIdentifier = compactIdentifier
                    sheet.prefersGrabberVisible = true
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                }

                host.present(safari, animated: true)
                self.presentedPageID = page.id
            }

            if host.presentedViewController != nil {
                host.dismiss(animated: false, completion: presentAction)
            } else {
                presentAction()
            }
        }

        func dismissIfNeeded(from host: UIViewController) {
            guard presentedPageID != nil else {
                return
            }

            presentedPageID = nil
            host.dismiss(animated: true)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            presentedPageID = nil
            page.wrappedValue = nil
        }
    }
}

@MainActor
private final class AssetNewsSafariHostViewController: UIViewController {
    override func loadView() {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        self.view = view
    }
}
