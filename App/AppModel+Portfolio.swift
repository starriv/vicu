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

        portfolio.isRefreshing = true
        defer { portfolio.isRefreshing = false }

        do {
            async let accountRequest = services.alpaca.fetchAccount(credentials: activeCredentials)
            async let positionsRequest = services.alpaca.fetchPositions(credentials: activeCredentials)
            async let ordersRequest = services.alpaca.fetchRecentOrders(credentials: activeCredentials)
            async let historyRequest = services.alpaca.fetchPortfolioHistory(
                range: portfolio.historyRange,
                accountCreatedAt: portfolio.account?.createdAt,
                credentials: activeCredentials
            )

            let (account, positions, orders, history) = try await (
                accountRequest,
                positionsRequest,
                ordersRequest,
                historyRequest
            )
            guard isCurrentCredentialContext(activeCredentials) else {
                return
            }
            portfolio.applySnapshot(
                account: account,
                positions: positions,
                orders: orders,
                history: history
            )
            credentialsStatus = .connected(activeCredentials.environment)
            startAccountEventListeners(credentials: activeCredentials)
            lastError = nil
            await refreshFavoriteMarketSymbols()
        } catch where error.isRequestCancellation {
            return
        } catch {
            guard isCurrentCredentialContext(activeCredentials) else {
                return
            }
            if error.isAuthenticationFailure {
                credentialsStatus = .failed(activeCredentials.environment, message: error.localizedDescription)
                stopAccountEventListeners()
            } else if !credentialsStatus.isConnected {
                credentialsStatus = .connected(activeCredentials.environment)
            }
            lastError = error.localizedDescription
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
            async let accountRequest = services.alpaca.fetchAccount(credentials: activeCredentials)
            async let positionsRequest = services.alpaca.fetchPositions(credentials: activeCredentials)
            let (account, positions) = try await (accountRequest, positionsRequest)
            guard isCurrentCredentialContext(activeCredentials) else {
                return
            }

            portfolio.account = account
            portfolio.positions = positions
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
            return
        }

        portfolio.isLoadingHistory = true
        defer { portfolio.isLoadingHistory = false }

        do {
            portfolio.history = try await services.alpaca.fetchPortfolioHistory(
                range: portfolio.historyRange,
                accountCreatedAt: portfolio.account?.createdAt,
                credentials: credentials
            )
            lastError = nil
        } catch where error.isRequestCancellation {
            return
        } catch {
            portfolio.history = []
            lastError = error.localizedDescription
        }
    }

    func fetchAccountDetails() async throws -> AlpacaAccount {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let account = try await services.alpaca.fetchAccount(credentials: credentials)
        portfolio.account = account
        return account
    }

    func fetchAccountActivities(pageSize: Int = 100, pageToken: String? = nil) async throws -> AlpacaAccountActivitiesPage {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.alpaca.fetchAccountActivities(
            pageSize: pageSize,
            pageToken: pageToken,
            credentials: credentials
        )
    }

    func fetchOrderDetail(orderID: String) async throws -> AlpacaOrder {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let order = try await services.alpaca.fetchOrder(id: orderID, nested: true, credentials: credentials)
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

        try await services.alpaca.cancelOrder(id: order.id, credentials: credentials)
        lastError = nil
        await refresh()
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
            replacedOrder = try await services.alpaca.replaceOrder(id: order.id, request: request, credentials: credentials)
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
            let submittedOrder = try await services.alpaca.submitOrder(
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

    private func marketAssets(credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        if let marketAssetCache,
           let marketAssetCacheDate,
           Date().timeIntervalSince(marketAssetCacheDate) < marketAssetCacheTTL {
            return marketAssetCache
        }

        let fetchedAssets = try await services.alpaca.fetchMarketAssets(credentials: credentials)
        let assets = fetchedAssets.filter { asset in
            asset.symbol.isEmpty == false && asset.status?.lowercased() == "active"
        }

        marketAssetCache = assets
        marketAssetCacheDate = Date()
        return assets
    }

    private func mergePortfolioOrder(_ order: AlpacaOrder) {
        if let index = portfolio.orders.firstIndex(where: { $0.id == order.id }) {
            portfolio.orders[index] = order
        } else {
            portfolio.orders.insert(order, at: 0)
        }
    }

    private func replacePortfolioOrder(oldID: String, with order: AlpacaOrder) {
        if oldID != order.id {
            removePortfolioOrder(id: oldID)
        }
        mergePortfolioOrder(order)
    }

    private func removePortfolioOrder(id: String) {
        portfolio.orders.removeAll { $0.id == id }
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
}
