import Foundation

struct SearchableAssetRecord: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let symbol: String
    let name: String?
    let exchange: String?
    let assetClass: String?
    let tradable: Bool
    let fractionable: Bool
    let shortable: Bool

    init(
        id: String,
        symbol: String,
        name: String? = nil,
        exchange: String? = nil,
        assetClass: String? = "us_equity",
        tradable: Bool = true,
        fractionable: Bool = false,
        shortable: Bool = false
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.assetClass = assetClass
        self.tradable = tradable
        self.fractionable = fractionable
        self.shortable = shortable
    }

    init(asset: AlpacaAsset) {
        self.id = asset.id
        self.symbol = asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let trimmedName = asset.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmedName?.isEmpty == false) ? trimmedName : nil
        let trimmedExchange = asset.exchange?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.exchange = (trimmedExchange?.isEmpty == false) ? trimmedExchange : nil
        self.assetClass = asset.assetClass
        self.tradable = asset.tradable ?? true
        self.fractionable = asset.fractionable ?? false
        self.shortable = asset.shortable ?? false
    }

    var alpacaAsset: AlpacaAsset {
        AlpacaAsset(
            id: id,
            assetClass: assetClass,
            exchange: exchange,
            symbol: symbol,
            name: name,
            status: "active",
            tradable: tradable,
            marginable: nil,
            maintenanceMarginRequirement: nil,
            marginRequirementLong: nil,
            marginRequirementShort: nil,
            shortable: shortable,
            easyToBorrow: nil,
            borrowStatus: nil,
            fractionable: fractionable,
            attributes: nil
        )
    }

    var displayName: String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isETF: Bool {
        Self.detectETF(nameLower: name?.lowercased() ?? "", exchangeUpper: exchange ?? "")
    }

    static func detectETF(nameLower: String, exchangeUpper: String) -> Bool {
        guard !nameLower.isEmpty else { return false }
        if nameLower.contains(" etf") || nameLower.hasSuffix("etf") || nameLower.contains("exchange-traded") || nameLower.contains("exchange traded") {
            return true
        }
        if exchangeUpper == "ARCA" && (
            nameLower.contains("trust") ||
            nameLower.contains("fund") ||
            nameLower.contains("shares") ||
            nameLower.contains("index") ||
            nameLower.contains("proshares") ||
            nameLower.contains("ishares") ||
            nameLower.contains("spdr") ||
            nameLower.contains("vanguard") ||
            nameLower.contains("invesco") ||
            nameLower.contains("direxion")
        ) {
            return true
        }
        return false
    }
}

enum MarketSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case saved
    case etf
    case fractional

    var id: String { rawValue }
}

/// Immutable, Sendable, pre-indexed in-memory catalog with contiguous UTF-8 byte matching
/// for sub-millisecond symbol & company search across 12,000+ equities.
struct MarketSearchIndex: Sendable {
    struct Entry: Sendable {
        let record: SearchableAssetRecord
        let symbolUpper: String
        let symbolUTF8: [UInt8]
        let nameUTF8: [UInt8]
        let isETF: Bool
        let rankPenalty: Int
    }

    let entries: [Entry]
    private let indexBySymbol: [String: Int]
    private let symbolBuckets: [UInt8: [Int]]

    static let empty = MarketSearchIndex(records: [])

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    init(assets: [AlpacaAsset]) {
        let records = assets.compactMap { asset -> SearchableAssetRecord? in
            let symbol = asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !symbol.isEmpty, asset.status?.lowercased() == "active" else {
                return nil
            }
            return SearchableAssetRecord(asset: asset)
        }
        self.init(records: records)
    }

    init(records: [SearchableAssetRecord]) {
        var builtEntries: [Entry] = []
        builtEntries.reserveCapacity(records.count)

        var bySymbol: [String: Int] = [:]
        bySymbol.reserveCapacity(records.count)

        var buckets: [UInt8: [Int]] = [:]

        for record in records {
            let symbolUpper = record.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !symbolUpper.isEmpty, bySymbol[symbolUpper] == nil else {
                continue
            }

            let nameLower = (record.name ?? "")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let exchangeUpper = record.exchange ?? ""
            let isETF = SearchableAssetRecord.detectETF(nameLower: nameLower, exchangeUpper: exchangeUpper)
            let penalty = Self.computeRankPenalty(
                symbolUpper: symbolUpper,
                exchangeUpper: exchangeUpper,
                tradable: record.tradable
            )
            let symbolUTF8 = Array(symbolUpper.utf8)
            let nameUTF8 = Array(nameLower.utf8)

            let entryIndex = builtEntries.count
            builtEntries.append(
                Entry(
                    record: record,
                    symbolUpper: symbolUpper,
                    symbolUTF8: symbolUTF8,
                    nameUTF8: nameUTF8,
                    isETF: isETF,
                    rankPenalty: penalty
                )
            )
            bySymbol[symbolUpper] = entryIndex

            if let firstByte = symbolUTF8.first {
                buckets[firstByte, default: []].append(entryIndex)
            }
        }

        self.entries = builtEntries
        self.indexBySymbol = bySymbol
        self.symbolBuckets = buckets
    }

    var records: [SearchableAssetRecord] {
        entries.map(\.record)
    }

    func record(forSymbol symbol: String) -> SearchableAssetRecord? {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let index = indexBySymbol[key] else {
            return nil
        }
        return entries[index].record
    }

    func companyName(forSymbol symbol: String) -> String? {
        record(forSymbol: symbol)?.displayName
    }

    func search(
        query: String,
        scope: MarketSearchScope = .all,
        ownedSymbols: Set<String> = [],
        favoriteSymbols: Set<String> = [],
        limit: Int = 16
    ) -> [SearchableAssetRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0, !entries.isEmpty else {
            return []
        }

        let queryUpper = trimmed.uppercased()
        let queryLower = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let queryUpperUTF8 = Array(queryUpper.utf8)
        let queryLowerUTF8 = Array(queryLower.utf8)
        let queryByteCount = queryUpperUTF8.count
        let hasContextSets = !ownedSymbols.isEmpty || !favoriteSymbols.isEmpty

        // Fast path for single-character queries: only inspect symbols starting with that byte.
        if queryUpper.count == 1, let firstByte = queryUpperUTF8.first {
            let bucketIndices = symbolBuckets[firstByte] ?? []
            var top: [(entryIndex: Int, score: Int, symbolLength: Int)] = []
            top.reserveCapacity(limit + 1)

            for idx in bucketIndices {
                let entry = entries[idx]
                guard matchesScope(entry, scope: scope, ownedSymbols: ownedSymbols, favoriteSymbols: favoriteSymbols) else {
                    continue
                }
                let isExact = entry.symbolUTF8.count == 1
                var score = isExact ? 0 : (100 + entry.rankPenalty + min(entry.symbolUTF8.count, 10))
                if !isExact && hasContextSets {
                    score += contextBoost(symbol: entry.symbolUpper, ownedSymbols: ownedSymbols, favoriteSymbols: favoriteSymbols)
                }
                insertBounded(
                    (idx, score, entry.symbolUTF8.count),
                    into: &top,
                    limit: limit
                )
            }

            return top.map { entries[$0.entryIndex].record }
        }

        var top: [(entryIndex: Int, score: Int, symbolLength: Int)] = []
        top.reserveCapacity(limit + 1)

        // When `.saved` scope is active, iterate ONLY over owned + favorited symbols in O(K) instead of scanning 12,000 entries.
        if scope == .saved {
            let candidateSymbols = ownedSymbols.union(favoriteSymbols)
            for symbol in candidateSymbols {
                guard let idx = indexBySymbol[symbol] else { continue }
                let entry = entries[idx]
                guard var score = matchScore(
                    entry: entry,
                    queryUpperUTF8: queryUpperUTF8,
                    queryLowerUTF8: queryLowerUTF8,
                    queryByteCount: queryByteCount
                ) else {
                    continue
                }
                if score > 0 {
                    score += contextBoost(symbol: entry.symbolUpper, ownedSymbols: ownedSymbols, favoriteSymbols: favoriteSymbols)
                }
                insertBounded((idx, score, entry.symbolUTF8.count), into: &top, limit: limit)
            }
            return top.map { entries[$0.entryIndex].record }
        }

        for idx in entries.indices {
            let entry = entries[idx]
            if scope == .etf && !entry.isETF { continue }
            if scope == .fractional && !entry.record.fractionable { continue }

            guard var score = matchScore(
                entry: entry,
                queryUpperUTF8: queryUpperUTF8,
                queryLowerUTF8: queryLowerUTF8,
                queryByteCount: queryByteCount
            ) else {
                continue
            }

            if score > 0 && hasContextSets {
                score += contextBoost(symbol: entry.symbolUpper, ownedSymbols: ownedSymbols, favoriteSymbols: favoriteSymbols)
            }
            insertBounded((idx, score, entry.symbolUTF8.count), into: &top, limit: limit)
        }

        return top.map { entries[$0.entryIndex].record }
    }

    @inline(__always)
    private func matchScore(
        entry: Entry,
        queryUpperUTF8: [UInt8],
        queryLowerUTF8: [UInt8],
        queryByteCount: Int
    ) -> Int? {
        let sym = entry.symbolUTF8
        if sym.count == queryByteCount && sym == queryUpperUTF8 {
            return 0
        }
        if Self.utf8HasPrefix(sym, prefix: queryUpperUTF8) {
            return 100 + entry.rankPenalty + min(sym.count - queryByteCount, 12)
        }

        let name = entry.nameUTF8
        if !name.isEmpty {
            if Self.utf8HasPrefix(name, prefix: queryLowerUTF8) {
                return 200 + entry.rankPenalty
            }
            if let matchPos = Self.utf8FirstIndex(of: queryLowerUTF8, in: name) {
                if matchPos == 0 || name[matchPos - 1] == 0x20 /* ASCII space */ {
                    return 260 + entry.rankPenalty
                }
                // Check if symbol contains query (higher priority than mid-word name match)
                if Self.utf8FirstIndex(of: queryUpperUTF8, in: sym) != nil {
                    return 340 + entry.rankPenalty
                }
                return 420 + entry.rankPenalty
            }
        }

        if Self.utf8FirstIndex(of: queryUpperUTF8, in: sym) != nil {
            return 340 + entry.rankPenalty
        }
        return nil
    }

    @inline(__always)
    private func insertBounded(
        _ candidate: (entryIndex: Int, score: Int, symbolLength: Int),
        into top: inout [(entryIndex: Int, score: Int, symbolLength: Int)],
        limit: Int
    ) {
        if top.count == limit, let worst = top.last, !isBetter(candidate, than: worst) {
            return
        }

        var insertAt = top.count
        while insertAt > 0 && isBetter(candidate, than: top[insertAt - 1]) {
            insertAt -= 1
        }
        top.insert(candidate, at: insertAt)
        if top.count > limit {
            top.removeLast()
        }
    }

    @inline(__always)
    private func isBetter(
        _ lhs: (entryIndex: Int, score: Int, symbolLength: Int),
        than rhs: (entryIndex: Int, score: Int, symbolLength: Int)
    ) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        if lhs.symbolLength != rhs.symbolLength {
            return lhs.symbolLength < rhs.symbolLength
        }
        return entries[lhs.entryIndex].symbolUpper < entries[rhs.entryIndex].symbolUpper
    }

    @inline(__always)
    private static func utf8HasPrefix(_ haystack: [UInt8], prefix: [UInt8]) -> Bool {
        let needleCount = prefix.count
        guard haystack.count >= needleCount else { return false }
        for i in 0..<needleCount {
            if haystack[i] != prefix[i] {
                return false
            }
        }
        return true
    }

    @inline(__always)
    private static func utf8FirstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        let needleCount = needle.count
        let hayCount = haystack.count
        guard needleCount > 0, hayCount >= needleCount else { return nil }

        let firstByte = needle[0]
        let lastStart = hayCount - needleCount
        var i = 0
        while i <= lastStart {
            if haystack[i] == firstByte {
                var j = 1
                while j < needleCount && haystack[i + j] == needle[j] {
                    j += 1
                }
                if j == needleCount {
                    return i
                }
            }
            i += 1
        }
        return nil
    }

    private func matchesScope(
        _ entry: Entry,
        scope: MarketSearchScope,
        ownedSymbols: Set<String>,
        favoriteSymbols: Set<String>
    ) -> Bool {
        switch scope {
        case .all:
            true
        case .saved:
            ownedSymbols.contains(entry.symbolUpper) || favoriteSymbols.contains(entry.symbolUpper)
        case .etf:
            entry.isETF
        case .fractional:
            entry.record.fractionable
        }
    }

    private func contextBoost(
        symbol: String,
        ownedSymbols: Set<String>,
        favoriteSymbols: Set<String>
    ) -> Int {
        if ownedSymbols.contains(symbol) {
            return -40
        }
        if favoriteSymbols.contains(symbol) {
            return -22
        }
        return 0
    }

    private static func computeRankPenalty(
        symbolUpper: String,
        exchangeUpper: String,
        tradable: Bool
    ) -> Int {
        var penalty = 0
        if !tradable {
            penalty += 25
        }
        switch exchangeUpper {
        case "NASDAQ", "NYSE", "ARCA", "AMEX", "BATS":
            break
        case "":
            penalty += 6
        default:
            penalty += 14
        }
        if symbolUpper.contains(".") || symbolUpper.contains("-") || symbolUpper.contains("/") {
            penalty += 6
        }
        if symbolUpper.count > 5 {
            penalty += 5
        }
        return penalty
    }

    static func looksLikeTicker(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (1...8).contains(trimmed.count) else {
            return false
        }
        return trimmed.allSatisfy { char in
            char.isASCII && (char.isLetter || char.isNumber || char == "." || char == "-")
        }
    }
}
