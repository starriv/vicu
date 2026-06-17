import SwiftUI

struct RiskView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var risk = app.riskManager

        BasicLayout(L10n.Risk.title, style: .form) {
            Section(L10n.Risk.globalControls) {
                Toggle(L10n.Risk.killSwitch, isOn: $risk.killSwitchEnabled)
                    .tint(.red)
                Toggle(L10n.Risk.requireOrderConfirmation, isOn: $risk.requireConfirmation)
                Toggle(L10n.Risk.unlockLiveTrading, isOn: $risk.liveTradingUnlocked)
                    .tint(.orange)
            }

            Section(L10n.Risk.limits) {
                Stepper(value: $risk.maxOrderNotional, in: 1...1_000_000, step: 100) {
                    HStack {
                        Text(L10n.Risk.maxOrder)
                        Spacer()
                        Text(AppFormatter.money(risk.maxOrderNotional, fractionLength: 0))
                            .font(AppTypography.rowValue)
                    }
                }

                Stepper(value: $risk.maxPositionNotional, in: 1...5_000_000, step: 500) {
                    HStack {
                        Text(L10n.Risk.maxPosition)
                        Spacer()
                        Text(AppFormatter.money(risk.maxPositionNotional, fractionLength: 0))
                            .font(AppTypography.rowValue)
                    }
                }
            }

            Section(L10n.Risk.status) {
                Label(
                    app.environment == .paper ? L10n.Risk.paperTradingSelected : L10n.Risk.liveTradingSelected,
                    systemImage: app.environment == .paper ? AppIcon.Risk.paperTrading : AppIcon.Risk.liveTrading
                )
                Label(
                    app.credentialsStatus.title(locale: locale),
                    systemImage: app.canUseAlpacaAPI ? AppIcon.Risk.credentialsReady : AppIcon.Risk.credentialsMissing
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        RiskView()
            .environment(AppModel())
    }
}
