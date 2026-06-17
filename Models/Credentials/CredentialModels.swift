import Foundation

enum CredentialConnectResult: Sendable, Equatable {
    case success(TradeEnvironment)
    case failure(String)
    case cancelled
}

enum CredentialsStatus: Equatable {
    case missing
    case untested(TradeEnvironment)
    case testing(TradeEnvironment)
    case verified(TradeEnvironment)
    case connected(TradeEnvironment)
    case failed(TradeEnvironment, message: String)

    var title: String {
        title(locale: .current)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .missing:
            L10n.Credentials.notConnected(locale: locale)
        case .untested(let environment):
            L10n.Credentials.untested(environment.titleText(locale: locale), locale: locale)
        case .testing(let environment):
            L10n.Credentials.testing(environment.titleText(locale: locale), locale: locale)
        case .verified(let environment):
            L10n.Credentials.verified(environment.titleText(locale: locale), locale: locale)
        case .connected(let environment):
            L10n.Credentials.connected(to: environment.titleText(locale: locale), locale: locale)
        case .failed(let environment, _):
            L10n.Credentials.failed(environment.titleText(locale: locale), locale: locale)
        }
    }

    var detail: String {
        detail(locale: .current)
    }

    func detail(locale: Locale) -> String {
        switch self {
        case .missing:
            L10n.Credentials.notConnectedDescription(locale: locale)
        case .untested:
            L10n.Credentials.untestedDescription(locale: locale)
        case .testing:
            L10n.Credentials.testingDescription(locale: locale)
        case .verified:
            L10n.Credentials.verifiedDescription(locale: locale)
        case .connected:
            L10n.Credentials.connectedDescription(locale: locale)
        case .failed(_, let message):
            message
        }
    }

    var isTesting: Bool {
        if case .testing = self {
            return true
        }

        return false
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }

        return false
    }

    var isFailure: Bool {
        if case .failed = self {
            return true
        }

        return false
    }

    var blocksAuthenticatedRoutes: Bool {
        if case .failed = self {
            return true
        }

        return false
    }
}

struct ConnectionDiagnostics: Equatable, Sendable {
    let environment: TradeEnvironment
    let endpoint: String
    let latencyMilliseconds: Int
    let httpStatusCode: Int?
    let checkedAt: Date
    let succeeded: Bool
}

enum CredentialGateState {
    case loading
    case requiresCredentials
    case unlocked
}
