import Foundation

extension AppModel {
    func refresh() async {
        guard let activeCredentials = credentials else {
            credentialsStatus = .missing
            connectionDiagnostics = nil
            portfolio.clear()
            stopAccountEventListeners()
            return
        }

        let portfolioService = services.portfolio
        let ordersService = services.orders
        let historyRange = portfolio.historyRange
        let accountCreatedAt = portfolio.account?.createdAt
        var didReceiveValue = false
        var firstFailure: PortfolioRefreshFailure?
        var authenticationFailure: PortfolioRefreshFailure?

        portfolio.prepareForRefresh()
        defer {
            portfolio.isRefreshing = false
            portfolio.isLoadingHistory = false
        }

        await withTaskGroup(of: PortfolioRefreshResult.self) { group in
            group.addTask {
                do {
                    return .account(try await portfolioService.fetchAccount(credentials: activeCredentials))
                } catch {
                    return .failure(.init(segment: .account, error: error))
                }
            }

            group.addTask {
                do {
                    return .positions(try await portfolioService.fetchPositions(credentials: activeCredentials))
                } catch {
                    return .failure(.init(segment: .positions, error: error))
                }
            }

            group.addTask {
                do {
                    return .orders(try await ordersService.fetchRecentOrders(credentials: activeCredentials))
                } catch {
                    return .failure(.init(segment: .orders, error: error))
                }
            }

            group.addTask {
                do {
                    return .history(
                        range: historyRange,
                        try await portfolioService.fetchPortfolioHistory(
                            range: historyRange,
                            accountCreatedAt: accountCreatedAt,
                            credentials: activeCredentials
                        )
                    )
                } catch {
                    return .failure(.init(segment: .history, error: error))
                }
            }

            for await result in group {
                guard isCurrentCredentialContext(activeCredentials) else {
                    group.cancelAll()
                    return
                }

                switch result {
                case .account(let account):
                    portfolio.applyAccount(account)
                    credentialsStatus = .connected(activeCredentials.environment)
                    startAccountEventListeners(credentials: activeCredentials)
                    lastError = nil
                    didReceiveValue = true
                case .positions(let positions):
                    portfolio.applyPositions(positions)
                    didReceiveValue = true
                case .orders(let orders):
                    portfolio.applyOrders(orders)
                    didReceiveValue = true
                case .history(let range, let history):
                    guard portfolio.historyRange == range else {
                        continue
                    }

                    portfolio.applyHistory(history)
                    didReceiveValue = true
                case .failure(let failure):
                    guard !failure.isCancellation else {
                        continue
                    }

                    firstFailure = firstFailure ?? failure
                    if failure.isAuthenticationFailure {
                        authenticationFailure = failure
                    }
                }
            }
        }

        guard isCurrentCredentialContext(activeCredentials) else {
            return
        }

        if let authenticationFailure {
            applyPortfolioRefreshFailure(authenticationFailure, credentials: activeCredentials)
        } else if didReceiveValue {
            credentialsStatus = .connected(activeCredentials.environment)
            lastError = nil
            await refreshFavoriteMarketSymbols()
        } else if let firstFailure {
            applyPortfolioRefreshFailure(firstFailure, credentials: activeCredentials)
        }
    }

    func refreshPositions() async throws {
        guard let activeCredentials = credentials else {
            credentialsStatus = .missing
            connectionDiagnostics = nil
            portfolio.clear()
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        portfolio.isRefreshing = true
        defer { portfolio.isRefreshing = false }

        do {
            async let accountRequest = services.portfolio.fetchAccount(credentials: activeCredentials)
            async let positionsRequest = services.portfolio.fetchPositions(credentials: activeCredentials)
            let (account, positions) = try await (accountRequest, positionsRequest)
            guard isCurrentCredentialContext(activeCredentials) else {
                return
            }

            portfolio.applyAccount(account)
            portfolio.applyPositions(positions)
            credentialsStatus = .connected(activeCredentials.environment)
            lastError = nil
        } catch where error.isRequestCancellation {
            throw error
        } catch {
            guard isCurrentCredentialContext(activeCredentials) else {
                return
            }

            if error.isAuthenticationFailure {
                credentialsStatus = .failed(activeCredentials.environment, message: error.localizedDescription)
            } else if !credentialsStatus.isConnected {
                credentialsStatus = .connected(activeCredentials.environment)
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    func selectPortfolioHistoryRange(_ range: PortfolioHistoryRange) async {
        guard portfolio.historyRange != range else {
            return
        }

        portfolio.historyRange = range
        await refreshPortfolioHistory()
    }

    func refreshPortfolioHistory() async {
        guard let credentials else {
            portfolio.history = []
            portfolio.hasLoadedHistory = false
            return
        }

        portfolio.isLoadingHistory = true
        defer { portfolio.isLoadingHistory = false }

        do {
            let history = try await services.portfolio.fetchPortfolioHistory(
                range: portfolio.historyRange,
                accountCreatedAt: portfolio.account?.createdAt,
                credentials: credentials
            )
            portfolio.applyHistory(history)
            lastError = nil
        } catch where error.isRequestCancellation {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }

    func fetchAccountDetails() async throws -> AlpacaAccount {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let account = try await services.home.fetchAccount(credentials: credentials)
        portfolio.applyAccount(account)
        return account
    }

    func fetchAccountActivities(pageSize: Int = 100, pageToken: String? = nil) async throws -> AlpacaAccountActivitiesPage {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.home.fetchAccountActivities(
            pageSize: pageSize,
            pageToken: pageToken,
            credentials: credentials
        )
    }

    func fetchOrderDetail(orderID: String) async throws -> AlpacaOrder {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let order = try await services.orders.fetchOrder(id: orderID, nested: true, credentials: credentials)
        mergePortfolioOrder(order)
        return order
    }

    func cancelOrder(_ order: AlpacaOrder) async throws {
        guard order.supportsCancellation else {
            throw APIClientError.underlying(L10n.Orders.actionNotCancelable(locale: appLanguage.locale))
        }

        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        try await services.orders.cancelOrder(id: order.id, credentials: credentials)
        lastError = nil
        await refresh()
    }

    @discardableResult
    func closePosition(_ position: AlpacaPosition) async throws -> AlpacaOrder {
        let symbolOrAssetID = closePositionIdentifier(for: position)
        guard !symbolOrAssetID.isEmpty else {
            throw APIClientError.underlying(L10n.PositionDetail.closeUnavailable(locale: appLanguage.locale))
        }

        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let order = try await services.portfolio.closeOpenPosition(
            symbolOrAssetID: symbolOrAssetID,
            credentials: credentials
        )
        mergePortfolioOrder(order)
        lastError = nil

        Task { @MainActor [weak self] in
            await self?.refresh()
        }

        return order
    }

    @discardableResult
    func replaceOrderPrice(_ order: AlpacaOrder, field: AlpacaOrderPriceField, priceText: String) async throws -> AlpacaOrder {
        guard order.supportsPriceReplacement else {
            throw APIClientError.underlying(L10n.Orders.actionNotReplaceable(locale: appLanguage.locale))
        }

        let price = try normalizedOrderPrice(priceText)
        let request = AlpacaReplaceOrderRequest.priceUpdate(price, field: field)
        let replacedOrder: AlpacaOrder

        if let credentials {
            replacedOrder = try await services.orders.replaceOrder(id: order.id, request: request, credentials: credentials)
        } else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        replacePortfolioOrder(oldID: order.id, with: replacedOrder)
        lastError = nil
        return replacedOrder
    }

    func submit(_ draft: OrderDraft, clientOrderID: String?) async -> TradeSubmitResult {
        guard let credentials else {
            let message = L10n.Trade.addCredentialsBeforeOrder(locale: appLanguage.locale)
            lastError = message
            return .failure(message)
        }

        do {
            let submittedOrder = try await services.trade.submitOrder(
                draft,
                clientOrderID: clientOrderID,
                credentials: credentials
            )
            mergePortfolioOrder(submittedOrder)
            let appNotifier = services.appNotifier
            let notificationLocale = appLanguage.locale
            let notificationPreferencesSnapshot = notificationPreferences
            Task {
                await appNotifier.notify(
                    orderSubmitted: submittedOrder,
                    locale: notificationLocale,
                    preferences: notificationPreferencesSnapshot
                )
            }
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
            lastError = nil
            return .success(submittedOrder)
        } catch {
            let message = localizedErrorDescription(error, locale: appLanguage.locale)
            lastError = message
            return .failure(message)
        }
    }

    private func localizedErrorDescription(_ error: Error, locale: Locale) -> String {
        if let orderError = error as? OrderDraftError {
            return orderError.errorDescription(locale: locale)
        }

        return error.localizedDescription
    }

    private func mergePortfolioOrder(_ order: AlpacaOrder) {
        if let index = portfolio.orders.firstIndex(where: { $0.id == order.id }) {
            portfolio.orders[index] = order
        } else {
            portfolio.orders.insert(order, at: 0)
        }
        portfolio.hasLoadedOrders = true
    }

    private func replacePortfolioOrder(oldID: String, with order: AlpacaOrder) {
        if oldID != order.id {
            removePortfolioOrder(id: oldID)
        }
        mergePortfolioOrder(order)
    }

    private func closePositionIdentifier(for position: AlpacaPosition) -> String {
        let normalizedSymbol = position.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !normalizedSymbol.isEmpty {
            return normalizedSymbol
        }

        return position.assetID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func removePortfolioOrder(id: String) {
        portfolio.orders.removeAll { $0.id == id }
        portfolio.hasLoadedOrders = true
    }

    private func normalizedOrderPrice(_ text: String) throws -> String {
        let trimmed = NumberText.trimTrailingZeros(text)
        guard let decimal = NumberParser.decimal(from: trimmed), decimal > 0 else {
            throw APIClientError.underlying(L10n.Orders.invalidPrice(locale: appLanguage.locale))
        }
        return trimmed
    }

    func clearPortfolioSnapshot() {
        portfolio.clear()
    }

    private func applyPortfolioRefreshFailure(
        _ failure: PortfolioRefreshFailure,
        credentials: AlpacaCredentials
    ) {
        if failure.isAuthenticationFailure {
            credentialsStatus = .failed(credentials.environment, message: failure.message)
            stopAccountEventListeners()
        } else if !credentialsStatus.isConnected {
            credentialsStatus = .connected(credentials.environment)
        }

        lastError = failure.message
    }
}

private enum PortfolioRefreshSegment: Sendable {
    case account
    case positions
    case orders
    case history
}

private struct PortfolioRefreshFailure: Sendable {
    let segment: PortfolioRefreshSegment
    let message: String
    let isAuthenticationFailure: Bool
    let isCancellation: Bool

    init(segment: PortfolioRefreshSegment, error: Error) {
        self.segment = segment
        message = error.localizedDescription
        isAuthenticationFailure = error.isAuthenticationFailure
        isCancellation = error.isRequestCancellation
    }
}

private enum PortfolioRefreshResult: Sendable {
    case account(AlpacaAccount)
    case positions([AlpacaPosition])
    case orders([AlpacaOrder])
    case history(range: PortfolioHistoryRange, [PortfolioHistoryPoint])
    case failure(PortfolioRefreshFailure)
}
