#if DEBUG
import SwiftUI
import UIKit

/// Debug-only gallery that renders the exact notification payloads produced by
/// `NotificationPresentation` as iOS Lock Screen banners, with one-tap local
/// delivery for on-device verification.
struct NotificationPreviewView: View {
    @Environment(AppModel.self) private var app
    @State private var deliveredID: String?

    private var locale: Locale { app.appLanguage.locale }
    private var isChinese: Bool { locale.identifier.hasPrefix("zh") }

    private var samples: [(section: String, payload: NotificationPayload)] {
        [
            (
                "Order · filled",
                NotificationPresentation.tradeEvent(
                    makeTradeEvent(
                        id: "preview-fill",
                        event: "fill",
                        symbol: "NVDA",
                        side: "sell",
                        type: "limit",
                        quantity: "25",
                        filledQuantity: "25",
                        price: "182.34"
                    ),
                    locale: locale
                )
            ),
            (
                "Order · partial fill",
                NotificationPresentation.tradeEvent(
                    makeTradeEvent(
                        id: "preview-partial",
                        event: "partial_fill",
                        symbol: "AAPL",
                        side: "buy",
                        type: "limit",
                        quantity: "10",
                        filledQuantity: "6",
                        price: "230.98"
                    ),
                    locale: locale
                )
            ),
            (
                "Order · rejected",
                NotificationPresentation.tradeEvent(
                    makeTradeEvent(
                        id: "preview-rejected",
                        event: "rejected",
                        symbol: "TSLA",
                        side: "buy",
                        type: "limit",
                        quantity: "8",
                        filledQuantity: "0",
                        price: nil,
                        limitPrice: "240.00"
                    ),
                    locale: locale
                )
            ),
            (
                "Order · submitted",
                NotificationPresentation.orderSubmitted(
                    order: makeOrder(
                        id: "preview-submitted",
                        symbol: "AAPL",
                        side: "buy",
                        type: "limit",
                        quantity: "10",
                        filledQuantity: "0",
                        limitPrice: "231.00",
                        status: "new"
                    ),
                    locale: locale
                )
            ),
            (
                "Account · dividend",
                NotificationPresentation.accountActivity(
                    AlpacaActivityEvent(
                        accountID: "acct-1",
                        at: nil,
                        eventID: "preview-div",
                        activityType: "DIV",
                        activitySubtype: "cash_dividend",
                        refID: "ref-div",
                        status: "executed",
                        executedAt: nil,
                        settleDate: nil,
                        quantity: nil,
                        price: nil,
                        netAmount: "12.40",
                        currency: "USD",
                        swapRate: nil,
                        swapFeeBps: nil,
                        previousID: nil,
                        details: ["symbol": .string("AAPL")]
                    ),
                    locale: locale
                )
            ),
            (
                "Account · transfer",
                NotificationPresentation.accountActivity(
                    AlpacaActivityEvent(
                        accountID: "acct-1",
                        at: nil,
                        eventID: "preview-csd",
                        activityType: "CSD",
                        activitySubtype: nil,
                        refID: "ref-csd",
                        status: "executed",
                        executedAt: nil,
                        settleDate: nil,
                        quantity: nil,
                        price: nil,
                        netAmount: "2500.00",
                        currency: "USD",
                        swapRate: nil,
                        swapFeeBps: nil,
                        previousID: nil,
                        details: [:]
                    ),
                    locale: locale
                )
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(samples, id: \.payload.requestIdentifier) { sample in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(sample.section)
                                .font(AppTypography.sectionHeader)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                Task {
                                    await app.services.appNotifier.deliver(sample.payload, locale: locale)
                                    deliveredID = sample.payload.requestIdentifier
                                }
                            } label: {
                                let isSent = deliveredID == sample.payload.requestIdentifier
                                Text(
                                    isSent
                                        ? (isChinese ? "已发送" : "Sent")
                                        : (isChinese ? "测试" : "Test")
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSent ? Color.green : Color.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        NotificationBannerPreviewCard(
                            payload: sample.payload,
                            timestampLabel: isChinese ? "刚刚" : "now"
                        )
                    }
                }

                Text(
                    isChinese
                        ? "中间态（已受理 / 待撤单等）由实时活动承接，通知仅在关键节点触达，减少打扰。"
                        : "Intermediate states (accepted, pending cancel) stay on Live Activities; notifications fire only on key milestones."
                )
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationTitle(isChinese ? "通知样式预览" : "Notification Preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func makeOrder(
        id: String,
        symbol: String,
        side: String,
        type: String,
        quantity: String,
        filledQuantity: String,
        limitPrice: String?,
        status: String
    ) -> AlpacaOrder {
        AlpacaOrder(
            id: id,
            clientOrderID: nil,
            createdAt: nil,
            updatedAt: nil,
            submittedAt: nil,
            filledAt: nil,
            expiredAt: nil,
            canceledAt: nil,
            failedAt: nil,
            replacedAt: nil,
            replacedBy: nil,
            replaces: nil,
            assetID: nil,
            symbol: symbol,
            assetClass: nil,
            quantity: quantity,
            filledQuantity: filledQuantity,
            filledAveragePrice: nil,
            notional: nil,
            orderClass: nil,
            orderType: type,
            side: side,
            type: type,
            positionIntent: nil,
            timeInForce: nil,
            limitPrice: limitPrice,
            stopPrice: nil,
            status: status,
            extendedHours: nil,
            legs: nil,
            trailPercent: nil,
            trailPrice: nil,
            highWaterMark: nil,
            subtag: nil,
            source: nil,
            expiresAt: nil
        )
    }

    private func makeTradeEvent(
        id: String,
        event: String,
        symbol: String,
        side: String,
        type: String,
        quantity: String,
        filledQuantity: String,
        price: String?,
        limitPrice: String? = nil
    ) -> AlpacaTradeEvent {
        AlpacaTradeEvent(
            eventID: id,
            event: event,
            order: makeOrder(
                id: "order-\(id)",
                symbol: symbol,
                side: side,
                type: type,
                quantity: quantity,
                filledQuantity: filledQuantity,
                limitPrice: limitPrice,
                status: event
            ),
            price: price,
            quantity: filledQuantity
        )
    }
}

private struct NotificationBannerPreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let payload: NotificationPayload
    let timestampLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            appIconView

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(payload.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(timestampLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if !payload.subtitle.isEmpty {
                    Text(payload.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                if !payload.body.isEmpty {
                    Text(payload.body)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardSurface)
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.06),
            radius: 10,
            x: 0,
            y: 3
        )
    }

    @ViewBuilder
    private var appIconView: some View {
        if let appIcon = Bundle.main.previewAppIconImage {
            Image(uiImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            // `AlpacaTabIcon` is an even-odd filled square with the alpaca knocked out:
            // tinting it brand yellow over a crisp dark/white backing reproduces Vicu's App Icon cleanly.
            ZStack {
                Color.white
                Image("AlpacaTabIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(ActivityDesign.brand)
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? AnyShapeStyle(Color(white: 0.14).opacity(0.95))
                    : AnyShapeStyle(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.09)
                            : Color.black.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
    }
}

private extension Bundle {
    var previewAppIconImage: UIImage? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else {
            return nil
        }
        return UIImage(named: name)
    }
}
#endif
