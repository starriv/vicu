import Foundation
import CryptoKit

extension AppModel {
    func bootstrap() async {
        isCredentialBootstrapComplete = false
        let generation = nextCredentialOperationGeneration()
        await loadCredentials(for: environment, generation: generation, completesBootstrap: true)
    }

    @discardableResult
    func testConnection(keyID: String, secretKey: String) async -> Bool {
        guard let candidate = makeCredentials(keyID: keyID, secretKey: secretKey) else {
            setCredentialMessage(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
            credentialsStatus = .missing
            return false
        }

        let generation = nextCredentialOperationGeneration()
        credentialsStatus = .testing(candidate.environment)
        connectionDiagnostics = nil
        verifiedCredentialFingerprint = nil
        clearCredentialMessage()

        do {
            try await testAlpacaConnection(credentials: candidate, generation: generation)
            guard isCurrentCredentialOperation(generation, environment: candidate.environment) else {
                return false
            }
            verifiedCredentialFingerprint = credentialVerificationFingerprint(candidate)
            credentialsStatus = .verified(candidate.environment)
            return true
        } catch where error.isRequestCancellation {
            guard isCurrentCredentialOperation(generation, environment: candidate.environment) else {
                return false
            }
            credentialsStatus = .untested(candidate.environment)
            return false
        } catch {
            guard isCurrentCredentialOperation(generation, environment: candidate.environment) else {
                return false
            }
            let message = credentialErrorMessage(for: error)
            credentialsStatus = .failed(candidate.environment, message: message)
            setCredentialMessage(message)
            return false
        }
    }

    @discardableResult
    func connectAndSaveCredentials(keyID: String, secretKey: String) async -> CredentialConnectResult {
        guard let newCredentials = makeCredentials(keyID: keyID, secretKey: secretKey) else {
            let message = L10n.Credentials.apiKeyRequired(locale: appLanguage.locale)
            setCredentialMessage(message)
            credentialsStatus = .missing
            return .failure(message)
        }

        let generation = nextCredentialOperationGeneration()
        credentialsStatus = .testing(newCredentials.environment)
        connectionDiagnostics = nil
        verifiedCredentialFingerprint = nil
        clearCredentialMessage()

        do {
            try await testAlpacaConnection(credentials: newCredentials, generation: generation)
            guard isCurrentCredentialOperation(generation, environment: newCredentials.environment) else {
                return .cancelled
            }

            guard persistVerifiedCredentials(newCredentials, generation: generation) else {
                return .failure(credentialMessage ?? L10n.Credentials.testRequired(locale: appLanguage.locale))
            }

            return .success(newCredentials.environment)
        } catch where error.isRequestCancellation {
            guard isCurrentCredentialOperation(generation, environment: newCredentials.environment) else {
                return .cancelled
            }
            credentialsStatus = .untested(newCredentials.environment)
            return .cancelled
        } catch {
            guard isCurrentCredentialOperation(generation, environment: newCredentials.environment) else {
                return .cancelled
            }
            let message = credentialErrorMessage(for: error)
            credentialsStatus = .failed(newCredentials.environment, message: message)
            setCredentialMessage(message)
            return .failure(message)
        }
    }

    @discardableResult
    func saveCredentials(keyID: String, secretKey: String) async -> Bool {
        guard let newCredentials = makeCredentials(keyID: keyID, secretKey: secretKey) else {
            setCredentialMessage(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
            credentialsStatus = .missing
            return false
        }

        guard verifiedCredentialFingerprint == credentialVerificationFingerprint(newCredentials) else {
            setCredentialMessage(L10n.Credentials.testRequired(locale: appLanguage.locale))
            credentialsStatus = .untested(newCredentials.environment)
            return false
        }

        let generation = nextCredentialOperationGeneration()
        return persistVerifiedCredentials(newCredentials, generation: generation)
    }

    private func persistVerifiedCredentials(_ newCredentials: AlpacaCredentials, generation: Int) -> Bool {
        guard isCurrentCredentialOperation(generation, environment: newCredentials.environment) else {
            return false
        }

        let previousCredentials = credentials
        do {
            try services.credentialStore.save(newCredentials)
            if let previousCredentials {
                services.stockStream.reset(credentials: previousCredentials)
            }
            setCredentials(newCredentials)
            isCredentialBootstrapComplete = true
            selectedTab = .home
            cachedMarketOverview = nil
            resetFavoriteMarketSymbols()
            verifiedCredentialFingerprint = nil
            credentialsStatus = .connected(newCredentials.environment)
            startAccountEventListeners(credentials: newCredentials)
            clearPortfolioSnapshot()
            clearCredentialMessage()
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
            return true
        } catch {
            guard isCurrentCredentialOperation(generation, environment: newCredentials.environment) else {
                return false
            }
            let message = credentialErrorMessage(for: error)
            credentialsStatus = .failed(newCredentials.environment, message: message)
            setCredentialMessage(message)
            return false
        }
    }

    func updateEnvironment(_ newEnvironment: TradeEnvironment) async {
        let generation = nextCredentialOperationGeneration()
        environment = newEnvironment
        stopAccountEventListeners()
        connectionDiagnostics = nil
        verifiedCredentialFingerprint = nil
        clearCredentialMessage()
        cachedMarketOverview = nil
        resetFavoriteMarketSymbols()
        await loadCredentials(for: newEnvironment, generation: generation)
    }

    func invalidateCredentialInput() {
        connectionDiagnostics = nil
        verifiedCredentialFingerprint = nil
        credentialMessage = nil
        if !hasCredentials {
            credentialsStatus = .missing
        } else if !credentialsStatus.isConnected {
            credentialsStatus = .untested(environment)
        }
    }

    func testSavedConnection() async {
        guard let credentials else {
            credentialsStatus = .missing
            return
        }

        let generation = nextCredentialOperationGeneration()
        await verifyStoredCredentials(credentials, generation: generation)
    }

    func clearCredentials() async {
        let generation = nextCredentialOperationGeneration()
        let credentialsToClear = credentials
        do {
            try services.credentialStore.delete(environment: environment)
            if let credentialsToClear {
                services.stockStream.reset(credentials: credentialsToClear)
            }
            stopAccountEventListeners()
            setCredentials(nil)
            connectionDiagnostics = nil
            verifiedCredentialFingerprint = nil
            cachedMarketOverview = nil
            credentialsStatus = .missing
            portfolio.clear()
            resetFavoriteMarketSymbols()
            clearCredentialMessage()
        } catch {
            guard isCurrentCredentialOperation(generation, environment: environment) else {
                return
            }
            setCredentialMessage(credentialErrorMessage(for: error))
        }
    }

    private func loadCredentials(
        for environment: TradeEnvironment,
        generation: Int,
        completesBootstrap: Bool = false
    ) async {
        do {
            if let stored = try services.credentialStore.load(environment: environment) {
                guard isCurrentCredentialOperation(generation, environment: environment) else {
                    return
                }
                setCredentials(stored)
                completeCredentialBootstrapIfNeeded(completesBootstrap)
                await verifyStoredCredentials(stored, generation: generation)
            } else {
                guard isCurrentCredentialOperation(generation, environment: environment) else {
                    return
                }
                setCredentials(nil)
                connectionDiagnostics = nil
                cachedMarketOverview = nil
                credentialsStatus = .missing
                portfolio.clear()
                resetFavoriteMarketSymbols()
                verifiedCredentialFingerprint = nil
                clearCredentialMessage()
                completeCredentialBootstrapIfNeeded(completesBootstrap)
            }
        } catch {
            guard isCurrentCredentialOperation(generation, environment: environment) else {
                return
            }
            setCredentials(nil)
            connectionDiagnostics = nil
            cachedMarketOverview = nil
            credentialsStatus = .missing
            verifiedCredentialFingerprint = nil
            setCredentialMessage(credentialErrorMessage(for: error))
            portfolio.clear()
            resetFavoriteMarketSymbols()
            completeCredentialBootstrapIfNeeded(completesBootstrap)
        }
    }

    private func setCredentialMessage(_ message: String) {
        credentialMessage = message
        lastError = message
    }

    private func clearCredentialMessage() {
        credentialMessage = nil
        lastError = nil
    }

    private func credentialErrorMessage(for error: Error) -> String {
        APIErrorDisplayMessage.message(for: error, locale: appLanguage.locale)
    }

    private func completeCredentialBootstrapIfNeeded(_ shouldComplete: Bool) {
        guard shouldComplete else {
            return
        }

        isCredentialBootstrapComplete = true
    }

    private func setCredentials(_ newCredentials: AlpacaCredentials?) {
        if credentials != newCredentials {
            stopAccountEventListeners()
            recentActivityRefIDs.removeAll()
            recentActivityRefIDOrder.removeAll()
            recentTradeEventIDs.removeAll()
            recentTradeEventIDOrder.removeAll()
            resetMarketSearchCaches()
        }

        credentials = newCredentials
        hasCredentials = newCredentials != nil
    }

    private func nextCredentialOperationGeneration() -> Int {
        credentialOperationGeneration += 1
        return credentialOperationGeneration
    }

    private func isCurrentCredentialOperation(_ generation: Int, environment: TradeEnvironment) -> Bool {
        credentialOperationGeneration == generation && self.environment == environment
    }

    func isCurrentCredentialContext(_ credentials: AlpacaCredentials) -> Bool {
        self.credentials == credentials && environment == credentials.environment
    }

    private func makeCredentials(keyID: String, secretKey: String) -> AlpacaCredentials? {
        let trimmedKeyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyID.isEmpty, !trimmedSecret.isEmpty else {
            return nil
        }

        return AlpacaCredentials(
            keyID: trimmedKeyID,
            secretKey: trimmedSecret,
            environment: environment
        )
    }

    private func credentialVerificationFingerprint(_ credentials: AlpacaCredentials) -> String {
        let rawValue = [
            credentials.environment.rawValue,
            credentials.keyID,
            credentials.secretKey
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func verifyStoredCredentials(_ stored: AlpacaCredentials, generation: Int) async {
        guard isCurrentCredentialOperation(generation, environment: stored.environment) else {
            return
        }
        credentialsStatus = .testing(stored.environment)
        connectionDiagnostics = nil
        verifiedCredentialFingerprint = nil
        clearCredentialMessage()

        do {
            try await testAlpacaConnection(credentials: stored, generation: generation)
            guard isCurrentCredentialOperation(generation, environment: stored.environment) else {
                return
            }
            credentialsStatus = .connected(stored.environment)
            clearCredentialMessage()
            startAccountEventListeners(credentials: stored)
            await refresh()
        } catch where error.isRequestCancellation {
            guard isCurrentCredentialOperation(generation, environment: stored.environment) else {
                return
            }
            credentialsStatus = .untested(stored.environment)
        } catch {
            guard isCurrentCredentialOperation(generation, environment: stored.environment) else {
                return
            }
            let message = credentialErrorMessage(for: error)
            if error.isAuthenticationFailure {
                credentialsStatus = .failed(stored.environment, message: message)
            } else {
                credentialsStatus = .untested(stored.environment)
            }
            setCredentialMessage(message)
        }
    }

    private func testAlpacaConnection(credentials: AlpacaCredentials, generation: Int) async throws {
        let startedAt = Date()

        do {
            try await services.alpaca.testConnection(credentials: credentials)
            if isCurrentCredentialOperation(generation, environment: credentials.environment) {
                recordConnectionDiagnostics(
                    credentials: credentials,
                    startedAt: startedAt,
                    statusCode: 200,
                    succeeded: true
                )
            }
        } catch {
            if isCurrentCredentialOperation(generation, environment: credentials.environment) {
                recordConnectionDiagnostics(
                    credentials: credentials,
                    startedAt: startedAt,
                    statusCode: apiStatusCode(from: error),
                    succeeded: false
                )
            }
            throw error
        }
    }

    private func recordConnectionDiagnostics(
        credentials: AlpacaCredentials,
        startedAt: Date,
        statusCode: Int?,
        succeeded: Bool
    ) {
        let completedAt = Date()
        let latency = max(0, Int((completedAt.timeIntervalSince(startedAt) * 1_000).rounded()))
        connectionDiagnostics = ConnectionDiagnostics(
            environment: credentials.environment,
            endpoint: credentials.environment.accountEndpoint,
            latencyMilliseconds: latency,
            httpStatusCode: statusCode,
            checkedAt: completedAt,
            succeeded: succeeded
        )
    }

    private func apiStatusCode(from error: Error) -> Int? {
        if let apiError = error as? APIClientError {
            return apiError.statusCode
        }

        return nil
    }
}
