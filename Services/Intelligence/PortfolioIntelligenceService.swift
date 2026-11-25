import Foundation

protocol PortfolioIntelligenceServicing: Sendable {
    func analyze(
        portfolio: PortfolioState,
        environment: TradeEnvironment,
        locale: Locale
    ) async -> PortfolioIntelligenceSnapshot

    func respond(
        to query: String,
        portfolio: PortfolioState,
        snapshot: PortfolioIntelligenceSnapshot,
        environment: TradeEnvironment,
        locale: Locale
    ) async -> PortfolioCopilotMessage
}

/// Deterministic local quantitative portfolio intelligence engine.
/// Computes health scores, concentration, leverage, attribution, actionable recommendations,
/// and contextual copilot answers directly from live Alpaca portfolio state.
/// Conforms to `PortfolioIntelligenceServicing` so an on-device or cloud LLM provider can
/// replace or augment this engine without changing any Home UI code.
struct LocalPortfolioIntelligenceService: PortfolioIntelligenceServicing {
    private static let openOrderStatuses: Set<String> = [
        "new",
        "accepted",
        "pending_new",
        "accepted_for_bidding",
        "partially_filled",
        "pending_replace",
        "pending_cancel",
        "held",
        "calculated"
    ]

    func analyze(
        portfolio: PortfolioState,
        environment: TradeEnvironment,
        locale: Locale
    ) async -> PortfolioIntelligenceSnapshot {
        analyzeSync(portfolio: portfolio, environment: environment, locale: locale)
    }

    func analyzeSync(
        portfolio: PortfolioState,
        environment: TradeEnvironment,
        locale: Locale
    ) -> PortfolioIntelligenceSnapshot {
        let account = portfolio.account
        let positions = portfolio.positions
        let orders = portfolio.orders
        let history = portfolio.displayedHistory(for: portfolio.historyRange)
        let currency = account?.currency ?? "USD"

        let longMV = NumberParser.double(from: account?.longMarketValue)
            ?? positions.reduce(0.0) { $0 + max(0, NumberParser.double(from: $1.marketValue) ?? 0) }
        let shortMV = abs(
            NumberParser.double(from: account?.shortMarketValue)
                ?? positions.reduce(0.0) { $0 + min(0, NumberParser.double(from: $1.marketValue) ?? 0) }
        )
        let cash = NumberParser.double(from: account?.cash) ?? 0
        let buyingPower = NumberParser.double(from: account?.buyingPower) ?? 0

        let parsedPositions: [ParsedPosition] = positions.map { position in
            let mv = NumberParser.double(from: position.marketValue) ?? 0
            let absMV = abs(mv)
            let pl = NumberParser.double(from: position.unrealizedPL) ?? 0
            let plpc = NumberParser.double(from: position.unrealizedPLPC)
            let qty = NumberParser.double(from: position.quantity) ?? 0
            let currentPrice = NumberParser.double(from: position.currentPrice)
            let avgEntry = NumberParser.double(from: position.averageEntryPrice)
            return ParsedPosition(
                position: position,
                symbol: position.symbol.uppercased(),
                category: position.assetCategory,
                marketValue: mv,
                absMarketValue: absMV,
                unrealizedPL: pl,
                unrealizedPLPercent: plpc,
                quantity: qty,
                currentPrice: currentPrice,
                averageEntryPrice: avgEntry
            )
        }

        let totalPositionsGross = parsedPositions.reduce(0.0) { $0 + $1.absMarketValue }
        let normalizedHistory = PortfolioEquitySeriesNormalizer.normalize(
            history: history,
            account: account,
            range: portfolio.historyRange,
            now: portfolio.historyUpdatedAtByRange[portfolio.historyRange] ?? Date()
        )
        let netEquity = PortfolioEquitySeriesNormalizer.liveAccountEquity(from: account)
            ?? normalizedHistory.last?.equity
            ?? (longMV - shortMV + cash)

        let weightDenominator = max(totalPositionsGross, 1e-9)
        let sortedByWeight = parsedPositions.sorted { $0.absMarketValue > $1.absMarketValue }
        var weightsBySymbol: [String: Double] = [:]
        for item in parsedPositions {
            let weight = totalPositionsGross > 0 ? item.absMarketValue / weightDenominator : 0
            weightsBySymbol[item.symbol] = weight
        }

        let topHolding = sortedByWeight.first
        let topConcentration = topHolding.map { totalPositionsGross > 0 ? $0.absMarketValue / weightDenominator : 0 } ?? 0
        let leverageRatio = netEquity > 0 ? totalPositionsGross / netEquity : (totalPositionsGross > 0 ? .infinity : 0)
        let cashRatio = netEquity > 0 ? cash / netEquity : 0

        let maxDrawdown = computeMaxDrawdown(history: normalizedHistory)
        let rangeReturn = normalizedHistory.last?.profitLossPercent

        let winnersCount = parsedPositions.filter { $0.unrealizedPL > 0 }.count
        let winRate: Double? = parsedPositions.isEmpty ? nil : Double(winnersCount) / Double(parsedPositions.count)

        let openOrders = orders.filter { order in
            guard let status = order.status?.lowercased() else { return false }
            return Self.openOrderStatuses.contains(status)
        }

        let hasAnyData = account != nil || !positions.isEmpty || !history.isEmpty

        let health = computeHealth(
            hasAnyData: hasAnyData,
            parsedPositions: parsedPositions,
            weightsBySymbol: weightsBySymbol,
            topHolding: topHolding,
            topConcentration: topConcentration,
            netEquity: netEquity,
            cash: cash,
            buyingPower: buyingPower,
            cashRatio: cashRatio,
            leverageRatio: leverageRatio,
            rangeReturn: rangeReturn,
            maxDrawdown: maxDrawdown,
            winRate: winRate
        )

        let allocation = computeAllocation(
            parsedPositions: parsedPositions,
            netEquity: netEquity,
            cash: cash,
            buyingPower: buyingPower,
            longMV: longMV,
            shortMV: shortMV,
            leverageRatio: leverageRatio,
            currencyCode: currency
        )

        let attribution = computeAttribution(
            parsedPositions: parsedPositions,
            weightsBySymbol: weightsBySymbol
        )

        let actions = buildActionCards(
            hasAnyData: hasAnyData,
            parsedPositions: parsedPositions,
            weightsBySymbol: weightsBySymbol,
            topHolding: topHolding,
            topConcentration: topConcentration,
            netEquity: netEquity,
            cash: cash,
            buyingPower: buyingPower,
            cashRatio: cashRatio,
            leverageRatio: leverageRatio,
            openOrders: openOrders,
            currencyCode: currency,
            locale: locale
        )

        let briefing = buildBriefing(
            hasAnyData: hasAnyData,
            health: health,
            attribution: attribution,
            openOrdersCount: openOrders.count,
            netEquity: netEquity,
            currencyCode: currency,
            locale: locale
        )

        let suggestedPrompts = buildSuggestedPrompts(
            health: health,
            topHolding: topHolding,
            topConcentration: topConcentration,
            leverageRatio: leverageRatio,
            cashRatio: cashRatio,
            openOrdersCount: openOrders.count,
            locale: locale
        )

        return PortfolioIntelligenceSnapshot(
            generatedAt: Date(),
            engineMode: .localQuant,
            health: health,
            briefing: briefing,
            actions: actions,
            allocation: allocation,
            attribution: attribution,
            suggestedPrompts: suggestedPrompts,
            positionWeightsBySymbol: weightsBySymbol,
            openOrdersCount: openOrders.count
        )
    }

    func respond(
        to query: String,
        portfolio: PortfolioState,
        snapshot: PortfolioIntelligenceSnapshot,
        environment: TradeEnvironment,
        locale: Locale
    ) async -> PortfolioCopilotMessage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        let currency = snapshot.allocation.currencyCode

        let mentioned = findMentionedPosition(in: trimmed, positions: portfolio.positions)
        if containsAny(normalized, keywords: ["rebalance", "concentrat", "trim", "diversif", "weight", "权重", "集中", "再平衡", "调仓", "减仓", "分散"]),
           let position = mentioned ?? portfolio.positions.first(where: { $0.symbol.uppercased() == snapshot.health.topHoldingSymbol }) {
            return buildRebalanceResponse(position: position, snapshot: snapshot, currencyCode: currency, locale: locale)
        }

        if let mentioned {
            return buildPositionDiagnosisResponse(position: mentioned, snapshot: snapshot, currencyCode: currency, locale: locale)
        }

        // 3. Margin / liquidity / cash / risk / leverage intent
        if containsAny(normalized, keywords: ["margin", "cash", "buying power", "leverage", "liquid", "risk", "drawdown", "保证金", "现金", "购买力", "杠杆", "流动", "风险", "回撤"]) {
            return buildLiquidityRiskResponse(snapshot: snapshot, currencyCode: currency, locale: locale)
        }

        // 4. Performance / attribution / winners / losers / P&L intent
        if containsAny(normalized, keywords: ["winner", "loser", "profit", "loss", "pnl", "p/l", "mover", "contrib", "drag", "perform", "盈亏", "盈利", "亏损", "贡献", "拖累", "表现", "领涨"]) {
            return buildAttributionResponse(snapshot: snapshot, currencyCode: currency, locale: locale)
        }

        // 5. Orders / pending intent
        if containsAny(normalized, keywords: ["order", "pending", "open", "fill", "订单", "委托", "挂单"]) {
            return buildOrdersResponse(portfolio: portfolio, snapshot: snapshot, locale: locale)
        }

        // 6. Health score / diagnosis intent
        if containsAny(normalized, keywords: ["health", "score", "grade", "diagnos", "why", "健康", "评分", "分数", "诊断", "为什么"]) {
            return buildHealthResponse(snapshot: snapshot, locale: locale)
        }

        // 7. Default comprehensive portfolio overview
        return buildOverviewResponse(snapshot: snapshot, currencyCode: currency, locale: locale)
    }

    // MARK: - Quantitative Calculations

    private func computeMaxDrawdown(history: [NormalizedPortfolioHistoryPoint]) -> Double? {
        guard history.count >= 2 else { return nil }
        var peak = history[0].equity
        var maxDD: Double = 0

        for point in history where point.equity.isFinite {
            if point.equity > peak {
                peak = point.equity
            } else if peak > 0 {
                let dd = (peak - point.equity) / peak
                if dd > maxDD {
                    maxDD = dd
                }
            }
        }

        return maxDD > 0 ? maxDD : 0
    }

    private func computeHealth(
        hasAnyData: Bool,
        parsedPositions: [ParsedPosition],
        weightsBySymbol: [String: Double],
        topHolding: ParsedPosition?,
        topConcentration: Double,
        netEquity: Double,
        cash: Double,
        buyingPower: Double,
        cashRatio: Double,
        leverageRatio: Double,
        rangeReturn: Double?,
        maxDrawdown: Double?,
        winRate: Double?
    ) -> PortfolioHealthAssessment {
        guard hasAnyData else {
            return PortfolioHealthAssessment(
                score: 0,
                grade: .empty,
                diversificationScore: 0,
                liquidityScore: 0,
                momentumScore: 0,
                concentrationRatio: 0,
                topHoldingSymbol: nil,
                cashRatio: 0,
                leverageRatio: 0,
                maxDrawdown: nil,
                winRate: nil
            )
        }

        // 1. Diversification Score
        let diversificationScore: Int
        if parsedPositions.isEmpty {
            diversificationScore = cash > 0 ? 60 : 50
        } else {
            let hhi = weightsBySymbol.values.reduce(0.0) { $0 + ($1 * $1) }
            let uniqueCategories = Set(parsedPositions.map(\.category)).count
            var score: Double
            switch parsedPositions.count {
            case 1:
                score = 28
            case 2:
                score = min(58, (1.0 - hhi) * 95.0)
            default:
                score = (1.0 - hhi) * 105.0 + Double(uniqueCategories) * 4.5
            }

            if topConcentration > 0.45 {
                score -= 14
            } else if topConcentration > 0.30 {
                score -= 6
            }
            diversificationScore = clampScore(score)
        }

        // 2. Liquidity & Leverage Score
        var liquidity: Double = 86
        if leverageRatio > 1.80 {
            liquidity -= 36
        } else if leverageRatio > 1.35 {
            liquidity -= 22
        } else if leverageRatio > 1.05 {
            liquidity -= 10
        }

        if cash < 0 {
            liquidity -= 12
        }
        if buyingPower <= 0 && netEquity > 0 {
            liquidity -= 16
        }
        if cashRatio > 0.65 && !parsedPositions.isEmpty {
            liquidity -= 8
        } else if cashRatio >= 0.08 && cashRatio <= 0.35 && leverageRatio <= 1.05 {
            liquidity += 8
        }
        let liquidityScore = clampScore(liquidity)

        // 3. Momentum & Performance Score
        var momentum: Double = 68
        if let rangeReturn {
            if rangeReturn >= 0.05 {
                momentum += 18
            } else if rangeReturn >= 0.01 {
                momentum += 10
            } else if rangeReturn <= -0.05 {
                momentum -= 20
            } else if rangeReturn <= -0.01 {
                momentum -= 10
            }
        }
        if let maxDrawdown {
            if maxDrawdown >= 0.10 {
                momentum -= 14
            } else if maxDrawdown >= 0.05 {
                momentum -= 7
            }
        }
        if let winRate, parsedPositions.count >= 2 {
            if winRate >= 0.65 {
                momentum += 9
            } else if winRate <= 0.35 {
                momentum -= 9
            }
        }
        let momentumScore = clampScore(momentum)

        let weightedScore = Double(diversificationScore) * 0.35
            + Double(liquidityScore) * 0.35
            + Double(momentumScore) * 0.30
        let totalScore = clampScore(weightedScore)

        let grade: PortfolioHealthGrade
        switch totalScore {
        case 80...100:
            grade = .strong
        case 60..<80:
            grade = .balanced
        case 40..<60:
            grade = .caution
        default:
            grade = .atRisk
        }

        return PortfolioHealthAssessment(
            score: totalScore,
            grade: grade,
            diversificationScore: diversificationScore,
            liquidityScore: liquidityScore,
            momentumScore: momentumScore,
            concentrationRatio: topConcentration,
            topHoldingSymbol: topHolding?.symbol,
            cashRatio: cashRatio,
            leverageRatio: leverageRatio,
            maxDrawdown: maxDrawdown,
            winRate: winRate
        )
    }

    private func computeAllocation(
        parsedPositions: [ParsedPosition],
        netEquity: Double,
        cash: Double,
        buyingPower: Double,
        longMV: Double,
        shortMV: Double,
        leverageRatio: Double,
        currencyCode: String
    ) -> PortfolioAllocationBreakdown {
        var totalsByCategory: [PortfolioAllocationCategory: (value: Double, count: Int, pl: Double)] = [:]
        for item in parsedPositions {
            let category = PortfolioAllocationCategory(positionCategory: item.category)
            let current = totalsByCategory[category] ?? (0, 0, 0)
            totalsByCategory[category] = (
                current.value + item.absMarketValue,
                current.count + 1,
                current.pl + item.unrealizedPL
            )
        }

        if cash > 0 {
            totalsByCategory[.cash] = (cash, 0, 0)
        }

        let grossTotal = totalsByCategory.values.reduce(0.0) { $0 + $1.value }
        let segments: [PortfolioAllocationSegment] = PortfolioAllocationCategory.allCases.compactMap { category in
            guard let entry = totalsByCategory[category], entry.value > 0 else {
                return nil
            }
            let weight = grossTotal > 0 ? entry.value / grossTotal : 0
            return PortfolioAllocationSegment(
                category: category,
                value: entry.value,
                weight: weight,
                count: entry.count,
                unrealizedPL: entry.pl
            )
        }
        .sorted { $0.value > $1.value }

        return PortfolioAllocationBreakdown(
            segments: segments,
            totalGrossValue: grossTotal,
            netEquity: netEquity,
            cashBalance: cash,
            buyingPower: buyingPower,
            longMarketValue: longMV,
            shortMarketValue: shortMV,
            leverageRatio: leverageRatio,
            currencyCode: currencyCode
        )
    }

    private func computeAttribution(
        parsedPositions: [ParsedPosition],
        weightsBySymbol: [String: Double]
    ) -> PortfolioAttributionSummary {
        let items = parsedPositions.map { item in
            PortfolioAttributionItem(
                symbol: item.symbol,
                marketValue: item.marketValue,
                weight: weightsBySymbol[item.symbol] ?? 0,
                unrealizedPL: item.unrealizedPL,
                unrealizedPLPercent: item.unrealizedPLPercent
            )
        }

        let contributors = items
            .filter { $0.unrealizedPL > 0 }
            .sorted { $0.unrealizedPL > $1.unrealizedPL }
            .prefix(3)

        let detractors = items
            .filter { $0.unrealizedPL < 0 }
            .sorted { $0.unrealizedPL < $1.unrealizedPL }
            .prefix(3)

        let totalPL = parsedPositions.reduce(0.0) { $0 + $1.unrealizedPL }

        return PortfolioAttributionSummary(
            topContributors: Array(contributors),
            topDetractors: Array(detractors),
            totalUnrealizedPL: totalPL
        )
    }

    private func buildActionCards(
        hasAnyData: Bool,
        parsedPositions: [ParsedPosition],
        weightsBySymbol: [String: Double],
        topHolding: ParsedPosition?,
        topConcentration: Double,
        netEquity: Double,
        cash: Double,
        buyingPower: Double,
        cashRatio: Double,
        leverageRatio: Double,
        openOrders: [AlpacaOrder],
        currencyCode: String,
        locale: Locale
    ) -> [PortfolioAIActionCard] {
        guard hasAnyData else {
            return []
        }

        if parsedPositions.isEmpty {
            return [
                PortfolioAIActionCard(
                    id: "empty-portfolio",
                    kind: .emptyPortfolio,
                    severity: .opportunity,
                    badge: L10n.HomeAI.badgeOpportunity(locale: locale),
                    title: L10n.HomeAI.actionEmptyTitle(locale: locale),
                    detail: L10n.HomeAI.actionEmptyDetail(
                        cash: AppFormatter.compactMoney(cash, currencyCode: currencyCode),
                        locale: locale
                    ),
                    metricLabel: AppFormatter.compactMoney(buyingPower, currencyCode: currencyCode),
                    ctaTitle: L10n.HomeAI.ctaAskCopilot(locale: locale),
                    destination: .copilot(prompt: L10n.HomeAI.promptStarterAllocation(locale: locale))
                )
            ]
        }

        var cards: [PortfolioAIActionCard] = []

        // 1. Margin / Buying Power pressure
        if leverageRatio > 1.30 || (cash < 0 && buyingPower <= max(netEquity * 0.05, 100)) {
            let leverageText = Self.leverageText(leverageRatio)
            cards.append(
                PortfolioAIActionCard(
                    id: "margin-pressure",
                    kind: .marginPressure,
                    severity: leverageRatio > 1.75 || buyingPower <= 0 ? .critical : .attention,
                    badge: L10n.HomeAI.badgeRisk(locale: locale),
                    title: L10n.HomeAI.actionMarginTitle(locale: locale),
                    detail: L10n.HomeAI.actionMarginDetail(
                        leverage: leverageText,
                        buyingPower: AppFormatter.compactMoney(buyingPower, currencyCode: currencyCode),
                        locale: locale
                    ),
                    metricLabel: leverageText,
                    ctaTitle: L10n.HomeAI.ctaReviewMargin(locale: locale),
                    destination: .account
                )
            )
        }

        // 2. Single-holding concentration risk
        if let topHolding, (topConcentration >= 0.30 && parsedPositions.count >= 2) || parsedPositions.count == 1 {
            let pctText = AppFormatter.percent(topConcentration, fractionLength: 1)
            let detail = rebalanceDetail(position: topHolding.position, weight: topConcentration, currencyCode: currencyCode, locale: locale)
            let severity: PortfolioActionSeverity = topConcentration >= 0.45 ? .critical : .attention
            cards.append(
                PortfolioAIActionCard(
                    id: "concentration-\(topHolding.symbol)",
                    kind: .concentrationRisk,
                    severity: severity,
                    badge: L10n.HomeAI.badgeRebalance(locale: locale),
                    title: L10n.HomeAI.actionConcentrationTitle(symbol: topHolding.symbol, locale: locale),
                    detail: detail,
                    metricLabel: pctText,
                    ctaTitle: L10n.HomeAI.ctaInspectSymbol(symbol: topHolding.symbol, locale: locale),
                    destination: .position(symbol: topHolding.symbol)
                )
            )
        }

        // 3. Winner take-profit candidate (>= +15%)
        if let topWinner = parsedPositions
            .filter({ ($0.unrealizedPLPercent ?? 0) >= 0.15 && $0.unrealizedPL > 0 })
            .sorted(by: { ($0.unrealizedPLPercent ?? 0) > ($1.unrealizedPLPercent ?? 0) })
            .first {
            let gainPct = AppFormatter.signedPercent(topWinner.unrealizedPLPercent, fractionLength: 1)
            cards.append(
                PortfolioAIActionCard(
                    id: "take-profit-\(topWinner.symbol)",
                    kind: .takeProfit,
                    severity: .opportunity,
                    badge: L10n.HomeAI.badgeOpportunity(locale: locale),
                    title: L10n.HomeAI.actionTakeProfitTitle(symbol: topWinner.symbol, locale: locale),
                    detail: L10n.HomeAI.actionTakeProfitDetail(
                        symbol: topWinner.symbol,
                        gainPercent: gainPct,
                        gainAmount: AppFormatter.signedCompactMoney(topWinner.unrealizedPL, currencyCode: currencyCode),
                        locale: locale
                    ),
                    metricLabel: gainPct,
                    ctaTitle: L10n.HomeAI.ctaTrimPosition(symbol: topWinner.symbol, locale: locale),
                    destination: topWinner.position.trimDestination
                )
            )
        }

        // 4. Laggard / drawdown review (<= -8%)
        if let topLoser = parsedPositions
            .filter({ ($0.unrealizedPLPercent ?? 0) <= -0.08 && $0.unrealizedPL < 0 })
            .sorted(by: { ($0.unrealizedPLPercent ?? 0) < ($1.unrealizedPLPercent ?? 0) })
            .first {
            let lossPct = AppFormatter.signedPercent(topLoser.unrealizedPLPercent, fractionLength: 1)
            cards.append(
                PortfolioAIActionCard(
                    id: "loss-review-\(topLoser.symbol)",
                    kind: .lossReview,
                    severity: .attention,
                    badge: L10n.HomeAI.badgeRisk(locale: locale),
                    title: L10n.HomeAI.actionLossReviewTitle(symbol: topLoser.symbol, locale: locale),
                    detail: L10n.HomeAI.actionLossReviewDetail(
                        symbol: topLoser.symbol,
                        lossPercent: lossPct,
                        lossAmount: AppFormatter.signedCompactMoney(topLoser.unrealizedPL, currencyCode: currencyCode),
                        locale: locale
                    ),
                    metricLabel: lossPct,
                    ctaTitle: L10n.HomeAI.ctaInspectSymbol(symbol: topLoser.symbol, locale: locale),
                    destination: .position(symbol: topLoser.symbol)
                )
            )
        }

        // 5. Active open orders check
        if !openOrders.isEmpty {
            let count = openOrders.count
            cards.append(
                PortfolioAIActionCard(
                    id: "open-orders",
                    kind: .openOrdersReview,
                    severity: .insight,
                    badge: L10n.HomeAI.badgeExecution(locale: locale),
                    title: L10n.HomeAI.actionOpenOrdersTitle(count: count, locale: locale),
                    detail: L10n.HomeAI.actionOpenOrdersDetail(
                        count: count,
                        firstSymbol: openOrders.first?.symbol ?? "--",
                        locale: locale
                    ),
                    metricLabel: "\(count)",
                    ctaTitle: L10n.HomeAI.ctaReviewOrders(locale: locale),
                    destination: .orders
                )
            )
        }

        // 6. Idle cash deployment opportunity
        if cashRatio >= 0.35 && cash >= 500 {
            let cashPct = AppFormatter.percent(cashRatio, fractionLength: 0)
            cards.append(
                PortfolioAIActionCard(
                    id: "cash-deployment",
                    kind: .cashDeployment,
                    severity: .opportunity,
                    badge: L10n.HomeAI.badgeOpportunity(locale: locale),
                    title: L10n.HomeAI.actionCashTitle(locale: locale),
                    detail: L10n.HomeAI.actionCashDetail(
                        cashRatio: cashPct,
                        cashAmount: AppFormatter.compactMoney(cash, currencyCode: currencyCode),
                        locale: locale
                    ),
                    metricLabel: cashPct,
                    ctaTitle: L10n.HomeAI.ctaPlanDeployment(locale: locale),
                    destination: .copilot(prompt: L10n.HomeAI.promptCashPlan(locale: locale))
                )
            )
        }

        // Fallback steady-state checkup card if everything is balanced
        if cards.isEmpty {
            cards.append(
                PortfolioAIActionCard(
                    id: "balanced-checkup",
                    kind: .balancedCheckup,
                    severity: .insight,
                    badge: L10n.HomeAI.badgeInsight(locale: locale),
                    title: L10n.HomeAI.actionBalancedTitle(locale: locale),
                    detail: L10n.HomeAI.actionBalancedDetail(count: parsedPositions.count, locale: locale),
                    metricLabel: "\(parsedPositions.count)",
                    ctaTitle: L10n.HomeAI.ctaAskCopilot(locale: locale),
                    destination: .copilot(prompt: L10n.HomeAI.promptHealthDiagnosis(locale: locale))
                )
            )
        }

        return Array(cards.sorted { $0.severity > $1.severity }.prefix(4))
    }

    private func buildBriefing(
        hasAnyData: Bool,
        health: PortfolioHealthAssessment,
        attribution: PortfolioAttributionSummary,
        openOrdersCount: Int,
        netEquity: Double,
        currencyCode: String,
        locale: Locale
    ) -> PortfolioAIBriefing {
        guard hasAnyData else {
            return PortfolioAIBriefing(
                headline: L10n.HomeAI.briefingEmptyHeadline(locale: locale),
                summary: L10n.HomeAI.briefingEmptySummary(locale: locale),
                tags: []
            )
        }

        let headline: String
        switch health.grade {
        case .strong:
            headline = L10n.HomeAI.briefingStrongHeadline(locale: locale)
        case .balanced:
            headline = L10n.HomeAI.briefingBalancedHeadline(locale: locale)
        case .caution:
            headline = L10n.HomeAI.briefingCautionHeadline(locale: locale)
        case .atRisk:
            headline = L10n.HomeAI.briefingRiskHeadline(locale: locale)
        case .empty:
            headline = L10n.HomeAI.briefingEmptyHeadline(locale: locale)
        }

        var parts: [String] = []
        if let topSymbol = health.topHoldingSymbol, health.concentrationRatio > 0 {
            parts.append(
                L10n.HomeAI.briefingTopHoldingClause(
                    symbol: topSymbol,
                    weight: AppFormatter.percent(health.concentrationRatio, fractionLength: 0),
                    locale: locale
                )
            )
        }

        if health.leverageRatio > 1.25 {
            parts.append(
                L10n.HomeAI.briefingLeverageClause(
                    leverage: Self.leverageText(health.leverageRatio),
                    locale: locale
                )
            )
        } else if let leader = attribution.topContributors.first {
            parts.append(
                L10n.HomeAI.briefingLeaderClause(
                    symbol: leader.symbol,
                    amount: AppFormatter.signedCompactMoney(leader.unrealizedPL, currencyCode: currencyCode),
                    locale: locale
                )
            )
        } else if let laggard = attribution.topDetractors.first {
            parts.append(
                L10n.HomeAI.briefingLaggardClause(
                    symbol: laggard.symbol,
                    amount: AppFormatter.signedCompactMoney(laggard.unrealizedPL, currencyCode: currencyCode),
                    locale: locale
                )
            )
        } else {
            parts.append(
                L10n.HomeAI.briefingEquityClause(
                    equity: AppFormatter.compactMoney(netEquity, currencyCode: currencyCode),
                    locale: locale
                )
            )
        }

        let summary = parts.joined(separator: " ")

        var tags: [PortfolioBriefingTag] = []
        if let topSymbol = health.topHoldingSymbol, health.concentrationRatio > 0 {
            tags.append(
                PortfolioBriefingTag(
                    id: "top-weight",
                    label: L10n.HomeAI.tagTopWeight(
                        symbol: topSymbol,
                        weight: AppFormatter.percent(health.concentrationRatio, fractionLength: 0),
                        locale: locale
                    ),
                    tone: health.concentrationRatio >= 0.35 ? .warning : .neutral
                )
            )
        }

        if health.leverageRatio > 1.05 {
            tags.append(
                PortfolioBriefingTag(
                    id: "leverage",
                    label: L10n.HomeAI.tagLeverage(
                        leverage: Self.leverageText(health.leverageRatio),
                        locale: locale
                    ),
                    tone: health.leverageRatio > 1.4 ? .negative : .warning
                )
            )
        } else if health.cashRatio >= 0 {
            tags.append(
                PortfolioBriefingTag(
                    id: "cash",
                    label: L10n.HomeAI.tagCash(
                        percent: AppFormatter.percent(health.cashRatio, fractionLength: 0),
                        locale: locale
                    ),
                    tone: .neutral
                )
            )
        }

        if let winRate = health.winRate {
            tags.append(
                PortfolioBriefingTag(
                    id: "win-rate",
                    label: L10n.HomeAI.tagWinRate(
                        percent: AppFormatter.percent(winRate, fractionLength: 0),
                        locale: locale
                    ),
                    tone: winRate >= 0.55 ? .positive : (winRate <= 0.35 ? .negative : .neutral)
                )
            )
        }

        if openOrdersCount > 0 {
            tags.append(
                PortfolioBriefingTag(
                    id: "open-orders",
                    label: L10n.HomeAI.tagOpenOrders(count: openOrdersCount, locale: locale),
                    tone: .brand
                )
            )
        }

        return PortfolioAIBriefing(headline: headline, summary: summary, tags: tags)
    }

    private func buildSuggestedPrompts(
        health: PortfolioHealthAssessment,
        topHolding: ParsedPosition?,
        topConcentration: Double,
        leverageRatio: Double,
        cashRatio: Double,
        openOrdersCount: Int,
        locale: Locale
    ) -> [PortfolioCopilotPrompt] {
        var prompts: [PortfolioCopilotPrompt] = [
            PortfolioCopilotPrompt(
                id: "health-diagnosis",
                title: L10n.HomeAI.promptChipHealth(locale: locale),
                prompt: L10n.HomeAI.promptHealthDiagnosis(locale: locale),
                systemImage: AppIcon.Intelligence.health
            )
        ]

        if let topHolding, topConcentration >= 0.25 {
            prompts.append(
                PortfolioCopilotPrompt(
                    id: "rebalance-top",
                    title: L10n.HomeAI.promptChipRebalance(symbol: topHolding.symbol, locale: locale),
                    prompt: L10n.HomeAI.promptRebalanceSymbol(symbol: topHolding.symbol, locale: locale),
                    systemImage: AppIcon.Intelligence.rebalance
                )
            )
        }

        if leverageRatio > 1.15 {
            prompts.append(
                PortfolioCopilotPrompt(
                    id: "margin-check",
                    title: L10n.HomeAI.promptChipMargin(locale: locale),
                    prompt: L10n.HomeAI.promptMarginRisk(locale: locale),
                    systemImage: AppIcon.Intelligence.shield
                )
            )
        } else if cashRatio >= 0.25 {
            prompts.append(
                PortfolioCopilotPrompt(
                    id: "cash-plan",
                    title: L10n.HomeAI.promptChipCash(locale: locale),
                    prompt: L10n.HomeAI.promptCashPlan(locale: locale),
                    systemImage: AppIcon.Account.cash
                )
            )
        }

        prompts.append(
            PortfolioCopilotPrompt(
                id: "attribution",
                title: L10n.HomeAI.promptChipAttribution(locale: locale),
                prompt: L10n.HomeAI.promptAttribution(locale: locale),
                systemImage: AppIcon.Intelligence.attribution
            )
        )

        if openOrdersCount > 0 {
            prompts.append(
                PortfolioCopilotPrompt(
                    id: "orders",
                    title: L10n.HomeAI.promptChipOrders(locale: locale),
                    prompt: L10n.HomeAI.promptOrders(locale: locale),
                    systemImage: AppIcon.More.orders
                )
            )
        }

        return Array(prompts.prefix(4))
    }

    // MARK: - Copilot Response Builders

    private func buildPositionDiagnosisResponse(
        position: AlpacaPosition,
        snapshot: PortfolioIntelligenceSnapshot,
        currencyCode: String,
        locale: Locale
    ) -> PortfolioCopilotMessage {
        let symbol = position.symbol.uppercased()
        let weight = snapshot.positionWeightsBySymbol[symbol] ?? 0
        let mv = NumberParser.double(from: position.marketValue) ?? 0
        let pl = NumberParser.double(from: position.unrealizedPL) ?? 0
        let plpc = NumberParser.double(from: position.unrealizedPLPC)

        let text = L10n.HomeAI.copilotPositionReply(
            symbol: symbol,
            weight: AppFormatter.percent(weight, fractionLength: 1),
            marketValue: AppFormatter.compactMoney(mv, currencyCode: currencyCode),
            plAmount: AppFormatter.signedCompactMoney(pl, currencyCode: currencyCode),
            plPercent: AppFormatter.signedPercent(plpc, fractionLength: 1),
            locale: locale
        )

        return PortfolioCopilotMessage(
            role: .assistant,
            text: text,
            highlights: [
                PortfolioCopilotMetric(
                    id: "weight",
                    label: L10n.HomeAI.metricWeight(locale: locale),
                    value: AppFormatter.percent(weight, fractionLength: 1),
                    tone: weight >= 0.30 ? .warning : .neutral
                ),
                PortfolioCopilotMetric(
                    id: "pl",
                    label: L10n.HomeAI.metricUnrealizedPL(locale: locale),
                    value: AppFormatter.signedCompactMoney(pl, currencyCode: currencyCode),
                    tone: pl >= 0 ? .positive : .negative
                )
            ],
            ctaTitle: L10n.HomeAI.ctaInspectSymbol(symbol: symbol, locale: locale),
            destination: .position(symbol: symbol)
        )
    }

    private func rebalanceDetail(position: AlpacaPosition, weight: Double, currencyCode: String, locale: Locale) -> String {
        guard weight < 1 else {
            return L10n.format("home_ai.rebalance.sole_holding", locale: locale, position.symbol)
        }
        // Cash is excluded from gross exposure. After trimming x, (holding - x) / (gross - x) = 0.25.
        let holding = abs(NumberParser.double(from: position.marketValue) ?? 0)
        let gross = weight > 0 ? holding / weight : 0
        let trim = max(0, (holding - 0.25 * gross) / 0.75)
        if trim == 0 {
            return L10n.format("home_ai.rebalance.within_limit", locale: locale, position.symbol)
        }
        return L10n.HomeAI.actionConcentrationDetail(
            symbol: position.symbol,
            weight: AppFormatter.percent(weight, fractionLength: 1),
            trimAmount: AppFormatter.compactMoney(trim, currencyCode: currencyCode),
            locale: locale
        )
    }

    private func buildRebalanceResponse(
        position: AlpacaPosition,
        snapshot: PortfolioIntelligenceSnapshot,
        currencyCode: String,
        locale: Locale
    ) -> PortfolioCopilotMessage {
        let topSymbol = position.symbol.uppercased()
        let topWeight = snapshot.positionWeightsBySymbol[topSymbol] ?? 0
        let text = rebalanceDetail(position: position, weight: topWeight, currencyCode: currencyCode, locale: locale)

        return PortfolioCopilotMessage(
            role: .assistant,
            text: text,
            highlights: [
                PortfolioCopilotMetric(
                    id: "top",
                    label: topSymbol,
                    value: AppFormatter.percent(topWeight, fractionLength: 1),
                    tone: topWeight >= 0.30 ? .warning : .positive
                ),
                PortfolioCopilotMetric(
                    id: "div",
                    label: L10n.HomeAI.subscoreDiversification(locale: locale),
                    value: "\(snapshot.health.diversificationScore)/100",
                    tone: snapshot.health.diversificationScore >= 70 ? .positive : .warning
                )
            ],
            ctaTitle: topWeight > 0.25
                ? L10n.HomeAI.ctaTrimPosition(symbol: topSymbol, locale: locale)
                : L10n.HomeAI.ctaInspectSymbol(symbol: topSymbol, locale: locale),
            destination: topWeight > 0.25
                ? position.trimDestination
                : .position(symbol: topSymbol)
        )
    }

    private func buildLiquidityRiskResponse(
        snapshot: PortfolioIntelligenceSnapshot,
        currencyCode: String,
        locale: Locale
    ) -> PortfolioCopilotMessage {
        let alloc = snapshot.allocation
        let leverageText = Self.leverageText(alloc.leverageRatio)
        let text = L10n.HomeAI.copilotLiquidityReply(
            buyingPower: AppFormatter.compactMoney(alloc.buyingPower, currencyCode: currencyCode),
            cash: AppFormatter.compactMoney(alloc.cashBalance, currencyCode: currencyCode),
            leverage: leverageText,
            liquidityScore: snapshot.health.liquidityScore,
            locale: locale
        )

        return PortfolioCopilotMessage(
            role: .assistant,
            text: text,
            highlights: [
                PortfolioCopilotMetric(
                    id: "bp",
                    label: L10n.HomeAI.metricBuyingPower(locale: locale),
                    value: AppFormatter.compactMoney(alloc.buyingPower, currencyCode: currencyCode),
                    tone: alloc.buyingPower <= 0 ? .negative : .positive
                ),
                PortfolioCopilotMetric(
                    id: "lev",
                    label: L10n.HomeAI.metricLeverage(locale: locale),
                    value: leverageText,
                    tone: alloc.leverageRatio > 1.35 ? .warning : .neutral
                )
            ],
            ctaTitle: L10n.HomeAI.ctaReviewMargin(locale: locale),
            destination: .account
        )
    }

    private func buildAttributionResponse(
        snapshot: PortfolioIntelligenceSnapshot,
        currencyCode: String,
        locale: Locale
    ) -> PortfolioCopilotMessage {
        let leader = snapshot.attribution.topContributors.first
        let laggard = snapshot.attribution.topDetractors.first
        let leaderText = leader.map { "\($0.symbol) (\(AppFormatter.signedCompactMoney($0.unrealizedPL, currencyCode: currencyCode)))" } ?? "--"
        let laggardText = laggard.map { "\($0.symbol) (\(AppFormatter.signedCompactMoney($0.unrealizedPL, currencyCode: currencyCode)))" } ?? "--"

        let text = L10n.HomeAI.copilotAttributionReply(
            totalPL: AppFormatter.signedCompactMoney(snapshot.attribution.totalUnrealizedPL, currencyCode: currencyCode),
            leader: leaderText,
            laggard: laggardText,
            locale: locale
        )

        var highlights: [PortfolioCopilotMetric] = []
        if let leader {
            highlights.append(
                PortfolioCopilotMetric(
                    id: "leader",
                    label: leader.symbol,
                    value: AppFormatter.signedCompactMoney(leader.unrealizedPL, currencyCode: currencyCode),
                    tone: .positive
                )
            )
        }
        if let laggard {
            highlights.append(
                PortfolioCopilotMetric(
                    id: "laggard",
                    label: laggard.symbol,
                    value: AppFormatter.signedCompactMoney(laggard.unrealizedPL, currencyCode: currencyCode),
                    tone: .negative
                )
            )
        }

        let targetSymbol = laggard?.symbol ?? leader?.symbol
        return PortfolioCopilotMessage(
            role: .assistant,
            text: text,
            highlights: highlights,
            ctaTitle: targetSymbol.map { L10n.HomeAI.ctaInspectSymbol(symbol: $0, locale: locale) },
            destination: targetSymbol.map { .position(symbol: $0) } ?? .positions
        )
    }

    private func buildOrdersResponse(
        portfolio: PortfolioState,
        snapshot: PortfolioIntelligenceSnapshot,
        locale: Locale
    ) -> PortfolioCopilotMessage {
        let count = snapshot.openOrdersCount
        let text = L10n.HomeAI.copilotOrdersReply(
            openCount: count,
            totalRecent: portfolio.orders.count,
            locale: locale
        )

        return PortfolioCopilotMessage(
            role: .assistant,
            text: text,
            highlights: [
                PortfolioCopilotMetric(
                    id: "open-orders",
                    label: L10n.HomeAI.metricOpenOrders(locale: locale),
                    value: "\(count)",
                    tone: count > 0 ? .brand : .neutral
                )
            ],
            ctaTitle: L10n.HomeAI.ctaReviewOrders(locale: locale),
            destination: .orders
        )
    }

    private func buildHealthResponse(
        snapshot: PortfolioIntelligenceSnapshot,
        locale: Locale
    ) -> PortfolioCopilotMessage {
        let h = snapshot.health
        let text = L10n.HomeAI.copilotHealthReply(
            score: h.score,
            diversification: h.diversificationScore,
            liquidity: h.liquidityScore,
            momentum: h.momentumScore,
            locale: locale
        )

        return PortfolioCopilotMessage(
            role: .assistant,
            text: text,
            highlights: [
                PortfolioCopilotMetric(
                    id: "div",
                    label: L10n.HomeAI.subscoreDiversification(locale: locale),
                    value: "\(h.diversificationScore)",
                    tone: tone(forScore: h.diversificationScore)
                ),
                PortfolioCopilotMetric(
                    id: "liq",
                    label: L10n.HomeAI.subscoreLiquidity(locale: locale),
                    value: "\(h.liquidityScore)",
                    tone: tone(forScore: h.liquidityScore)
                ),
                PortfolioCopilotMetric(
                    id: "mom",
                    label: L10n.HomeAI.subscoreMomentum(locale: locale),
                    value: "\(h.momentumScore)",
                    tone: tone(forScore: h.momentumScore)
                )
            ],
            ctaTitle: snapshot.actions.first?.ctaTitle,
            destination: snapshot.actions.first?.destination
        )
    }

    private func buildOverviewResponse(
        snapshot: PortfolioIntelligenceSnapshot,
        currencyCode: String,
        locale: Locale
    ) -> PortfolioCopilotMessage {
        let text = L10n.HomeAI.copilotOverviewReply(
            equity: AppFormatter.compactMoney(snapshot.allocation.netEquity, currencyCode: currencyCode),
            score: snapshot.health.score,
            headline: snapshot.briefing.headline,
            summary: snapshot.briefing.summary,
            locale: locale
        )

        return PortfolioCopilotMessage(
            role: .assistant,
            text: text,
            highlights: [
                PortfolioCopilotMetric(
                    id: "score",
                    label: L10n.HomeAI.healthScoreLabel(locale: locale),
                    value: "\(snapshot.health.score)/100",
                    tone: tone(forScore: snapshot.health.score)
                ),
                PortfolioCopilotMetric(
                    id: "equity",
                    label: L10n.HomeAI.metricNetEquity(locale: locale),
                    value: AppFormatter.compactMoney(snapshot.allocation.netEquity, currencyCode: currencyCode),
                    tone: .neutral
                )
            ],
            ctaTitle: snapshot.actions.first?.ctaTitle,
            destination: snapshot.actions.first?.destination
        )
    }

    // MARK: - Helpers

    private func findMentionedPosition(in query: String, positions: [AlpacaPosition]) -> AlpacaPosition? {
        let uppercase = query.uppercased()
        let tickerCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        let tokens = Set(uppercase.components(separatedBy: tickerCharacters.inverted).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".-")) })
        return positions.first { tokens.contains($0.symbol.uppercased()) }
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func leverageText(_ ratio: Double) -> String {
        ratio.isFinite ? String(format: "%.2fx", ratio) : "∞"
    }

    private func clampScore(_ value: Double) -> Int {
        min(99, max(12, Int(value.rounded())))
    }

    private func tone(forScore score: Int) -> PortfolioTagTone {
        switch score {
        case 80...100: .positive
        case 60..<80: .brand
        case 40..<60: .warning
        default: .negative
        }
    }
}

private extension AlpacaPosition {
    var trimDestination: PortfolioAIActionDestination {
        let short = side?.lowercased() == "short" || (NumberParser.double(from: quantity) ?? 0) < 0
        switch assetCategory {
        case .option:
            return .closeOption(symbol: symbol, intent: short ? .buyToClose : .sellToClose)
        case .stock, .etf:
            return .trade(symbol: symbol, side: short ? .buy : .sell)
        case .crypto:
            return .position(symbol: symbol)
        }
    }
}

private struct ParsedPosition {
    let position: AlpacaPosition
    let symbol: String
    let category: PositionAssetCategory
    let marketValue: Double
    let absMarketValue: Double
    let unrealizedPL: Double
    let unrealizedPLPercent: Double?
    let quantity: Double
    let currentPrice: Double?
    let averageEntryPrice: Double?
}
