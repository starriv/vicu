import Foundation

enum PortfolioIntelligenceEngineMode: String, Sendable, Equatable {
    case localQuant
    case onDeviceFoundation
    case cloudLLM
}

enum PortfolioHealthGrade: String, Sendable, Equatable {
    case strong
    case balanced
    case caution
    case atRisk
    case empty
}

enum PortfolioActionSeverity: Int, Sendable, Equatable, Comparable {
    case critical = 3
    case attention = 2
    case opportunity = 1
    case insight = 0

    static func < (lhs: PortfolioActionSeverity, rhs: PortfolioActionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum PortfolioAIActionKind: String, Sendable, Equatable {
    case marginPressure
    case concentrationRisk
    case takeProfit
    case lossReview
    case openOrdersReview
    case cashDeployment
    case balancedCheckup
    case emptyPortfolio
}

enum PortfolioAIActionDestination: Hashable, Sendable {
    case position(symbol: String)
    case trade(symbol: String, side: OrderSide)
    case closeOption(symbol: String, intent: OrderPositionIntent)
    case asset(symbol: String)
    case account
    case orders
    case positions
    case copilot(prompt: String)
}

struct PortfolioHealthAssessment: Sendable, Equatable {
    let score: Int
    let grade: PortfolioHealthGrade
    let diversificationScore: Int
    let liquidityScore: Int
    let momentumScore: Int
    let concentrationRatio: Double
    let topHoldingSymbol: String?
    let cashRatio: Double
    let leverageRatio: Double
    let maxDrawdown: Double?
    let winRate: Double?
}

struct PortfolioBriefingTag: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let tone: PortfolioTagTone
}

enum PortfolioTagTone: Sendable, Equatable {
    case neutral
    case positive
    case negative
    case warning
    case brand
}

struct PortfolioAIBriefing: Sendable, Equatable {
    let headline: String
    let summary: String
    let tags: [PortfolioBriefingTag]
}

struct PortfolioAIActionCard: Identifiable, Sendable, Equatable {
    let id: String
    let kind: PortfolioAIActionKind
    let severity: PortfolioActionSeverity
    let badge: String
    let title: String
    let detail: String
    let metricLabel: String
    let ctaTitle: String
    let destination: PortfolioAIActionDestination
}

enum PortfolioAllocationCategory: String, CaseIterable, Identifiable, Sendable, Equatable {
    case stock
    case etf
    case option
    case crypto
    case cash

    var id: String { rawValue }

    init(positionCategory: PositionAssetCategory) {
        switch positionCategory {
        case .stock: self = .stock
        case .etf: self = .etf
        case .option: self = .option
        case .crypto: self = .crypto
        }
    }

    var positionCategory: PositionAssetCategory? {
        switch self {
        case .stock: .stock
        case .etf: .etf
        case .option: .option
        case .crypto: .crypto
        case .cash: nil
        }
    }
}

struct PortfolioAllocationSegment: Identifiable, Sendable, Equatable {
    let category: PortfolioAllocationCategory
    let value: Double
    let weight: Double
    let count: Int
    let unrealizedPL: Double

    var id: String { category.id }
}

struct PortfolioAllocationBreakdown: Sendable, Equatable {
    let segments: [PortfolioAllocationSegment]
    let totalGrossValue: Double
    let netEquity: Double
    let cashBalance: Double
    let buyingPower: Double
    let longMarketValue: Double
    let shortMarketValue: Double
    let leverageRatio: Double
    let currencyCode: String
}

struct PortfolioAttributionItem: Identifiable, Sendable, Equatable {
    let symbol: String
    let marketValue: Double
    let weight: Double
    let unrealizedPL: Double
    let unrealizedPLPercent: Double?

    var id: String { symbol }
}

struct PortfolioAttributionSummary: Sendable, Equatable {
    let topContributors: [PortfolioAttributionItem]
    let topDetractors: [PortfolioAttributionItem]
    let totalUnrealizedPL: Double
}

struct PortfolioCopilotPrompt: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let systemImage: String
}

struct PortfolioCopilotMetric: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let value: String
    let tone: PortfolioTagTone
}

enum PortfolioCopilotRole: String, Sendable, Equatable {
    case user
    case assistant
}

struct PortfolioCopilotMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    let role: PortfolioCopilotRole
    let text: String
    let highlights: [PortfolioCopilotMetric]
    let ctaTitle: String?
    let destination: PortfolioAIActionDestination?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: PortfolioCopilotRole,
        text: String,
        highlights: [PortfolioCopilotMetric] = [],
        ctaTitle: String? = nil,
        destination: PortfolioAIActionDestination? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.highlights = highlights
        self.ctaTitle = ctaTitle
        self.destination = destination
        self.createdAt = createdAt
    }
}

struct PortfolioIntelligenceSnapshot: Sendable, Equatable {
    let generatedAt: Date
    let engineMode: PortfolioIntelligenceEngineMode
    let health: PortfolioHealthAssessment
    let briefing: PortfolioAIBriefing
    let actions: [PortfolioAIActionCard]
    let allocation: PortfolioAllocationBreakdown
    let attribution: PortfolioAttributionSummary
    let suggestedPrompts: [PortfolioCopilotPrompt]
    let positionWeightsBySymbol: [String: Double]
    let openOrdersCount: Int
}
