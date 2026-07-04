import Foundation
import Observation
import RxSwift
import SwiftUI

@MainActor
@Observable
final class MarketIndexProxyStore {
    static let realtimeVisualRefreshInterval = RxTimeInterval.milliseconds(1_000)
    static let realtimeVisualRefreshMaxBatchSize = 512
    static let snapshotFallbackInitialDelay: UInt64 = 5_000_000_000
    static let snapshotFallbackInterval: UInt64 = 15_000_000_000
    static let streamQuietThreshold: TimeInterval = 10

    private(set) var liveQuotes: [MarketIndexQuote] = []
    private(set) var lastRealtimeUpdateAt: Date?

    let overview: MarketOverview
    private weak var app: AppModel?
    private var realtimeDisposeBag = DisposeBag()

    init(overview: MarketOverview, app: AppModel) {
        self.overview = overview
        self.app = app
    }

    var displayedQuotes: [MarketIndexQuote] {
        liveQuotes.isEmpty ? overview.indexQuotes : liveQuotes
    }

    var realtimeFeed: AlpacaMarketDataFeed {
        MarketSessionSnapshot.current(for: overview).session == .overnight ? .overnight : .iex
    }

    var shouldFetchSnapshotFallback: Bool {
        guard let lastRealtimeUpdateAt else {
            return true
        }
        return Date().timeIntervalSince(lastRealtimeUpdateAt) >= Self.streamQuietThreshold
    }

    func seedInitialQuotes() {
        liveQuotes = overview.indexQuotes
    }

    func bindRealtime() {
        guard let app, app.hasCredentials, !overview.indexQuotes.isEmpty else {
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
                    onNext: { [weak self] updates in
                        Task { @MainActor [weak self] in
                            self?.apply(updates)
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

    func stopRealtime() {
        realtimeDisposeBag = DisposeBag()
    }

    func fetchSnapshotFallback() async {
        guard let app else { return }
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

struct MarketIndexProxyPanel: View {
    @Environment(AppModel.self) private var app
    @State private var store: MarketIndexProxyStore?

    let overview: MarketOverview

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

            IndexProxyList(quotes: store?.displayedQuotes ?? overview.indexQuotes)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: baselineID) {
            if store == nil {
                store = MarketIndexProxyStore(overview: overview, app: app)
            }
            store?.seedInitialQuotes()
        }
        .task(id: realtimeStreamID) {
            store?.bindRealtime()
        }
        .task(id: snapshotFallbackID) {
            await runSnapshotFallback()
        }
        .onDisappear {
            store?.stopRealtime()
        }
    }

    private var displayedQuotes: [MarketIndexQuote] {
        store?.displayedQuotes ?? overview.indexQuotes
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

    private func runSnapshotFallback() async {
        guard store != nil else {
            return
        }
        do {
            try await Task.sleep(nanoseconds: MarketIndexProxyStore.snapshotFallbackInitialDelay)
        } catch {
            return
        }

        while !Task.isCancelled {
            if store?.shouldFetchSnapshotFallback == true {
                await store?.fetchSnapshotFallback()
            }

            do {
                try await Task.sleep(nanoseconds: MarketIndexProxyStore.snapshotFallbackInterval)
            } catch {
                return
            }
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
        NavigationLink {
            AssetDetailView(symbol: quote.symbol)
        } label: {
            HStack(spacing: 10) {
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

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 7)
    }

    private var percentTint: Color {
        guard quote.percentChange != nil else {
            return .secondary
        }

        return quote.isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
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
