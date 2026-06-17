import SwiftUI

struct AlpacaView: View {
    var body: some View {
        BasicLayout(L10n.Alpaca.title, style: .form) {
            AlpacaCredentialConfigurationView(mode: .settings)

            AlpacaLastMessageSection()
        }
        .scrollDismissesKeyboard(.interactively)
        .tint(AppTheme.ColorToken.brand)
    }
}

struct AlpacaCredentialOnboardingView: View {
    var body: some View {
        ScrollView {
            AlpacaCredentialConfigurationView(mode: .onboarding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .contentMargins(.horizontal, AppTheme.Spacing.pageHorizontal, for: .scrollContent)
        .contentMargins(.top, 56, for: .scrollContent)
        .contentMargins(.bottom, AppTheme.Spacing.pageBottom, for: .scrollContent)
        .tint(AppTheme.ColorToken.brand)
    }
}

private struct OnboardingHeader: View {
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            AppAccountAvatar(size: 72, iconSize: 58)

            VStack(alignment: .center, spacing: 8) {
                Text(L10n.Alpaca.onboardingTitle)
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.Alpaca.onboardingDescription)
                    .font(AppTypography.detail)
                    .foregroundStyle(.secondary)
                    .lineSpacing(AppTypography.secondaryLineSpacing)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private enum AlpacaCredentialConfigurationMode {
    case settings
    case onboarding
}

private struct AlpacaCredentialConfigurationView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.locale) private var locale
    @State private var keyID = ""
    @State private var secretKey = ""
    @State private var isCurrentCredentialInputVerified = false
    @State private var isConnecting = false
    @FocusState private var focusedField: CredentialField?

    let mode: AlpacaCredentialConfigurationMode

    private var hasCredentialInput: Bool {
        !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTestConnection: Bool {
        hasCredentialInput && !app.credentialsStatus.isTesting
    }

    private var canSaveCredentials: Bool {
        hasCredentialInput &&
        isCurrentCredentialInputVerified &&
        !app.credentialsStatus.isTesting
    }

    private var canConnectCredentials: Bool {
        hasCredentialInput &&
        !app.credentialsStatus.isTesting &&
        !isConnecting
    }

    private var isConnectInProgress: Bool {
        app.credentialsStatus.isTesting || isConnecting
    }

    var body: some View {
        @Bindable var app = app

        if mode == .onboarding {
            loginContent(environment: $app.environment)
        } else {
            settingsContent(environment: $app.environment)
        }
    }

    @ViewBuilder
    private func settingsContent(environment: Binding<TradeEnvironment>) -> some View {
        Section {
            environmentPicker(selection: environment, showsLabel: true)
            .padding(.vertical, 4)
            .onChange(of: app.environment) { _, newValue in
                handleEnvironmentChange(newValue)
            }

            ConnectionStatusRow(
                status: app.credentialsStatus
            )
        } header: {
            Text(L10n.Alpaca.connection)
        }

        if let diagnostics = app.connectionDiagnostics {
            Section {
                ConnectionDiagnosticsView(diagnostics: diagnostics)
            } header: {
                Text(L10n.Alpaca.networkDiagnostics)
            }
        }

        if app.hasCredentials {
            savedCredentialsSection
        } else {
            credentialInputSection
        }
    }

    private func loginContent(environment: Binding<TradeEnvironment>) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            OnboardingHeader()
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 18) {
                environmentPicker(selection: environment, showsLabel: false)
                    .onChange(of: app.environment) { _, newValue in
                        handleEnvironmentChange(newValue)
                    }

                Divider()

                loginTextField(
                    title: L10n.Alpaca.apiKeyID,
                    systemImage: "person.crop.circle",
                    text: $keyID,
                    field: .keyID
                )

                Divider()

                loginSecretField()
            }
            .padding(20)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Button {
                connectCredentials()
            } label: {
                HStack(spacing: 10) {
                    if isConnectInProgress {
                        RotatingConnectionIndicator()
                    }

                    Text(isConnectInProgress ? L10n.Alpaca.testingConnection : L10n.Alpaca.connectAction)
                        .font(AppTypography.rowTitle)
                }
                .foregroundStyle(AppTheme.ColorToken.brandForeground)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(connectButtonBackground, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canConnectCredentials)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.snappy, value: isConnectInProgress)
            .animation(.snappy, value: hasCredentialInput)
            .accessibilityHint(L10n.Alpaca.saveToKeychainHint)
        }
        .frame(maxWidth: 430, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var connectButtonBackground: Color {
        if canConnectCredentials || isConnectInProgress {
            return AppTheme.ColorToken.brand
        }

        return AppTheme.ColorToken.groupedSurface
    }

    private func environmentPicker(selection: Binding<TradeEnvironment>, showsLabel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsLabel {
                Text(L10n.Alpaca.environment)
                    .font(AppTypography.rowMeta)
                    .foregroundStyle(.secondary)
            }

            Picker(L10n.Alpaca.environment, selection: selection) {
                ForEach(TradeEnvironment.allCases) { environment in
                    Text(environment.title).tag(environment)
                }
            }
            .pickerStyle(.segmented)
            .disabled(app.credentialsStatus.isTesting || isConnecting)
        }
    }

    private func loginTextField(
        title: LocalizedStringKey,
        systemImage: String,
        text: Binding<String>,
        field: CredentialField
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.icon)
                .frame(width: 28)

            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .focused($focusedField, equals: field)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .secretKey
                }
                .disabled(app.credentialsStatus.isTesting || isConnecting)
                .onChange(of: keyID) { _, _ in
                    invalidateCurrentCredentialInput()
                }
        }
        .frame(minHeight: 36)
    }

    private func loginSecretField() -> some View {
        HStack(spacing: 12) {
            Image(systemName: AppIcon.Alpaca.credential)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.icon)
                .frame(width: 28)

            SecureField(L10n.Alpaca.apiSecretKey, text: $secretKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .focused($focusedField, equals: .secretKey)
                .submitLabel(.go)
                .onSubmit {
                    connectCredentials()
                }
                .disabled(app.credentialsStatus.isTesting || isConnecting)
                .onChange(of: secretKey) { _, _ in
                    invalidateCurrentCredentialInput()
                }
        }
        .frame(minHeight: 36)
    }

    private func saveCredentials() {
        guard canSaveCredentials else {
            return
        }

        focusedField = nil
        Task {
            let didSave = await app.saveCredentials(keyID: keyID, secretKey: secretKey)
            if didSave {
                keyID = ""
                secretKey = ""
                isCurrentCredentialInputVerified = false
                toastCenter.show(connectedToastMessage(environment: app.environment))
            } else if let message = app.credentialMessage {
                toastCenter.show(message, systemImage: "exclamationmark.circle.fill", tone: .error)
            }
        }
    }

    private func connectCredentials() {
        guard canConnectCredentials else {
            return
        }

        focusedField = nil
        isConnecting = true
        Task {
            defer { isConnecting = false }

            switch await app.connectAndSaveCredentials(keyID: keyID, secretKey: secretKey) {
            case .success(let environment):
                keyID = ""
                secretKey = ""
                isCurrentCredentialInputVerified = false
                toastCenter.show(connectedToastMessage(environment: environment))
            case .failure(let message):
                toastCenter.show(message, systemImage: "exclamationmark.circle.fill", tone: .error)
            case .cancelled:
                break
            }
        }
    }

    private func testConnection() {
        guard canTestConnection else {
            return
        }

        focusedField = nil
        Task {
            isCurrentCredentialInputVerified = await app.testConnection(
                keyID: keyID,
                secretKey: secretKey
            )
        }
    }

    private func testSavedConnection() {
        Task {
            await app.testSavedConnection()
        }
    }

    private func removeCredentials() {
        Task {
            await app.clearCredentials()
            keyID = ""
            secretKey = ""
            isCurrentCredentialInputVerified = false
        }
    }

    private func invalidateCurrentCredentialInput() {
        isCurrentCredentialInputVerified = false
        app.invalidateCredentialInput()
    }

    private func handleEnvironmentChange(_ newValue: TradeEnvironment) {
        keyID = ""
        secretKey = ""
        isCurrentCredentialInputVerified = false
        isConnecting = false
        Task {
            await app.updateEnvironment(newValue)
        }
    }

    private func connectedToastMessage(environment: TradeEnvironment) -> String {
        L10n.Credentials.connected(to: environment.titleText(locale: locale), locale: locale)
    }

    private var savedCredentialsSection: some View {
        Section {
            SavedCredentialRow(
                environmentTitle: app.environment.titleText(locale: locale),
                maskedKeyID: app.maskedCredentialKeyID
            )

            Button {
                testSavedConnection()
            } label: {
                if app.credentialsStatus.isTesting {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.Alpaca.testingConnection)
                    }
                } else {
                    Label(L10n.Alpaca.testSavedConnection, systemImage: AppIcon.Alpaca.testConnection)
                }
            }
            .disabled(app.credentialsStatus.isTesting)
            .accessibilityHint(L10n.Alpaca.testConnectionHint)

            Button(role: .destructive) {
                removeCredentials()
            } label: {
                Label(L10n.Alpaca.removeCredentials, systemImage: AppIcon.Alpaca.removeCredentials)
            }
            .disabled(app.credentialsStatus.isTesting)
            .accessibilityHint(L10n.Alpaca.removeCredentialsHint)
        } header: {
            Text(L10n.Alpaca.savedCredentials)
        } footer: {
            Text(mode == .onboarding ? L10n.Alpaca.onboardingSavedFooter : L10n.Alpaca.savedCredentialsFooter)
        }
    }

    private var credentialInputSection: some View {
        Section {
            TextField(L10n.Alpaca.apiKeyID, text: $keyID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .focused($focusedField, equals: .keyID)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .secretKey
                }
                .disabled(app.credentialsStatus.isTesting)
                .onChange(of: keyID) { _, _ in
                    invalidateCurrentCredentialInput()
                }

            SecureField(L10n.Alpaca.apiSecretKey, text: $secretKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .focused($focusedField, equals: .secretKey)
                .submitLabel(.done)
                .onSubmit {
                    testConnection()
                }
                .disabled(app.credentialsStatus.isTesting)
                .onChange(of: secretKey) { _, _ in
                    invalidateCurrentCredentialInput()
                }

            Button {
                testConnection()
            } label: {
                if app.credentialsStatus.isTesting {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.Alpaca.testingConnection)
                    }
                } else {
                    Label(L10n.Alpaca.testConnection, systemImage: AppIcon.Alpaca.testConnection)
                }
            }
            .disabled(!canTestConnection)
            .accessibilityHint(L10n.Alpaca.testConnectionHint)

            Button {
                saveCredentials()
            } label: {
                Label(L10n.Alpaca.saveToKeychain, systemImage: AppIcon.Alpaca.credential)
            }
            .disabled(!canSaveCredentials)
            .accessibilityHint(L10n.Alpaca.saveToKeychainHint)
        } header: {
            Text(L10n.Alpaca.apiKey)
        } footer: {
            Text(isCurrentCredentialInputVerified ? L10n.Alpaca.apiKeyVerifiedFooter : L10n.Alpaca.apiKeyFooter)
        }
    }
}

private enum CredentialField: Hashable {
    case keyID
    case secretKey
}

private struct RotatingConnectionIndicator: View {
    @State private var isRotating = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.headline.weight(.semibold))
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(.linear(duration: 0.85).repeatForever(autoreverses: false), value: isRotating)
            .onAppear {
                isRotating = true
            }
            .onDisappear {
                isRotating = false
            }
    }
}

private struct AlpacaLastMessageSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let message = app.credentialMessage {
            Section {
                Text(message)
                    .font(AppTypography.detail)
                    .foregroundStyle(.secondary)
                    .lineSpacing(AppTypography.secondaryLineSpacing)
            } header: {
                Text(L10n.Alpaca.lastMessage)
            }
        }
    }
}

private struct SavedCredentialRow: View {
    let environmentTitle: String
    let maskedKeyID: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Alpaca.savedInKeychain)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(environmentTitle)
                    if let maskedKeyID {
                        Text(maskedKeyID)
                            .monospaced()
                    }
                }
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)

                Text(L10n.Alpaca.secretSavedDescription)
                    .font(AppTypography.detail)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: AppIcon.Alpaca.credential)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.icon)
                .frame(width: 30)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct ConnectionStatusRow: View {
    @Environment(\.locale) private var locale

    let status: CredentialsStatus

    private var systemImage: String {
        switch status {
        case .connected, .verified:
            AppIcon.Alpaca.connected
        case .failed:
            AppIcon.Alpaca.failed
        case .untested:
            AppIcon.Alpaca.credentialMissing
        case .testing:
            AppIcon.Alpaca.testing
        case .missing:
            AppIcon.Alpaca.missing
        }
    }

    private var tint: Color {
        switch status {
        case .connected, .verified:
            AppTheme.ColorToken.positive
        case .failed:
            AppTheme.ColorToken.negative
        case .testing:
            AppTheme.ColorToken.brand
        case .missing, .untested:
            AppTheme.ColorToken.warning
        }
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title(locale: locale))
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(tint)
                Text(status.detail(locale: locale))
                    .font(AppTypography.detail)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            if status.isTesting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 30)
            } else {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct ConnectionDiagnosticsView: View {
    let diagnostics: ConnectionDiagnostics

    private var resultTint: Color {
        diagnostics.succeeded ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    var body: some View {
        ConnectionDiagnosticRow(L10n.Alpaca.endpoint) {
            Text(diagnostics.endpoint)
                .font(.footnote.monospaced())
                .lineLimit(2)
                .minimumScaleFactor(0.86)
        }

        ConnectionDiagnosticRow(L10n.Alpaca.result) {
            Text(diagnostics.succeeded ? L10n.Alpaca.success : L10n.Alpaca.failed)
                .font(AppTypography.rowMeta)
                .foregroundStyle(resultTint)
        }

        ConnectionDiagnosticRow(L10n.Alpaca.latency) {
            Text(AppFormatter.latency(milliseconds: diagnostics.latencyMilliseconds))
                .font(AppTypography.rowMeta)
        }

        ConnectionDiagnosticRow(L10n.Alpaca.httpStatus) {
            Text(AppFormatter.httpStatus(diagnostics.httpStatusCode))
                .font(AppTypography.rowMeta)
        }

        ConnectionDiagnosticRow(L10n.Alpaca.checkedAt) {
            Text(AppFormatter.time(diagnostics.checkedAt))
                .font(AppTypography.rowMeta)
        }
    }
}

private struct ConnectionDiagnosticRow<Value: View>: View {
    let title: LocalizedStringKey
    private let value: Value

    init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(AppTypography.rowMeta)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            value
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        AlpacaView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
