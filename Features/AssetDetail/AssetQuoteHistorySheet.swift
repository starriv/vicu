import Charts
import SwiftUI

struct AssetQuoteHistorySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    let symbol: String
    let feed: AlpacaMarketDataFeed
    let latestQuote: AlpacaRealtimeQuote?

    @State private var selectedRange: QuoteHistoryRange = .fiveMinutes
    @State private var rows: [QuoteHistoryRowModel] = []
    @State private var spreadPoints: [QuoteHistorySpreadPoint] = []
    @State private var nextPageToken: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasLoadError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    QuoteHistoryRangePicker(selection: $selectedRange)

                    if let latestRow {
                        QuoteHistoryCurrentCard(row: latestRow)
                    }

                    QuoteHistorySpreadCard(points: spreadPoints, quoteCount: rows.count)

                    QuoteHistoryRowsCard(
                        rows: rows,
                        isLoading: isLoading,
                        isLoadingMore: isLoadingMore,
                        hasLoadError: hasLoadError,
                        canLoadMore: nextPageToken != nil,
                        loadMore: {
                            Task { await loadMoreIfNeeded() }
                        }
                    )
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Quote history")
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
        .task(id: selectedRange) {
            await loadQuotes(reset: true)
        }
    }

    private var latestRow: QuoteHistoryRowModel? {
        guard let latestQuote else {
            return nil
        }

        return QuoteHistoryRowModel(symbol: symbol, quote: latestQuote)
    }

    @MainActor
    private func loadQuotes(reset: Bool) async {
        if reset {
            isLoading = true
            hasLoadError = false
            nextPageToken = nil
        } else {
            isLoadingMore = true
        }

        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let end = Date()
            let start = selectedRange.startDate(endingAt: end)
            let page = try await app.fetchHistoricalStockQuotes(
                symbol: symbol,
                feed: feed,
                start: start,
                end: end,
                limit: selectedRange.requestLimit,
                pageToken: reset ? nil : nextPageToken,
                sort: .desc
            )

            guard !Task.isCancelled else {
                return
            }

            let pageRows = page.quotes.map { QuoteHistoryRowModel(symbol: symbol, quote: $0) }
            nextPageToken = page.nextPageToken

            if reset {
                rows = pageRows
            } else {
                appendUnique(pageRows)
            }

            spreadPoints = QuoteHistorySpreadPoint.makePoints(from: rows)
        } catch where error.isRequestCancellation {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            if reset {
                rows = []
                spreadPoints = []
            }
            hasLoadError = true
            toastCenter.showError(error, locale: app.appLanguage.locale)
        }
    }

    @MainActor
    private func loadMoreIfNeeded() async {
        guard !isLoading, !isLoadingMore, nextPageToken != nil else {
            return
        }

        await loadQuotes(reset: false)
    }

    private func appendUnique(_ newRows: [QuoteHistoryRowModel]) {
        var seen = Set(rows.map(\.id))
        rows.append(contentsOf: newRows.filter { seen.insert($0.id).inserted })
    }
}

private enum QuoteHistoryRange: String, CaseIterable, Identifiable {
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMinute:
            "1m"
        case .fiveMinutes:
            "5m"
        case .fifteenMinutes:
            "15m"
        case .oneHour:
            "1h"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute:
            60
        case .fiveMinutes:
            5 * 60
        case .fifteenMinutes:
            15 * 60
        case .oneHour:
            60 * 60
        }
    }

    var requestLimit: Int {
        switch self {
        case .oneMinute:
            120
        case .fiveMinutes:
            240
        case .fifteenMinutes:
            360
        case .oneHour:
            500
        }
    }

    func startDate(endingAt end: Date) -> Date {
        end.addingTimeInterval(-seconds)
    }
}

private struct QuoteHistoryRowModel: Identifiable, Equatable {
    let id: String
    let date: Date?
    let timeText: String
    let bidPrice: Double?
    let askPrice: Double?
    let bidSize: Double?
    let askSize: Double?
    let spreadText: String
    let spread: Double?

    init(symbol fallbackSymbol: String, quote: AlpacaStockQuote) {
        self.init(
            symbol: quote.symbol ?? fallbackSymbol,
            askExchange: quote.askExchange,
            askPrice: quote.askPrice,
            askSize: quote.askSize,
            bidExchange: quote.bidExchange,
            bidPrice: quote.bidPrice,
            bidSize: quote.bidSize,
            timestamp: quote.timestamp
        )
    }

    init(symbol fallbackSymbol: String, quote: AlpacaRealtimeQuote) {
        self.init(
            symbol: quote.symbol.isEmpty ? fallbackSymbol : quote.symbol,
            askExchange: quote.askExchange,
            askPrice: quote.askPrice,
            askSize: quote.askSize,
            bidExchange: quote.bidExchange,
            bidPrice: quote.bidPrice,
            bidSize: quote.bidSize,
            timestamp: quote.timestamp
        )
    }

    private init(
        symbol: String,
        askExchange: String?,
        askPrice: Double?,
        askSize: Double?,
        bidExchange: String?,
        bidPrice: Double?,
        bidSize: Double?,
        timestamp: String?
    ) {
        let date = AlpacaDateParser.date(timestamp)
        let spread = QuoteHistoryFormat.spread(bid: bidPrice, ask: askPrice)

        self.id = QuoteHistoryFormat.id(
            symbol: symbol,
            timestamp: timestamp,
            bidPrice: bidPrice,
            askPrice: askPrice,
            bidSize: bidSize,
            askSize: askSize,
            bidExchange: bidExchange,
            askExchange: askExchange
        )
        self.date = date
        self.timeText = QuoteHistoryFormat.time(date)
        self.bidPrice = bidPrice
        self.askPrice = askPrice
        self.bidSize = bidSize
        self.askSize = askSize
        self.spreadText = "Spread \(AppFormatter.money(spread))"
        self.spread = spread
    }
}

private struct QuoteHistoryRangePicker: View {
    @Binding var selection: QuoteHistoryRange

    var body: some View {
        Picker("Quote range", selection: $selection) {
            ForEach(QuoteHistoryRange.allCases) { range in
                Text(range.title)
                    .tag(range)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct QuoteHistoryCurrentCard: View {
    let row: QuoteHistoryRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Latest quote", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(row.timeText)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            AssetLevelOneQuoteContent(
                bidPrice: row.bidPrice,
                askPrice: row.askPrice,
                bidSize: row.bidSize,
                askSize: row.askSize,
                spread: row.spread
            )
        }
        .padding(14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct QuoteHistorySpreadCard: View {
    let points: [QuoteHistorySpreadPoint]
    let quoteCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spread flow")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(quoteCount) quotes")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Spread", point.spread)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(AppTheme.ColorToken.brand)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 84)
            } else {
                Text("No data")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 84)
            }
        }
        .padding(14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct QuoteHistoryRowsCard: View {
    let rows: [QuoteHistoryRowModel]
    let isLoading: Bool
    let isLoadingMore: Bool
    let hasLoadError: Bool
    let canLoadMore: Bool
    let loadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Quote stream")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if rows.isEmpty, !isLoading {
                Text(hasLoadError ? "No quote history" : "No data")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        QuoteHistoryRow(row: row)

                        if row.id != rows.last?.id {
                            Divider()
                                .padding(.leading, 14)
                        }
                    }

                    if canLoadMore {
                        QuoteHistoryLoadMoreRow(isLoading: isLoadingMore)
                            .onAppear(perform: loadMore)
                    }
                }
            }
        }
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct QuoteHistoryRow: View, Equatable {
    let row: QuoteHistoryRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(row.timeText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(row.spreadText)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            AssetLevelOneQuoteContent(
                bidPrice: row.bidPrice,
                askPrice: row.askPrice,
                bidSize: row.bidSize,
                askSize: row.askSize,
                spread: row.spread
            )
        }
        .padding(14)
    }
}

private struct QuoteHistoryLoadMoreRow: View {
    let isLoading: Bool

    var body: some View {
        HStack {
            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("More")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(height: 44)
    }
}

private struct QuoteHistorySpreadPoint: Identifiable, Equatable {
    let date: Date
    let spread: Double

    var id: TimeInterval { date.timeIntervalSince1970 }

    static func makePoints(from rows: [QuoteHistoryRowModel], maxCount: Int = 160) -> [QuoteHistorySpreadPoint] {
        let points = rows
            .compactMap { row -> QuoteHistorySpreadPoint? in
                guard let date = row.date, let spread = row.spread else {
                    return nil
                }

                return QuoteHistorySpreadPoint(date: date, spread: spread)
            }
            .sorted { $0.date < $1.date }

        guard points.count > maxCount, maxCount > 1 else {
            return points
        }

        let stride = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { index in
            let sourceIndex = min(points.count - 1, Int((Double(index) * stride).rounded()))
            return points[sourceIndex]
        }
    }
}

private enum QuoteHistoryFormat {
    static func time(_ date: Date?) -> String {
        guard let date else {
            return AppFormatter.placeholder
        }

        return timeFormatter.string(from: date)
    }

    static func spread(bid: Double?, ask: Double?) -> Double? {
        guard let bid, let ask else {
            return nil
        }

        return max(0, ask - bid)
    }

    static func id(
        symbol: String,
        timestamp: String?,
        bidPrice: Double?,
        askPrice: Double?,
        bidSize: Double?,
        askSize: Double?,
        bidExchange: String?,
        askExchange: String?
    ) -> String {
        [
            symbol,
            timestamp ?? "",
            numberKey(bidPrice),
            numberKey(askPrice),
            numberKey(bidSize),
            numberKey(askSize),
            bidExchange ?? "",
            askExchange ?? ""
        ]
        .joined(separator: "|")
    }

    private static func numberKey(_ value: Double?) -> String {
        guard let value else {
            return ""
        }

        return String(value)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}
