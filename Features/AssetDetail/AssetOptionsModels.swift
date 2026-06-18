import Foundation
import SwiftUI

enum AssetOptionTypeFilter: String, CaseIterable, Identifiable {
    case all
    case calls
    case puts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .calls:
            "Calls"
        case .puts:
            "Puts"
        }
    }

    var emptyStateName: String {
        switch self {
        case .all:
            "option"
        case .calls:
            "call"
        case .puts:
            "put"
        }
    }

    var contractType: AlpacaOptionContractType? {
        switch self {
        case .all:
            nil
        case .calls:
            .call
        case .puts:
            .put
        }
    }
}

enum AssetOptionExpirationFilter: Hashable, Identifiable {
    case all
    case exact(AssetOptionExpiration)

    var id: String {
        switch self {
        case .all:
            "all"
        case .exact(let expiration):
            expiration.id
        }
    }

    var title: String {
        switch self {
        case .all:
            "All"
        case .exact(let expiration):
            expiration.title
        }
    }

    var apiValue: String? {
        switch self {
        case .all:
            nil
        case .exact(let expiration):
            expiration.id
        }
    }

    func emptyStateSuffix(symbol: String) -> String {
        switch self {
        case .all:
            symbol
        case .exact(let expiration):
            "\(symbol) expiring \(expiration.menuTitle)"
        }
    }
}

struct AssetOptionExpiration: Hashable, Identifiable {
    let id: String
    let year: Int
    let title: String
    let menuTitle: String
    let sortKey: Int

    init?(apiDate: String) {
        let parts = apiDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }

        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    init(year: Int, month: Int, day: Int) {
        id = String(format: "%04d-%02d-%02d", year, month, day)
        self.year = year
        title = "\(month)/\(day)"
        menuTitle = OptionValueText.expiration(year: year, month: month, day: day)
        sortKey = year * 10_000 + month * 100 + day
    }
}

struct AssetOptionExpirationGroup: Identifiable {
    let year: Int
    let expirations: [AssetOptionExpiration]

    var id: Int { year }
    var title: String { String(year) }
}

struct AssetOptionsLoadMoreTrigger: Equatable {
    let filter: AssetOptionTypeFilter
    let expiration: AssetOptionExpirationFilter
    let pageToken: String?
    let count: Int
}

struct OptionContractDescriptor: Equatable, Hashable, Sendable {
    let symbol: String
    let underlyingSymbol: String
    let expiration: AssetOptionExpiration?
    let expirationText: String
    let expirationSortKey: Int
    let type: AlpacaOptionContractType?
    let typeText: String
    let strike: Double?
    let strikeText: String

    init(symbol: String) {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.symbol = normalized

        guard normalized.count >= 15 else {
            underlyingSymbol = normalized
            expiration = nil
            expirationText = AppFormatter.placeholder
            expirationSortKey = Int.max
            type = nil
            typeText = "Option"
            strike = nil
            strikeText = AppFormatter.placeholder
            return
        }

        let suffix = normalized.suffix(15)
        let root = normalized.dropLast(15)
        let dateText = suffix.prefix(6)
        let typeText = suffix.dropFirst(6).prefix(1)
        let strikeText = suffix.suffix(8)
        let yearText = dateText.prefix(2)
        let monthText = dateText.dropFirst(2).prefix(2)
        let dayText = dateText.suffix(2)
        let year = Int(String(yearText)).map { 2000 + $0 }
        let month = Int(String(monthText))
        let day = Int(String(dayText))

        underlyingSymbol = root.isEmpty ? normalized : String(root)

        if let year, let month, let day {
            let expiration = AssetOptionExpiration(year: year, month: month, day: day)
            self.expiration = expiration
            expirationSortKey = expiration.sortKey
            expirationText = expiration.menuTitle
        } else {
            expiration = nil
            expirationSortKey = Int.max
            expirationText = AppFormatter.placeholder
        }

        switch typeText {
        case "C":
            type = .call
            self.typeText = "Call"
        case "P":
            type = .put
            self.typeText = "Put"
        default:
            type = nil
            self.typeText = "Option"
        }

        if let rawStrike = Double(String(strikeText)) {
            strike = rawStrike / 1000
            self.strikeText = OptionValueText.strike(rawStrike / 1000)
        } else {
            strike = nil
            self.strikeText = AppFormatter.placeholder
        }
    }

    var isPut: Bool {
        type == .put
    }

    var expirationDate: Date? {
        guard let expiration else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let year = expiration.sortKey / 10_000
        let month = (expiration.sortKey % 10_000) / 100
        let day = expiration.sortKey % 100
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    var dteText: String {
        guard let expirationDate else {
            return AppFormatter.placeholder
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let todayStart = calendar.startOfDay(for: Date())
        let expirationStart = calendar.startOfDay(for: expirationDate)
        guard let days = calendar.dateComponents([.day], from: todayStart, to: expirationStart).day else {
            return AppFormatter.placeholder
        }

        return days <= 0 ? "0D" : "\(days)D"
    }
}

struct AssetOptionRowModel: Equatable, Identifiable {
    let id: String
    let snapshot: AlpacaOptionSnapshot
    let contractSymbol: String
    let expiration: AssetOptionExpiration?
    let summaryText: String
    let typeText: String
    let typeTint: Color
    let bidText: String
    let askText: String
    let midText: String
    let lastText: String
    let ivText: String
    let deltaText: String
    let thetaText: String
    let volumeText: String
    let timeText: String
    let expirationSortKey: Int
    let strikeSortKey: Double
    let typeSortKey: Int

    init(snapshot: AlpacaOptionSnapshot) {
        let contract = OptionContractDescriptor(symbol: snapshot.contractSymbol)
        let quote = snapshot.latestQuote
        let trade = snapshot.latestTrade
        let greeks = snapshot.greeks

        id = snapshot.contractSymbol
        self.snapshot = snapshot
        contractSymbol = snapshot.contractSymbol
        expiration = contract.expiration
        let summaryParts = [
            contract.expirationText,
            contract.strikeText
        ]
        .filter { !$0.isEmpty && $0 != AppFormatter.placeholder }
        summaryText = summaryParts.isEmpty ? AppFormatter.placeholder : summaryParts.joined(separator: "  ")
        typeText = contract.typeText
        typeTint = contract.type == .put ? AppTheme.ColorToken.negative : AppTheme.ColorToken.positive
        bidText = OptionValueText.money(quote?.bidPrice)
        askText = OptionValueText.money(quote?.askPrice)
        midText = OptionValueText.money(quote?.midpoint)
        lastText = OptionValueText.money(trade?.price)
        ivText = OptionValueText.percent(snapshot.impliedVolatility)
        deltaText = OptionValueText.decimal(greeks?.delta)
        thetaText = OptionValueText.decimal(greeks?.theta)
        volumeText = OptionValueText.size(trade?.size)
        timeText = OptionValueText.time(
            AlpacaDateParser.date(quote?.timestamp) ?? AlpacaDateParser.date(trade?.timestamp)
        )
        expirationSortKey = contract.expirationSortKey
        strikeSortKey = contract.strike ?? .greatestFiniteMagnitude
        typeSortKey = contract.type == .put ? 1 : 0
    }

    static func == (lhs: AssetOptionRowModel, rhs: AssetOptionRowModel) -> Bool {
        lhs.id == rhs.id
            && lhs.contractSymbol == rhs.contractSymbol
            && lhs.expiration == rhs.expiration
            && lhs.summaryText == rhs.summaryText
            && lhs.typeText == rhs.typeText
            && lhs.bidText == rhs.bidText
            && lhs.askText == rhs.askText
            && lhs.midText == rhs.midText
            && lhs.lastText == rhs.lastText
            && lhs.ivText == rhs.ivText
            && lhs.deltaText == rhs.deltaText
            && lhs.thetaText == rhs.thetaText
            && lhs.volumeText == rhs.volumeText
            && lhs.timeText == rhs.timeText
            && lhs.expirationSortKey == rhs.expirationSortKey
            && lhs.strikeSortKey == rhs.strikeSortKey
            && lhs.typeSortKey == rhs.typeSortKey
    }
}

enum OptionValueText {
    static func moneyFractionLength(for value: Double?) -> Int {
        guard let value, value.isFinite else {
            return 2
        }

        return value >= 10 ? 2 : 3
    }

    static func money(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else {
            return AppFormatter.placeholder
        }

        return AppFormatter.money(value, fractionLength: moneyFractionLength(for: value))
    }

    static func strike(_ value: Double?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return AppFormatter.money(value, fractionLength: value.rounded() == value ? 0 : 2)
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return AppFormatter.placeholder
        }

        return AppFormatter.percent(value, fractionLength: 2)
    }

    static func decimal(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return AppFormatter.placeholder
        }

        return value.formatted(.number.precision(.fractionLength(0...4)))
    }

    static func size(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else {
            return AppFormatter.placeholder
        }

        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func time(_ date: Date?) -> String {
        guard let date else {
            return AppFormatter.placeholder
        }

        if abs(date.timeIntervalSinceNow) < 24 * 60 * 60 {
            return date.formatted(date: .omitted, time: .shortened)
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func expiration(year: Int, month: Int, day: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return AppFormatter.placeholder
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
