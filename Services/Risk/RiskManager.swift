import Foundation
import Observation

@MainActor
@Observable
final class RiskManager {
    var killSwitchEnabled = false
    var liveTradingUnlocked = false
    var requireConfirmation = true
    var maxOrderNotional = 1_000.0
    var maxPositionNotional = 5_000.0

    func evaluate(
        draft: OrderDraft,
        credentials: AlpacaCredentials,
        account: AlpacaAccount?,
        locale: Locale = .current
    ) -> RiskDecision {
        if killSwitchEnabled {
            return .rejected(L10n.Risk.killSwitchDecision(locale: locale))
        }

        if credentials.environment == .live && !liveTradingUnlocked {
            return .rejected(L10n.Risk.liveLockedDecision(locale: locale))
        }

        if let estimatedNotional = draft.estimatedNotional {
            let maxAllowed = Decimal(maxOrderNotional)
            if estimatedNotional > maxAllowed {
                return .rejected(L10n.Risk.maxOrderExceededDecision(locale: locale))
            }
        }

        if account == nil {
            return .allowed(L10n.Risk.accountMissingStaticDecision(locale: locale))
        }

        return .allowed(L10n.Risk.checksPassedDecision(locale: locale))
    }
}

struct RiskDecision: Equatable {
    let isAllowed: Bool
    let message: String

    static func allowed(_ message: String) -> RiskDecision {
        RiskDecision(isAllowed: true, message: message)
    }

    static func rejected(_ message: String) -> RiskDecision {
        RiskDecision(isAllowed: false, message: message)
    }
}
