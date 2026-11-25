import SwiftUI

struct HomeAICopilotSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: PortfolioIntelligenceSnapshot
    let initialPrompt: String?
    let onSelectDestination: (PortfolioAIActionDestination) -> Void

    @State private var messages: [PortfolioCopilotMessage] = []
    @State private var draftQuery = ""
    @State private var isThinking = false
    @State private var hasSubmittedInitialPrompt = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextBanner

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if messages.isEmpty {
                                emptyStatePrompts
                            } else {
                                ForEach(messages) { message in
                                    CopilotMessageBubble(
                                        message: message,
                                        onTapDestination: onSelectDestination
                                    )
                                    .id(message.id)
                                }

                                if isThinking {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(L10n.HomeAI.copilotAnalyzing)
                                            .font(AppTypography.detail)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.ColorToken.groupedSurface, in: Capsule())
                                    .id("thinking-indicator")
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                        .padding(.vertical, 16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastID = messages.last?.id {
                            withAnimation(.snappy) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }

                composerBar
            }
            .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
            .navigationTitle(L10n.HomeAI.copilotTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppSheetCloseButton()
                }
            }
            .task {
                guard !hasSubmittedInitialPrompt else { return }
                hasSubmittedInitialPrompt = true
                if let initialPrompt, !initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await submit(query: initialPrompt)
                }
            }
        }
    }

    private var contextBanner: some View {
        HStack(spacing: 8) {
            Text(
                AppFormatter.compactMoney(
                    snapshot.allocation.netEquity,
                    currencyCode: snapshot.allocation.currencyCode
                )
            )
            .font(AppTypography.detail.weight(.semibold).monospacedDigit())
            .foregroundStyle(.primary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(
                AppFormatter.signedCompactMoney(
                    snapshot.attribution.totalUnrealizedPL,
                    currencyCode: snapshot.allocation.currencyCode
                )
            )
            .font(AppTypography.caption.monospacedDigit())
            .foregroundStyle(
                snapshot.attribution.totalUnrealizedPL >= 0
                    ? AppTheme.ColorToken.positive
                    : AppTheme.ColorToken.negative
            )

            Spacer(minLength: 6)

            Text(L10n.Account.cash)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)

            Text(
                AppFormatter.compactMoney(
                    snapshot.allocation.cashBalance,
                    currencyCode: snapshot.allocation.currencyCode
                )
            )
            .font(AppTypography.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.vertical, 10)
        .background(AppTheme.ColorToken.groupedSurface)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    private var emptyStatePrompts: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.HomeAI.copilotWelcomeTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(L10n.HomeAI.copilotWelcomeSubtitle)
                    .font(AppTypography.detail)
                    .foregroundStyle(.secondary)
                    .lineSpacing(AppTypography.secondaryLineSpacing)
            }
            .padding(.top, 4)

            VStack(spacing: 10) {
                ForEach(snapshot.suggestedPrompts) { item in
                    Button {
                        Task {
                            await submit(query: item.prompt)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? AppTheme.ColorToken.brand : AppTheme.ColorToken.brandAlt)
                                .frame(width: 26)

                            Text(item.prompt)
                                .font(AppTypography.detail.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 8)

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            AppTheme.ColorToken.groupedSurface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var composerBar: some View {
        HStack(spacing: 10) {
            TextField(L10n.HomeAI.askPlaceholder, text: $draftQuery, axis: .vertical)
                .font(AppTypography.rowTitle)
                .lineLimit(1...3)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    submitCurrentDraft()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.ColorToken.groupedSurface, in: Capsule())

            Button {
                submitCurrentDraft()
            } label: {
                Image(systemName: AppIcon.Intelligence.send)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(canSend ? AppTheme.ColorToken.brand : Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(L10n.Common.submit)
        }
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        !isThinking && !draftQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitCurrentDraft() {
        let query = draftQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isThinking else { return }
        draftQuery = ""
        isInputFocused = false
        Task {
            await submit(query: query)
        }
    }

    private func submit(query: String) async {
        let userMessage = PortfolioCopilotMessage(role: .user, text: query)
        messages.append(userMessage)
        isThinking = true
        defer { isThinking = false }

        let reply = await app.askPortfolioCopilot(query, snapshot: snapshot)
        messages.append(reply)
    }
}

private struct CopilotMessageBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: PortfolioCopilotMessage
    let onTapDestination: (PortfolioAIActionDestination) -> Void

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 44)
                Text(message.text)
                    .font(AppTypography.detail.weight(.medium))
                    .foregroundStyle(AppTheme.ColorToken.brandForeground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.ColorToken.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: AppIcon.Intelligence.copilot)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? AppTheme.ColorToken.brand : AppTheme.ColorToken.brandAlt)

                    Text(L10n.HomeAI.copilotTitle)
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .font(AppTypography.detail)
                    .foregroundStyle(.primary)
                    .lineSpacing(AppTypography.secondaryLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)

                if !message.highlights.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(message.highlights) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Text(item.value)
                                    .font(AppTypography.detail.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(metricTint(item.tone))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemFill).opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }

                if let ctaTitle = message.ctaTitle, let destination = message.destination {
                    Button {
                        onTapDestination(destination)
                    } label: {
                        HStack(spacing: 6) {
                            Text(ctaTitle)
                                .font(AppTypography.chip)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.ColorToken.groupedSurface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    private func metricTint(_ tone: PortfolioTagTone) -> Color {
        switch tone {
        case .neutral: .primary
        case .positive: AppTheme.ColorToken.positive
        case .negative: AppTheme.ColorToken.negative
        case .warning: AppTheme.ColorToken.warning
        case .brand: colorScheme == .dark ? AppTheme.ColorToken.brand : AppTheme.ColorToken.brandAlt
        }
    }
}
