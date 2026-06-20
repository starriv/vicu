import Foundation
import SwiftUI

enum AppLocale {
    static let defaultIdentifier = "en"
    static let simplifiedChineseIdentifier = "zh-Hans"
    static let supportedIdentifiers = [defaultIdentifier, simplifiedChineseIdentifier]

    static var current: Locale {
        resolvedLocale(for: .current)
    }

    static var system: Locale {
        let preferences = Locale.preferredLanguages.isEmpty
            ? [Locale.autoupdatingCurrent.identifier]
            : Locale.preferredLanguages

        return Locale(identifier: resolvedIdentifier(forPreferences: preferences))
    }

    static func resolvedLocale(for locale: Locale) -> Locale {
        Locale(identifier: resolvedIdentifier(for: locale))
    }

    static func resolvedIdentifier(for locale: Locale) -> String {
        resolvedIdentifier(forPreferences: localePreferences(for: locale))
    }

    static func resolvedIdentifier(forPreferences preferences: [String]) -> String {
        let normalizedPreferences = preferences.flatMap(localePreferences(forIdentifier:))
        if let preferred = Bundle.preferredLocalizations(
            from: supportedIdentifiers,
            forPreferences: normalizedPreferences
        ).first {
            return preferred
        }

        return defaultIdentifier
    }

    static func localizationCandidates(for locale: Locale) -> [String] {
        var candidates = localePreferences(for: locale)
        append(resolvedIdentifier(for: locale), to: &candidates)
        append(defaultIdentifier, to: &candidates)
        return candidates
    }

    static func acceptLanguageHeader(for locale: Locale? = nil) -> String {
        let identifier = locale.map(resolvedIdentifier(for:)) ?? resolvedIdentifier(forPreferences: Locale.preferredLanguages)
        let fallback = identifier == defaultIdentifier ? simplifiedChineseIdentifier : defaultIdentifier
        return "\(identifier), \(fallback);q=0.8"
    }

    private static func localePreferences(for locale: Locale) -> [String] {
        localePreferences(forIdentifier: locale.identifier)
    }

    private static func localePreferences(forIdentifier identifier: String) -> [String] {
        let normalizedIdentifier = normalized(identifier)
        var preferences: [String] = []
        append(normalizedIdentifier, to: &preferences)

        let locale = Locale(identifier: normalizedIdentifier)
        append(locale.language.languageCode?.identifier, to: &preferences)

        return preferences
    }

    private static func normalized(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "@", maxSplits: 1)
            .first
            .map(String.init) ?? identifier
    }

    private static func append(_ candidate: String?, to candidates: inout [String]) {
        guard let candidate, !candidate.isEmpty, !candidates.contains(candidate) else {
            return
        }

        candidates.append(candidate)
    }
}

enum L10n {
    static func string(_ key: String, locale: Locale = .current) -> String {
        localizedBundle(for: locale).localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, locale: Locale = .current, _ arguments: CVarArg...) -> String {
        let resolvedLocale = AppLocale.resolvedLocale(for: locale)
        return String(format: string(key, locale: resolvedLocale), locale: resolvedLocale, arguments: arguments)
    }

    private static func localizedBundle(for locale: Locale) -> Bundle {
        for candidate in AppLocale.localizationCandidates(for: locale) {
            guard let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                continue
            }

            return bundle
        }

        return .main
    }

    enum Common {
        static var refresh: LocalizedStringKey { "common.refresh" }
        static var retry: LocalizedStringKey { "common.retry" }
        static var back: LocalizedStringKey { "common.back" }
        static var clear: LocalizedStringKey { "common.clear" }
        static var close: LocalizedStringKey { "common.close" }
        static var submit: LocalizedStringKey { "common.submit" }
        static var cancel: LocalizedStringKey { "common.cancel" }
        static var share: LocalizedStringKey { "common.share" }
        static var copy: LocalizedStringKey { "common.copy" }
        static var noData: LocalizedStringKey { "common.no_data" }
        static var loadingMore: LocalizedStringKey { "common.loading_more" }
        static var copyToClipboardHint: LocalizedStringKey { "common.copy_to_clipboard_hint" }
        static var noResponseBody: String { L10n.string("common.no_response_body") }
        static func copiedToClipboard(locale: Locale) -> String { L10n.string("common.copied_to_clipboard", locale: locale) }
        static func submitText(locale: Locale) -> String { L10n.string("common.submit", locale: locale) }
        static func cancelText(locale: Locale) -> String { L10n.string("common.cancel", locale: locale) }
    }

    enum Credentials {
        static func notConnected(locale: Locale = .current) -> String {
            L10n.string("credentials.not_connected", locale: locale)
        }

        static func notConnectedDescription(locale: Locale = .current) -> String {
            L10n.string("credentials.not_connected_description", locale: locale)
        }

        static func connectedDescription(locale: Locale = .current) -> String {
            L10n.string("credentials.connected_description", locale: locale)
        }

        static func testingDescription(locale: Locale = .current) -> String {
            L10n.string("credentials.testing_description", locale: locale)
        }

        static func verifiedDescription(locale: Locale = .current) -> String {
            L10n.string("credentials.verified_description", locale: locale)
        }

        static func untestedDescription(locale: Locale = .current) -> String {
            L10n.string("credentials.untested_description", locale: locale)
        }

        static func apiKeyRequired(locale: Locale = .current) -> String {
            L10n.string("credentials.api_key_required", locale: locale)
        }

        static func testRequired(locale: Locale = .current) -> String {
            L10n.string("credentials.test_required", locale: locale)
        }

        static func connected(to environment: String, locale: Locale = .current) -> String {
            L10n.format("credentials.connected_format", locale: locale, environment)
        }

        static func failed(_ environment: String, locale: Locale = .current) -> String {
            L10n.format("credentials.failed_format", locale: locale, environment)
        }

        static func testing(_ environment: String, locale: Locale = .current) -> String {
            L10n.format("credentials.testing_format", locale: locale, environment)
        }

        static func untested(_ environment: String, locale: Locale = .current) -> String {
            L10n.format("credentials.untested_format", locale: locale, environment)
        }

        static func verified(_ environment: String, locale: Locale = .current) -> String {
            L10n.format("credentials.verified_format", locale: locale, environment)
        }
    }

    enum Portfolio {
        static var title: LocalizedStringKey { "portfolio.title" }
        static var yourPortfolio: LocalizedStringKey { "portfolio.your_portfolio" }
        static var refreshAccessibility: LocalizedStringKey { "portfolio.refresh_accessibility" }
        static var chartAccessibility: LocalizedStringKey { "portfolio.chart_accessibility" }
    }

    enum PortfolioEmpty {
        static var noHistory: LocalizedStringKey { "portfolio.empty.no_history" }
        static var connectAlpaca: LocalizedStringKey { "portfolio.empty.connect_alpaca" }
        static var historyDescription: LocalizedStringKey { "portfolio.empty.history_description" }
        static var connectDescription: LocalizedStringKey { "portfolio.empty.connect_description" }
        static var connectAction: LocalizedStringKey { "portfolio.empty.connect_action" }
    }

    enum PortfolioRange {
        static func accessibility(title: String, locale: Locale) -> String {
            L10n.format("portfolio.range.accessibility_format", locale: locale, title)
        }
    }

    enum Account {
        static var sectionTitle: LocalizedStringKey { "account.section_title" }
        static var buyingPower: LocalizedStringKey { "account.buying_power" }
        static var cash: LocalizedStringKey { "account.cash" }
        static var longMarketValue: LocalizedStringKey { "account.long_market_value" }
        static var shortMarketValue: LocalizedStringKey { "account.short_market_value" }
    }

    enum AccountDetail {
        static var title: LocalizedStringKey { "account_detail.title" }
        static var loading: LocalizedStringKey { "account_detail.loading" }
        static var paperBannerTitle: LocalizedStringKey { "account_detail.paper_banner.title" }
        static var paperBannerMessage: LocalizedStringKey { "account_detail.paper_banner.message" }
        static var overview: LocalizedStringKey { "account_detail.overview" }
        static var accountID: LocalizedStringKey { "account_detail.account_id" }
        static var accountNumber: LocalizedStringKey { "account_detail.account_number" }
        static var status: LocalizedStringKey { "account_detail.status" }
        static var cryptoStatus: LocalizedStringKey { "account_detail.crypto_status" }
        static var currency: LocalizedStringKey { "account_detail.currency" }
        static var createdAt: LocalizedStringKey { "account_detail.created_at" }
        static var balanceAsOf: LocalizedStringKey { "account_detail.balance_as_of" }
        static var buyingPowerSection: LocalizedStringKey { "account_detail.buying_power_section" }
        static var regtBuyingPower: LocalizedStringKey { "account_detail.regt_buying_power" }
        static var daytradingBuyingPower: LocalizedStringKey { "account_detail.daytrading_buying_power" }
        static var effectiveBuyingPower: LocalizedStringKey { "account_detail.effective_buying_power" }
        static var nonMarginableBuyingPower: LocalizedStringKey { "account_detail.non_marginable_buying_power" }
        static var optionsBuyingPower: LocalizedStringKey { "account_detail.options_buying_power" }
        static var bodDtbp: LocalizedStringKey { "account_detail.bod_dtbp" }
        static var balances: LocalizedStringKey { "account_detail.balances" }
        static var portfolioValue: LocalizedStringKey { "account_detail.portfolio_value" }
        static var equity: LocalizedStringKey { "account_detail.equity" }
        static var lastEquity: LocalizedStringKey { "account_detail.last_equity" }
        static var positionMarketValue: LocalizedStringKey { "account_detail.position_market_value" }
        static var margin: LocalizedStringKey { "account_detail.margin" }
        static var multiplier: LocalizedStringKey { "account_detail.multiplier" }
        static var initialMargin: LocalizedStringKey { "account_detail.initial_margin" }
        static var maintenanceMargin: LocalizedStringKey { "account_detail.maintenance_margin" }
        static var lastMaintenanceMargin: LocalizedStringKey { "account_detail.last_maintenance_margin" }
        static var sma: LocalizedStringKey { "account_detail.sma" }
        static var trading: LocalizedStringKey { "account_detail.trading" }
        static var patternDayTrader: LocalizedStringKey { "account_detail.pattern_day_trader" }
        static var tradingBlocked: LocalizedStringKey { "account_detail.trading_blocked" }
        static var transfersBlocked: LocalizedStringKey { "account_detail.transfers_blocked" }
        static var accountBlocked: LocalizedStringKey { "account_detail.account_blocked" }
        static var tradeSuspendedByUser: LocalizedStringKey { "account_detail.trade_suspended_by_user" }
        static var shortingEnabled: LocalizedStringKey { "account_detail.shorting_enabled" }
        static var optionsApprovedLevel: LocalizedStringKey { "account_detail.options_approved_level" }
        static var optionsTradingLevel: LocalizedStringKey { "account_detail.options_trading_level" }
        static var cryptoTier: LocalizedStringKey { "account_detail.crypto_tier" }
        static var daytradeCount: LocalizedStringKey { "account_detail.daytrade_count" }
        static var feesAdjustments: LocalizedStringKey { "account_detail.fees_adjustments" }
        static var accruedFees: LocalizedStringKey { "account_detail.accrued_fees" }
        static var pendingRegTAFFees: LocalizedStringKey { "account_detail.pending_reg_taf_fees" }
        static var intradayAdjustments: LocalizedStringKey { "account_detail.intraday_adjustments" }
        static var yes: String { L10n.string("account_detail.yes") }
        static var no: String { L10n.string("account_detail.no") }
    }

    enum AccountActivity {
        static var title: LocalizedStringKey { "account_activity.title" }
        static var entrySubtitle: LocalizedStringKey { "account_activity.entry_subtitle" }
        static var entryHint: LocalizedStringKey { "account_activity.entry_hint" }
        static var loading: LocalizedStringKey { "account_activity.loading" }
        static var recentSection: LocalizedStringKey { "account_activity.recent_section" }
        static var emptyTitle: LocalizedStringKey { "account_activity.empty_title" }
        static var emptyDescription: LocalizedStringKey { "account_activity.empty_description" }
        static var errorTitle: LocalizedStringKey { "account_activity.error_title" }

        static func tradeFill(locale: Locale = .current) -> String {
            L10n.string("account_activity.kind.trade_fill", locale: locale)
        }

        static func transfer(locale: Locale = .current) -> String {
            L10n.string("account_activity.kind.transfer", locale: locale)
        }

        static func dividend(locale: Locale = .current) -> String {
            L10n.string("account_activity.kind.dividend", locale: locale)
        }

        static func fee(locale: Locale = .current) -> String {
            L10n.string("account_activity.kind.fee", locale: locale)
        }

        static func optionEvent(locale: Locale = .current) -> String {
            L10n.string("account_activity.kind.option_event", locale: locale)
        }

        static func corporateAction(locale: Locale = .current) -> String {
            L10n.string("account_activity.kind.corporate_action", locale: locale)
        }
    }

    enum ActivityNotification {
        static func title(locale: Locale = .current) -> String {
            L10n.string("activity_notification.title", locale: locale)
        }

        static func genericActivity(locale: Locale = .current) -> String {
            L10n.string("activity_notification.kind.generic", locale: locale)
        }

        static func bodySubjectAmount(kind: String, subject: String, amount: String, locale: Locale) -> String {
            L10n.format("activity_notification.body.subject_amount_format", locale: locale, kind, subject, amount)
        }

        static func bodySubject(kind: String, subject: String, locale: Locale) -> String {
            L10n.format("activity_notification.body.subject_format", locale: locale, kind, subject)
        }

        static func bodyAmount(kind: String, amount: String, locale: Locale) -> String {
            L10n.format("activity_notification.body.amount_format", locale: locale, kind, amount)
        }

        static func bodyGeneric(kind: String, locale: Locale) -> String {
            L10n.format("activity_notification.body.generic_format", locale: locale, kind)
        }

        static func orderSubmittedTitle(locale: Locale) -> String {
            L10n.string("activity_notification.order_submitted.title", locale: locale)
        }

        static func orderSubmittedQuantitySize(_ quantity: String, locale: Locale) -> String {
            L10n.format("activity_notification.order_submitted.quantity_size_format", locale: locale, quantity)
        }

        static func orderSubmittedBody(side: String, size: String, symbol: String, type: String, locale: Locale) -> String {
            L10n.format("activity_notification.order_submitted.body_format", locale: locale, side, size, symbol, type)
        }

        static func tradeEventTitle(status: String, locale: Locale) -> String {
            L10n.format("activity_notification.trade_event.title_format", locale: locale, status)
        }

        static func tradeEventBody(
            side: String,
            size: String,
            symbol: String,
            type: String,
            priceSuffix: String,
            locale: Locale
        ) -> String {
            L10n.format(
                "activity_notification.trade_event.body_format",
                locale: locale,
                side,
                size,
                symbol,
                type,
                priceSuffix
            )
        }

        static func tradeEventPriceSuffix(_ price: String, locale: Locale) -> String {
            L10n.format("activity_notification.trade_event.price_suffix_format", locale: locale, price)
        }

        static func tradeEventStatus(_ key: String, locale: Locale) -> String {
            L10n.string("activity_notification.trade_event.status.\(key)", locale: locale)
        }
    }

    enum Positions {
        static var title: LocalizedStringKey { "positions.title" }
        static var share: LocalizedStringKey { "positions.share" }
        static var loading: LocalizedStringKey { "positions.loading" }
        static var sectionTitle: LocalizedStringKey { "positions.section_title" }
        static var emptyTitle: LocalizedStringKey { "positions.empty.title" }
        static var emptyDescription: LocalizedStringKey { "positions.empty.description" }
        static var overview: LocalizedStringKey { "positions.overview" }
        static var totalMarketValue: LocalizedStringKey { "positions.total_market_value" }
        static var totalUnrealizedPL: LocalizedStringKey { "positions.total_unrealized_pl" }
        static var totalIntradayPL: LocalizedStringKey { "positions.total_intraday_pl" }
        static var quantityPrefix: LocalizedStringKey { "positions.quantity_prefix" }
        static var profitLossPrefix: LocalizedStringKey { "positions.profit_loss_prefix" }

        static func categoryAccessibility(title: String, count: Int, locale: Locale = .current) -> String {
            L10n.format("positions.category.accessibility_format", locale: locale, title, count)
        }

        static func viewAllAccessibility(count: Int, locale: Locale = .current) -> String {
            L10n.format("positions.view_all.accessibility_format", locale: locale, count)
        }
    }

    enum PositionsShare {
        static var title: LocalizedStringKey { "positions_share.title" }
        static var previewAccessibility: LocalizedStringKey { "positions_share.preview_accessibility" }
        static func sharePreviewTitle(count: Int, locale: Locale) -> String {
            L10n.format("positions_share.preview_title_format", locale: locale, count)
        }
        static func portfolioSnapshot(locale: Locale) -> String { L10n.string("positions_share.portfolio_snapshot", locale: locale) }
        static func allocation(locale: Locale) -> String { L10n.string("positions_share.allocation", locale: locale) }
        static func holdings(locale: Locale) -> String { L10n.string("positions_share.holdings", locale: locale) }
        static func assetCode(locale: Locale) -> String { L10n.string("positions_share.asset_code", locale: locale) }
        static func entryPrice(locale: Locale) -> String { L10n.string("positions_share.entry_price", locale: locale) }
        static func latestPrice(locale: Locale) -> String { L10n.string("positions_share.latest_price", locale: locale) }
        static func unrealizedPL(locale: Locale) -> String { L10n.string("positions_share.unrealized_pl", locale: locale) }
        static func morePositions(count: Int, locale: Locale) -> String {
            L10n.format("positions_share.more_positions_format", locale: locale, count)
        }
        static func other(locale: Locale) -> String { L10n.string("positions_share.other", locale: locale) }
        static func positionCount(count: Int, locale: Locale) -> String {
            L10n.format("positions_share.position_count_format", locale: locale, count)
        }
    }

    enum PositionDetail {
        static var title: LocalizedStringKey { "position_detail.title" }
        static var loading: LocalizedStringKey { "position_detail.loading" }
        static var notFound: LocalizedStringKey { "position_detail.not_found" }
        static var errorTitle: LocalizedStringKey { "position_detail.error_title" }
        static var viewAsset: LocalizedStringKey { "position_detail.view_asset" }
        static var share: LocalizedStringKey { "position_detail.share" }
        static var yourPosition: LocalizedStringKey { "position_detail.your_position" }
        static var overview: LocalizedStringKey { "position_detail.overview" }
        static var holdings: LocalizedStringKey { "position_detail.holdings" }
        static var performance: LocalizedStringKey { "position_detail.performance" }
        static var pricingCost: LocalizedStringKey { "position_detail.pricing_cost" }
        static var instrument: LocalizedStringKey { "position_detail.instrument" }
        static var side: LocalizedStringKey { "position_detail.side" }
        static var quantity: LocalizedStringKey { "position_detail.quantity" }
        static var available: LocalizedStringKey { "position_detail.available" }
        static var availableShort: LocalizedStringKey { "position_detail.available_short" }
        static var marketValue: LocalizedStringKey { "position_detail.market_value" }
        static var today: LocalizedStringKey { "position_detail.today" }
        static var unrealizedPL: LocalizedStringKey { "position_detail.unrealized_pl" }
        static var unrealizedPLPercent: LocalizedStringKey { "position_detail.unrealized_pl_percent" }
        static var intradayPL: LocalizedStringKey { "position_detail.intraday_pl" }
        static var intradayPLPercent: LocalizedStringKey { "position_detail.intraday_pl_percent" }
        static var changeToday: LocalizedStringKey { "position_detail.change_today" }
        static var averageEntryPrice: LocalizedStringKey { "position_detail.average_entry_price" }
        static var averageEntryPriceShort: LocalizedStringKey { "position_detail.average_entry_price_short" }
        static var currentPrice: LocalizedStringKey { "position_detail.current_price" }
        static var lastDayPrice: LocalizedStringKey { "position_detail.last_day_price" }
        static var costBasis: LocalizedStringKey { "position_detail.cost_basis" }
        static var costBasisShort: LocalizedStringKey { "position_detail.cost_basis_short" }
        static var symbol: LocalizedStringKey { "position_detail.symbol" }
        static var assetID: LocalizedStringKey { "position_detail.asset_id" }
        static var exchange: LocalizedStringKey { "position_detail.exchange" }
        static var assetClass: LocalizedStringKey { "position_detail.asset_class" }
        static var assetMarginable: LocalizedStringKey { "position_detail.asset_marginable" }

        static func notFoundDescription(locale: Locale = .current) -> String {
            L10n.string("position_detail.not_found_description", locale: locale)
        }

        static func closeAction(locale: Locale = .current) -> String {
            L10n.string("position_detail.close_action", locale: locale)
        }

        static func closeSheetTitle(locale: Locale = .current) -> String {
            L10n.string("position_detail.close_sheet_title", locale: locale)
        }

        static func closeConfirmAction(locale: Locale = .current) -> String {
            L10n.string("position_detail.close_confirm_action", locale: locale)
        }

        static func closeSheetMessage(symbol: String, locale: Locale = .current) -> String {
            L10n.format("position_detail.close_sheet_message_format", locale: locale, symbol)
        }

        static func closeSubmitted(symbol: String, locale: Locale = .current) -> String {
            L10n.format("position_detail.close_submitted_format", locale: locale, symbol)
        }

        static func closeUnavailable(locale: Locale = .current) -> String {
            L10n.string("position_detail.close_unavailable", locale: locale)
        }

        static func long(locale: Locale = .current) -> String {
            L10n.string("position_detail.long", locale: locale)
        }

        static func short(locale: Locale = .current) -> String {
            L10n.string("position_detail.short", locale: locale)
        }

        static func yes(locale: Locale = .current) -> String {
            L10n.string("position_detail.yes", locale: locale)
        }

        static func no(locale: Locale = .current) -> String {
            L10n.string("position_detail.no", locale: locale)
        }

        static func quantityUnitShare(locale: Locale = .current) -> String {
            L10n.string("position_detail.quantity_unit.share", locale: locale)
        }

        static func quantityUnitShares(locale: Locale = .current) -> String {
            L10n.string("position_detail.quantity_unit.shares", locale: locale)
        }

        static func quantityUnitContract(locale: Locale = .current) -> String {
            L10n.string("position_detail.quantity_unit.contract", locale: locale)
        }

        static func quantityUnitContracts(locale: Locale = .current) -> String {
            L10n.string("position_detail.quantity_unit.contracts", locale: locale)
        }

        static func quantityUnitUnit(locale: Locale = .current) -> String {
            L10n.string("position_detail.quantity_unit.unit", locale: locale)
        }

        static func quantityUnitUnits(locale: Locale = .current) -> String {
            L10n.string("position_detail.quantity_unit.units", locale: locale)
        }
    }

    enum AssetPositionShare {
        static var title: LocalizedStringKey { "asset_position_share.title" }
        static var done: LocalizedStringKey { "asset_position_share.done" }
        static var previewAccessibility: LocalizedStringKey { "asset_position_share.preview_accessibility" }
        static func save(locale: Locale) -> String { L10n.string("asset_position_share.save", locale: locale) }
        static func saving(locale: Locale) -> String { L10n.string("asset_position_share.saving", locale: locale) }
        static func saved(locale: Locale) -> String { L10n.string("asset_position_share.saved", locale: locale) }
        static func share(locale: Locale) -> String { L10n.string("asset_position_share.share", locale: locale) }
        static func preparingImage(locale: Locale) -> String { L10n.string("asset_position_share.preparing_image", locale: locale) }
        static func sharePreviewTitle(symbol: String, locale: Locale) -> String {
            L10n.format("asset_position_share.preview_title_format", locale: locale, symbol)
        }
        static func openSettings(locale: Locale) -> String { L10n.string("asset_position_share.open_settings", locale: locale) }
        static func ok(locale: Locale) -> String { L10n.string("asset_position_share.ok", locale: locale) }
        static func photoAccessOffTitle(locale: Locale) -> String { L10n.string("asset_position_share.photo_access_off.title", locale: locale) }
        static func photoAccessOffMessage(locale: Locale) -> String { L10n.string("asset_position_share.photo_access_off.message", locale: locale) }
        static func photoAccessRestrictedTitle(locale: Locale) -> String { L10n.string("asset_position_share.photo_access_restricted.title", locale: locale) }
        static func photoAccessRestrictedMessage(locale: Locale) -> String { L10n.string("asset_position_share.photo_access_restricted.message", locale: locale) }
        static func photoAccessNeededTitle(locale: Locale) -> String { L10n.string("asset_position_share.photo_access_needed.title", locale: locale) }
        static func photoAccessNeededMessage(locale: Locale) -> String { L10n.string("asset_position_share.photo_access_needed.message", locale: locale) }
        static func prepareFailed(locale: Locale) -> String { L10n.string("asset_position_share.prepare_failed", locale: locale) }
        static func saveFailed(locale: Locale) -> String { L10n.string("asset_position_share.save_failed", locale: locale) }
        static func entryPrice(locale: Locale) -> String { L10n.string("asset_position_share.entry_price", locale: locale) }
        static func latestPrice(locale: Locale) -> String { L10n.string("asset_position_share.latest_price", locale: locale) }
    }

    enum AssetShare {
        static var title: LocalizedStringKey { "asset_share.title" }
        static var previewAccessibility: LocalizedStringKey { "asset_share.preview_accessibility" }
        static func sharePreviewTitle(symbol: String, locale: Locale) -> String {
            L10n.format("asset_share.preview_title_format", locale: locale, symbol)
        }
        static func marketSnapshot(locale: Locale) -> String { L10n.string("asset_share.market_snapshot", locale: locale) }
        static func open(locale: Locale) -> String { L10n.string("asset_share.open", locale: locale) }
        static func high(locale: Locale) -> String { L10n.string("asset_share.high", locale: locale) }
        static func low(locale: Locale) -> String { L10n.string("asset_share.low", locale: locale) }
        static func volume(locale: Locale) -> String { L10n.string("asset_share.volume", locale: locale) }
    }

    enum PositionCategory {
        static func title(_ category: PositionAssetCategory, locale: Locale) -> String {
            switch category {
            case .stock:
                L10n.string("position.category.stock.title", locale: locale)
            case .etf:
                L10n.string("position.category.etf.title", locale: locale)
            case .option:
                L10n.string("position.category.option.title", locale: locale)
            case .crypto:
                L10n.string("position.category.crypto.title", locale: locale)
            }
        }

        static func chipTitle(_ category: PositionAssetCategory, locale: Locale) -> String {
            switch category {
            case .stock:
                L10n.string("position.category.stock.chip", locale: locale)
            case .etf:
                L10n.string("position.category.etf.chip", locale: locale)
            case .option:
                L10n.string("position.category.option.chip", locale: locale)
            case .crypto:
                L10n.string("position.category.crypto.chip", locale: locale)
            }
        }

        static func emptyTitle(_ category: PositionAssetCategory, locale: Locale) -> String {
            switch category {
            case .stock:
                L10n.string("position.category.stock.empty_title", locale: locale)
            case .etf:
                L10n.string("position.category.etf.empty_title", locale: locale)
            case .option:
                L10n.string("position.category.option.empty_title", locale: locale)
            case .crypto:
                L10n.string("position.category.crypto.empty_title", locale: locale)
            }
        }
    }

    enum Alpaca {
        static var title: LocalizedStringKey { "alpaca.title" }
        static var bootstrapLoading: LocalizedStringKey { "alpaca.bootstrap_loading" }
        static var onboardingTitle: LocalizedStringKey { "alpaca.onboarding_title" }
        static var onboardingDescription: LocalizedStringKey { "alpaca.onboarding_description" }
        static var onboardingSavedFooter: LocalizedStringKey { "alpaca.onboarding_saved_footer" }
        static var connectAction: LocalizedStringKey { "alpaca.connect_action" }
        static var connection: LocalizedStringKey { "alpaca.connection" }
        static var environment: LocalizedStringKey { "alpaca.environment" }
        static var connectedDescription: LocalizedStringKey { "alpaca.connected_description" }
        static var notConnectedDescription: LocalizedStringKey { "alpaca.not_connected_description" }
        static var apiKey: LocalizedStringKey { "alpaca.api_key" }
        static var apiKeyID: LocalizedStringKey { "alpaca.api_key_id" }
        static var apiSecretKey: LocalizedStringKey { "alpaca.api_secret_key" }
        static var testConnection: LocalizedStringKey { "alpaca.test_connection" }
        static var testSavedConnection: LocalizedStringKey { "alpaca.test_saved_connection" }
        static var testingConnection: LocalizedStringKey { "alpaca.testing_connection" }
        static var testConnectionHint: LocalizedStringKey { "alpaca.test_connection_hint" }
        static var saveToKeychain: LocalizedStringKey { "alpaca.save_to_keychain" }
        static var saveToKeychainHint: LocalizedStringKey { "alpaca.save_to_keychain_hint" }
        static var removeCredentials: LocalizedStringKey { "alpaca.remove_credentials" }
        static var removeCredentialsHint: LocalizedStringKey { "alpaca.remove_credentials_hint" }
        static var apiKeyFooter: LocalizedStringKey { "alpaca.api_key_footer" }
        static var apiKeyVerifiedFooter: LocalizedStringKey { "alpaca.api_key_verified_footer" }
        static var savedCredentials: LocalizedStringKey { "alpaca.saved_credentials" }
        static var savedCredentialsFooter: LocalizedStringKey { "alpaca.saved_credentials_footer" }
        static var savedInKeychain: LocalizedStringKey { "alpaca.saved_in_keychain" }
        static var secretSavedDescription: LocalizedStringKey { "alpaca.secret_saved_description" }
        static var lastMessage: LocalizedStringKey { "alpaca.last_message" }
        static var networkDiagnostics: LocalizedStringKey { "alpaca.network_diagnostics" }
        static var latency: LocalizedStringKey { "alpaca.latency" }
        static var endpoint: LocalizedStringKey { "alpaca.endpoint" }
        static var httpStatus: LocalizedStringKey { "alpaca.http_status" }
        static var checkedAt: LocalizedStringKey { "alpaca.checked_at" }
        static var result: LocalizedStringKey { "alpaca.result" }
        static var success: LocalizedStringKey { "alpaca.success" }
        static var failed: LocalizedStringKey { "alpaca.failed" }
    }

    enum More {
        static var title: LocalizedStringKey { "more.title" }
        static func ordersTitle(locale: Locale) -> String { L10n.string("more.orders.title", locale: locale) }
        static func ordersSubtitle(locale: Locale) -> String { L10n.string("more.orders.subtitle", locale: locale) }
        static func riskTitle(locale: Locale) -> String { L10n.string("more.risk.title", locale: locale) }
        static func alpacaTitle(locale: Locale) -> String { L10n.string("more.alpaca.title", locale: locale) }
        static func notificationsTitle(locale: Locale) -> String { L10n.string("more.notifications.title", locale: locale) }
        static func notificationsSubtitle(locale: Locale) -> String { L10n.string("more.notifications.subtitle", locale: locale) }
        static func settingsTitle(locale: Locale) -> String { L10n.string("more.settings.title", locale: locale) }
        static func killSwitchActive(locale: Locale) -> String { L10n.string("more.risk.kill_switch_active", locale: locale) }
        static func liveTradingLocked(locale: Locale) -> String { L10n.string("more.risk.live_trading_locked", locale: locale) }
        static func staticRiskChecksEnabled(locale: Locale) -> String { L10n.string("more.risk.static_checks_enabled", locale: locale) }

        static func settingsSubtitle(theme: String, locale: Locale) -> String {
            L10n.format("more.settings.subtitle_format", locale: locale, theme)
        }
    }

    enum Settings {
        static var title: LocalizedStringKey { "settings.title" }
        static var appearance: LocalizedStringKey { "settings.appearance" }
        static var themeMode: LocalizedStringKey { "settings.theme_mode" }
        static var themeModeFooter: LocalizedStringKey { "settings.theme_mode_footer" }
        static var language: LocalizedStringKey { "settings.language" }
        static var appLanguage: LocalizedStringKey { "settings.app_language" }
        static var languageFooter: LocalizedStringKey { "settings.language_footer" }
        static var logoDev: LocalizedStringKey { "settings.logo_dev" }
        static var logoDevEnabled: LocalizedStringKey { "settings.logo_dev_enabled" }
        static var logoDevAPIKey: LocalizedStringKey { "settings.logo_dev_api_key" }
        static var logoDevAPIKeyPlaceholder: LocalizedStringKey { "settings.logo_dev_api_key_placeholder" }
        static var logoDevFooter: LocalizedStringKey { "settings.logo_dev_footer" }
        static var clearLogoDevAPIKey: LocalizedStringKey { "settings.clear_logo_dev_api_key" }
        static var themeSystem: LocalizedStringKey { "settings.theme.system" }
        static var themeDark: LocalizedStringKey { "settings.theme.dark" }
        static var themeLight: LocalizedStringKey { "settings.theme.light" }
        static var languageSystem: LocalizedStringKey { "settings.language.system" }
        static var languageEnglish: LocalizedStringKey { "settings.language.english" }
        static var languageSimplifiedChinese: LocalizedStringKey { "settings.language.simplified_chinese" }
        static func themeSystemText(locale: Locale) -> String { L10n.string("settings.theme.system", locale: locale) }
        static func themeDarkText(locale: Locale) -> String { L10n.string("settings.theme.dark", locale: locale) }
        static func themeLightText(locale: Locale) -> String { L10n.string("settings.theme.light", locale: locale) }
        static func languageSystemText(locale: Locale) -> String { L10n.string("settings.language.system", locale: locale) }
        static func languageEnglishText(locale: Locale) -> String { L10n.string("settings.language.english", locale: locale) }
        static func languageSimplifiedChineseText(locale: Locale) -> String { L10n.string("settings.language.simplified_chinese", locale: locale) }
    }

    enum NotificationSettings {
        static var title: LocalizedStringKey { "notifications.title" }
        static var allowNotifications: LocalizedStringKey { "notifications.allow" }
        static var tradeOrderSubmitted: LocalizedStringKey { "notifications.trade_order_submitted" }
        static var tradeOrderStatus: LocalizedStringKey { "notifications.trade_order_status" }
        static var accountActivity: LocalizedStringKey { "notifications.account_activity" }
        static var footer: LocalizedStringKey { "notifications.footer" }
    }

    enum API {
        static var invalidURL: String { L10n.string("api.invalid_url") }
        static var invalidResponse: String { L10n.string("api.invalid_response") }
        static var emptyResponse: String { L10n.string("api.empty_response") }
        static var cancelled: String { L10n.string("api.cancelled") }
        static func invalidURLText(locale: Locale = .current) -> String { L10n.string("api.invalid_url", locale: locale) }
        static func invalidResponseText(locale: Locale = .current) -> String { L10n.string("api.invalid_response", locale: locale) }
        static func emptyResponseText(locale: Locale = .current) -> String { L10n.string("api.empty_response", locale: locale) }
        static func cancelledText(locale: Locale = .current) -> String { L10n.string("api.cancelled", locale: locale) }
        static func transportFailed(_ message: String) -> String {
            L10n.format("api.transport_failed_format", message)
        }
        static func requestFailed(statusCode: Int, message: String) -> String {
            L10n.format("api.request_failed_format", statusCode, message)
        }
        static func requestFailed(statusCode: Int, message: String, locale: Locale) -> String {
            L10n.format("api.request_failed_format", locale: locale, statusCode, message)
        }
        static func decodingFailed(_ message: String) -> String {
            L10n.format("api.decoding_failed_format", message)
        }
        static func credentialsRejected(locale: Locale = .current) -> String {
            L10n.string("api.error.credentials_rejected", locale: locale)
        }
        static func permissionDenied(locale: Locale = .current) -> String {
            L10n.string("api.error.permission_denied", locale: locale)
        }
        static func resourceUnavailable(locale: Locale = .current) -> String {
            L10n.string("api.error.resource_unavailable", locale: locale)
        }
        static func requestRejected(locale: Locale = .current) -> String {
            L10n.string("api.error.request_rejected", locale: locale)
        }
        static func rateLimited(locale: Locale = .current) -> String {
            L10n.string("api.error.rate_limited", locale: locale)
        }
        static func serviceUnavailable(locale: Locale = .current) -> String {
            L10n.string("api.error.service_unavailable", locale: locale)
        }
        static func timeout(locale: Locale = .current) -> String {
            L10n.string("api.error.timeout", locale: locale)
        }
        static func networkUnavailable(locale: Locale = .current) -> String {
            L10n.string("api.error.network_unavailable", locale: locale)
        }
        static func networkRequestFailed(locale: Locale = .current) -> String {
            L10n.string("api.error.network_request_failed", locale: locale)
        }
        static func unexpected(locale: Locale = .current) -> String {
            L10n.string("api.error.unexpected", locale: locale)
        }
    }

    enum Tab {
        static var home: LocalizedStringKey { "tab.home" }
        static var markets: LocalizedStringKey { "tab.markets" }
        static var search: LocalizedStringKey { "tab.search" }
        static var orders: LocalizedStringKey { "tab.orders" }
        static var trade: LocalizedStringKey { "tab.trade" }
        static var more: LocalizedStringKey { "tab.more" }
    }

    enum Environment {
        static var paper: LocalizedStringKey { "environment.paper" }
        static var live: LocalizedStringKey { "environment.live" }
        static func paperText(locale: Locale) -> String { L10n.string("environment.paper", locale: locale) }
        static func liveText(locale: Locale) -> String { L10n.string("environment.live", locale: locale) }
    }

    enum Markets {
        static var title: LocalizedStringKey { "markets.title" }
        static var searchTitle: LocalizedStringKey { "markets.search_title" }
        static var searchPlaceholder: LocalizedStringKey { "markets.search_placeholder" }
        static var searchSymbols: LocalizedStringKey { "markets.search_symbols" }
        static var searching: LocalizedStringKey { "markets.searching" }
        static var searchNoResults: LocalizedStringKey { "markets.search_no_results" }
        static var searchNoResultsDescription: LocalizedStringKey { "markets.search_no_results_description" }
        static var searchPopularTitle: LocalizedStringKey { "markets.search_popular_title" }
        static var searchPopularSubtitle: LocalizedStringKey { "markets.search_popular_subtitle" }
        static var searchPopularTradesSubtitle: LocalizedStringKey { "markets.search_popular_subtitle.trades" }
        static var searchPopularVolumeSubtitle: LocalizedStringKey { "markets.search_popular_subtitle.volume" }
        static var searchPopularUnavailable: LocalizedStringKey { "markets.search_popular_unavailable" }
        static var sortVolume: LocalizedStringKey { "markets.sort.volume" }
        static var sortTrades: LocalizedStringKey { "markets.sort.trades" }
        static var equity: LocalizedStringKey { "markets.category.equity" }
        static var etf: LocalizedStringKey { "markets.category.etf" }
        static var crypto: LocalizedStringKey { "markets.category.crypto" }
        static var connectAlpaca: LocalizedStringKey { "markets.connect_alpaca" }
        static var credentialRequired: LocalizedStringKey { "markets.credential_required" }
        static var loadingData: LocalizedStringKey { "markets.loading_data" }
        static var dataUnavailable: LocalizedStringKey { "markets.data_unavailable" }
        static var pullToRefresh: LocalizedStringKey { "markets.pull_to_refresh" }
        static var status: LocalizedStringKey { "markets.status" }
        static var open: LocalizedStringKey { "markets.open" }
        static var closed: LocalizedStringKey { "markets.closed" }
        static var preMarket: LocalizedStringKey { "markets.pre_market" }
        static var afterHours: LocalizedStringKey { "markets.after_hours" }
        static var overnight: LocalizedStringKey { "markets.overnight" }
        static var regularSession: LocalizedStringKey { "markets.regular_session" }
        static var extendedSession: LocalizedStringKey { "markets.extended_session" }
        static var marketClosed: LocalizedStringKey { "markets.market_closed" }
        static var timestampUnavailable: LocalizedStringKey { "markets.timestamp_unavailable" }
        static var nextClose: LocalizedStringKey { "markets.next_close" }
        static var nextOpen: LocalizedStringKey { "markets.next_open" }
        static var indexProxySource: LocalizedStringKey { "markets.index_proxy_source" }
        static var indexProxyDescription: LocalizedStringKey { "markets.index_proxy_description" }
        static var topGainers: LocalizedStringKey { "markets.top_gainers" }
        static var topLosers: LocalizedStringKey { "markets.top_losers" }
        static var mostActive: LocalizedStringKey { "markets.most_active" }
        static var favorites: LocalizedStringKey { "markets.favorites" }
        static var popular: LocalizedStringKey { "markets.popular" }
        static var noFavorites: LocalizedStringKey { "markets.no_favorites" }
        static var noFavoritesDescription: LocalizedStringKey { "markets.no_favorites_description" }
        static var noScreenerData: LocalizedStringKey { "markets.no_screener_data" }
        static var noActivityData: LocalizedStringKey { "markets.no_activity_data" }
        static var volume: LocalizedStringKey { "markets.volume" }
        static var retry: LocalizedStringKey { "markets.retry" }
        static var apiNotConnected: LocalizedStringKey { "markets.api_not_connected" }
        static var apiNotConnectedDescription: LocalizedStringKey { "markets.api_not_connected_description" }
    }

    enum Watchlists {
        static var title: LocalizedStringKey { "watchlists.title" }
        static var actionsTitle: LocalizedStringKey { "watchlists.actions.title" }
        static var createTitle: LocalizedStringKey { "watchlists.create.title" }
        static var editTitle: LocalizedStringKey { "watchlists.edit.title" }
        static var createAction: LocalizedStringKey { "watchlists.create.action" }
        static var saveAction: LocalizedStringKey { "watchlists.save.action" }
        static var deleteAction: LocalizedStringKey { "watchlists.delete.action" }
        static var reorderAction: LocalizedStringKey { "watchlists.reorder.action" }
        static var reorderDoneAction: LocalizedStringKey { "watchlists.reorder.done_action" }
        static var deleteConfirmTitle: LocalizedStringKey { "watchlists.delete.confirm.title" }
        static var nameTitle: LocalizedStringKey { "watchlists.name.title" }
        static var namePlaceholder: LocalizedStringKey { "watchlists.name.placeholder" }
        static var symbolsTitle: LocalizedStringKey { "watchlists.symbols.title" }
        static var symbolsPlaceholder: LocalizedStringKey { "watchlists.symbols.placeholder" }
        static var symbolsFooter: LocalizedStringKey { "watchlists.symbols.footer" }
        static var assetsTitle: LocalizedStringKey { "watchlists.assets.title" }
        static var currentAssetsTitle: LocalizedStringKey { "watchlists.current_assets.title" }
        static var availableAssetsTitle: LocalizedStringKey { "watchlists.available_assets.title" }
        static var assetSearchPrompt: LocalizedStringKey { "watchlists.asset_search.prompt" }
        static var symbolTitle: LocalizedStringKey { "watchlists.symbol.title" }
        static var symbolPlaceholder: LocalizedStringKey { "watchlists.symbol.placeholder" }
        static var addSymbolTitle: LocalizedStringKey { "watchlists.add_symbol.title" }
        static var addSymbolAction: LocalizedStringKey { "watchlists.add_symbol.action" }
        static var removeSymbolAction: LocalizedStringKey { "watchlists.remove_symbol.action" }
        static var emptyTitle: LocalizedStringKey { "watchlists.empty.title" }
        static var emptyDescription: LocalizedStringKey { "watchlists.empty.description" }
        static var noAssetsTitle: LocalizedStringKey { "watchlists.no_assets.title" }
        static var noAssetsDescription: LocalizedStringKey { "watchlists.no_assets.description" }
        static var missingTitle: LocalizedStringKey { "watchlists.missing.title" }
        static var missingDescription: LocalizedStringKey { "watchlists.missing.description" }

        static func assetCount(_ count: Int, locale: Locale) -> String {
            L10n.format("watchlists.asset_count_format", locale: locale, count)
        }

        static func createdToast(name: String, locale: Locale) -> String {
            L10n.format("watchlists.toast.created_format", locale: locale, name)
        }

        static func updatedToast(name: String, locale: Locale) -> String {
            L10n.format("watchlists.toast.updated_format", locale: locale, name)
        }

        static func deletedToast(name: String, locale: Locale) -> String {
            L10n.format("watchlists.toast.deleted_format", locale: locale, name)
        }

        static func symbolAddedToast(symbol: String, locale: Locale) -> String {
            L10n.format("watchlists.toast.symbol_added_format", locale: locale, symbol)
        }

        static func symbolRemovedToast(symbol: String, locale: Locale) -> String {
            L10n.format("watchlists.toast.symbol_removed_format", locale: locale, symbol)
        }

        static func deleteConfirmMessage(name: String, locale: Locale) -> String {
            L10n.format("watchlists.delete.confirm.message_format", locale: locale, name)
        }

        static func duplicateSymbol(symbol: String, locale: Locale) -> String {
            L10n.format("watchlists.duplicate_symbol_format", locale: locale, symbol)
        }

        static func invalidSymbol(locale: Locale) -> String {
            L10n.string("watchlists.invalid_symbol", locale: locale)
        }

        static func nameRequired(locale: Locale) -> String {
            L10n.string("watchlists.name.required", locale: locale)
        }
    }

    enum Orders {
        static var title: LocalizedStringKey { "orders.title" }
        static var recentTitle: LocalizedStringKey { "orders.recent.title" }
        static var recentEmptyTitle: LocalizedStringKey { "orders.recent.empty.title" }
        static var recentEmptyDescription: LocalizedStringKey { "orders.recent.empty.description" }
        static var emptyTitle: LocalizedStringKey { "orders.empty.title" }
        static var emptyDescription: LocalizedStringKey { "orders.empty.description" }
        static var filteredEmptyTitle: LocalizedStringKey { "orders.filtered.empty.title" }
        static var filteredEmptyDescription: LocalizedStringKey { "orders.filtered.empty.description" }
        static var filterSheetTitle: LocalizedStringKey { "orders.filter.title" }
        static var filterReset: LocalizedStringKey { "orders.filter.reset" }
        static var filterApply: LocalizedStringKey { "orders.filter.apply" }
        static var filterStatus: LocalizedStringKey { "orders.filter.status" }
        static var filterTime: LocalizedStringKey { "orders.filter.time" }
        static var filterStartDate: LocalizedStringKey { "orders.filter.start_date" }
        static var filterEndDate: LocalizedStringKey { "orders.filter.end_date" }
        static var filterSymbols: LocalizedStringKey { "orders.filter.symbols" }
        static var filterNoSymbols: LocalizedStringKey { "orders.filter.no_symbols" }
        static var filterSide: LocalizedStringKey { "orders.filter.side" }
        static var filterResults: LocalizedStringKey { "orders.filter.results" }
        static var cancelConfirmTitle: LocalizedStringKey { "orders.cancel.confirm.title" }
        static var replacePriceTitle: LocalizedStringKey { "orders.replace_price.title" }
        static var priceSymbol: LocalizedStringKey { "orders.price.symbol" }
        static var currentPrice: LocalizedStringKey { "orders.price.current" }
        static func filterButton(locale: Locale) -> String { L10n.string("orders.filter.button", locale: locale) }
        static func filterTitle(locale: Locale) -> String { L10n.string("orders.filter.title", locale: locale) }
        static func filterActiveCount(_ count: Int, locale: Locale) -> String { L10n.format("orders.filter.active_count_format", locale: locale, count) }
        static func filterReset(locale: Locale) -> String { L10n.string("orders.filter.reset", locale: locale) }
        static func filterApply(locale: Locale) -> String { L10n.string("orders.filter.apply", locale: locale) }
        static func filterStatus(locale: Locale) -> String { L10n.string("orders.filter.status", locale: locale) }
        static func filterTime(locale: Locale) -> String { L10n.string("orders.filter.time", locale: locale) }
        static func filterStartDate(locale: Locale) -> String { L10n.string("orders.filter.start_date", locale: locale) }
        static func filterEndDate(locale: Locale) -> String { L10n.string("orders.filter.end_date", locale: locale) }
        static func filterSymbols(locale: Locale) -> String { L10n.string("orders.filter.symbols", locale: locale) }
        static func filterNoSymbols(locale: Locale) -> String { L10n.string("orders.filter.no_symbols", locale: locale) }
        static func filterSide(locale: Locale) -> String { L10n.string("orders.filter.side", locale: locale) }
        static func filterResults(locale: Locale) -> String { L10n.string("orders.filter.results", locale: locale) }
        static func filterAll(locale: Locale) -> String { L10n.string("orders.filter.all", locale: locale) }
        static func filterOpen(locale: Locale) -> String { L10n.string("orders.filter.open", locale: locale) }
        static func filterFilled(locale: Locale) -> String { L10n.string("orders.filter.filled", locale: locale) }
        static func filterCanceled(locale: Locale) -> String { L10n.string("orders.filter.canceled", locale: locale) }
        static func filterOther(locale: Locale) -> String { L10n.string("orders.filter.other", locale: locale) }
        static func filterTimeAll(locale: Locale) -> String { L10n.string("orders.filter.time.all", locale: locale) }
        static func filterTimeLastWeek(locale: Locale) -> String { L10n.string("orders.filter.time.last_week", locale: locale) }
        static func filterTimeLastMonth(locale: Locale) -> String { L10n.string("orders.filter.time.last_month", locale: locale) }
        static func filterTimeLastThreeMonths(locale: Locale) -> String { L10n.string("orders.filter.time.last_three_months", locale: locale) }
        static func filterTimeCustom(locale: Locale) -> String { L10n.string("orders.filter.time.custom", locale: locale) }
        static func filterAllSymbols(locale: Locale) -> String { L10n.string("orders.filter.all_symbols", locale: locale) }
        static func filterSymbolSearchPlaceholder(locale: Locale) -> String { L10n.string("orders.filter.symbol_search_placeholder", locale: locale) }
        static func filterSymbolNoMatches(locale: Locale) -> String { L10n.string("orders.filter.symbol_no_matches", locale: locale) }
        static func filterSymbolSelectionCount(_ count: Int, locale: Locale) -> String { L10n.format("orders.filter.symbol_selection_count_format", locale: locale, count) }
        static func filterSideAll(locale: Locale) -> String { L10n.string("orders.filter.side.all", locale: locale) }
        static func filterSideBuy(locale: Locale) -> String { L10n.string("orders.filter.side.buy", locale: locale) }
        static func filterSideSell(locale: Locale) -> String { L10n.string("orders.filter.side.sell", locale: locale) }
        static func quantityPrefix(locale: Locale) -> String { L10n.string("orders.quantity_prefix", locale: locale) }
        static func notionalPrefix(locale: Locale) -> String { L10n.string("orders.notional_prefix", locale: locale) }
        static func extendedHoursTag(locale: Locale) -> String { L10n.string("orders.extended_hours_tag", locale: locale) }
        static func actionMenu(locale: Locale) -> String { L10n.string("orders.action.menu", locale: locale) }
        static func cancelOrder(locale: Locale) -> String { L10n.string("orders.action.cancel", locale: locale) }
        static func replacePrice(locale: Locale) -> String { L10n.string("orders.action.replace_price", locale: locale) }
        static func savePrice(locale: Locale) -> String { L10n.string("orders.action.save_price", locale: locale) }
        static func cancelConfirmMessage(symbol: String, locale: Locale) -> String { L10n.format("orders.cancel.confirm.message_format", locale: locale, symbol) }
        static func cancelSheetTitle(locale: Locale) -> String { L10n.string("orders.cancel.sheet.title", locale: locale) }
        static func cancelHoldAction(locale: Locale) -> String { L10n.string("orders.cancel.sheet.hold_action", locale: locale) }
        static func cancelHoldProgress(locale: Locale) -> String { L10n.string("orders.cancel.sheet.hold_progress", locale: locale) }
        static func cancelHoldSubmitting(locale: Locale) -> String { L10n.string("orders.cancel.sheet.hold_submitting", locale: locale) }
        static func cancelRequestedToast(symbol: String, locale: Locale) -> String { L10n.format("orders.toast.cancel_requested_format", locale: locale, symbol) }
        static func priceReplacedToast(symbol: String, locale: Locale) -> String { L10n.format("orders.toast.price_replaced_format", locale: locale, symbol) }
        static func cancelLiveActivityAwaitingConfirmation(symbol: String, locale: Locale) -> String { L10n.format("orders.live_activity.cancel.awaiting_confirmation_format", locale: locale, symbol) }
        static func cancelLiveActivitySubmitting(symbol: String, locale: Locale) -> String { L10n.format("orders.live_activity.cancel.submitting_format", locale: locale, symbol) }
        static func cancelLiveActivityFailed(symbol: String, locale: Locale) -> String { L10n.format("orders.live_activity.cancel.failed_format", locale: locale, symbol) }
        static func cancelLiveActivityDismissed(symbol: String, locale: Locale) -> String { L10n.format("orders.live_activity.cancel.dismissed_format", locale: locale, symbol) }
        static func actionNotCancelable(locale: Locale) -> String { L10n.string("orders.error.not_cancelable", locale: locale) }
        static func actionNotReplaceable(locale: Locale) -> String { L10n.string("orders.error.not_replaceable", locale: locale) }
        static func invalidPrice(locale: Locale) -> String { L10n.string("orders.error.invalid_price", locale: locale) }

        enum Detail {
            static var navigationTitle: LocalizedStringKey { "orders.detail.navigation_title" }
            static var title: LocalizedStringKey { "orders.detail.title" }
            static var execution: LocalizedStringKey { "orders.detail.execution" }
            static var priceConditions: LocalizedStringKey { "orders.detail.price_conditions" }
            static var timeline: LocalizedStringKey { "orders.detail.timeline" }
            static var metadata: LocalizedStringKey { "orders.detail.metadata" }
            static var errorTitle: LocalizedStringKey { "orders.detail.error_title" }
            static var retry: LocalizedStringKey { "orders.detail.retry" }
            static var quantity: LocalizedStringKey { "orders.detail.quantity" }
            static var notional: LocalizedStringKey { "orders.detail.notional" }
            static var filledQuantity: LocalizedStringKey { "orders.detail.filled_quantity" }
            static var filledAveragePrice: LocalizedStringKey { "orders.detail.filled_average_price" }
            static var timeInForce: LocalizedStringKey { "orders.detail.time_in_force" }
            static var extendedHours: LocalizedStringKey { "orders.detail.extended_hours" }
            static var orderType: LocalizedStringKey { "orders.detail.order_type" }
            static var orderClass: LocalizedStringKey { "orders.detail.order_class" }
            static var limitPrice: LocalizedStringKey { "orders.detail.limit_price" }
            static var stopPrice: LocalizedStringKey { "orders.detail.stop_price" }
            static var trailPrice: LocalizedStringKey { "orders.detail.trail_price" }
            static var trailPercent: LocalizedStringKey { "orders.detail.trail_percent" }
            static var highWaterMark: LocalizedStringKey { "orders.detail.high_water_mark" }
            static var createdAt: LocalizedStringKey { "orders.detail.created_at" }
            static var updatedAt: LocalizedStringKey { "orders.detail.updated_at" }
            static var submittedAt: LocalizedStringKey { "orders.detail.submitted_at" }
            static var filledAt: LocalizedStringKey { "orders.detail.filled_at" }
            static var expiredAt: LocalizedStringKey { "orders.detail.expired_at" }
            static var canceledAt: LocalizedStringKey { "orders.detail.canceled_at" }
            static var failedAt: LocalizedStringKey { "orders.detail.failed_at" }
            static var replacedAt: LocalizedStringKey { "orders.detail.replaced_at" }
            static var expiresAt: LocalizedStringKey { "orders.detail.expires_at" }
            static var orderID: LocalizedStringKey { "orders.detail.order_id" }
            static var clientOrderID: LocalizedStringKey { "orders.detail.client_order_id" }
            static var assetID: LocalizedStringKey { "orders.detail.asset_id" }
            static var assetClass: LocalizedStringKey { "orders.detail.asset_class" }
            static var positionIntent: LocalizedStringKey { "orders.detail.position_intent" }
            static var replacedBy: LocalizedStringKey { "orders.detail.replaced_by" }
            static var replaces: LocalizedStringKey { "orders.detail.replaces" }
            static var source: LocalizedStringKey { "orders.detail.source" }
            static var subtag: LocalizedStringKey { "orders.detail.subtag" }
            static var legs: LocalizedStringKey { "orders.detail.legs" }
            static var asset: LocalizedStringKey { "orders.detail.asset" }
            static var side: LocalizedStringKey { "orders.detail.side" }
            static var averageFillPrice: LocalizedStringKey { "orders.detail.average_fill_price" }
            static var status: LocalizedStringKey { "orders.detail.status" }
            static var tradeDirection: LocalizedStringKey { "orders.detail.trade_direction" }
            static var orderStatus: LocalizedStringKey { "orders.detail.order_status" }
            static var nameCode: LocalizedStringKey { "orders.detail.name_code" }
            static var orderQuantityPrice: LocalizedStringKey { "orders.detail.order_quantity_price" }
            static var orderAmount: LocalizedStringKey { "orders.detail.order_amount" }
            static var filledQuantityAveragePrice: LocalizedStringKey { "orders.detail.filled_quantity_average_price" }
            static var filledAmount: LocalizedStringKey { "orders.detail.filled_amount" }
            static var placedAt: LocalizedStringKey { "orders.detail.placed_at" }
            static var duration: LocalizedStringKey { "orders.detail.duration" }
            static var session: LocalizedStringKey { "orders.detail.session" }
            static var fillDetails: LocalizedStringKey { "orders.detail.fill_details" }
            static var fillTime: LocalizedStringKey { "orders.detail.fill_time" }
            static var fillPrice: LocalizedStringKey { "orders.detail.fill_price" }
            static var noFillDetails: LocalizedStringKey { "orders.detail.no_fill_details" }
            static var additionalDetails: LocalizedStringKey { "orders.detail.additional_details" }
            static func yes(locale: Locale) -> String { L10n.string("orders.detail.yes", locale: locale) }
            static func no(locale: Locale) -> String { L10n.string("orders.detail.no", locale: locale) }
            static func sideBuy(locale: Locale) -> String { L10n.string("orders.detail.side.buy", locale: locale) }
            static func sideSell(locale: Locale) -> String { L10n.string("orders.detail.side.sell", locale: locale) }
            static func statusFilled(locale: Locale) -> String { L10n.string("orders.detail.status.filled", locale: locale) }
            static func statusPartiallyFilled(locale: Locale) -> String { L10n.string("orders.detail.status.partially_filled", locale: locale) }
            static func statusAccepted(locale: Locale) -> String { L10n.string("orders.detail.status.accepted", locale: locale) }
            static func statusCanceled(locale: Locale) -> String { L10n.string("orders.detail.status.canceled", locale: locale) }
            static func statusExpired(locale: Locale) -> String { L10n.string("orders.detail.status.expired", locale: locale) }
            static func statusFailed(locale: Locale) -> String { L10n.string("orders.detail.status.failed", locale: locale) }
            static func orderTypeMarket(locale: Locale) -> String { L10n.string("orders.detail.order_type.market", locale: locale) }
            static func orderTypeLimit(locale: Locale) -> String { L10n.string("orders.detail.order_type.limit", locale: locale) }
            static func orderTypeStop(locale: Locale) -> String { L10n.string("orders.detail.order_type.stop", locale: locale) }
            static func orderTypeStopLimit(locale: Locale) -> String { L10n.string("orders.detail.order_type.stop_limit", locale: locale) }
            static func orderTypeTrailingStop(locale: Locale) -> String { L10n.string("orders.detail.order_type.trailing_stop", locale: locale) }
            static func timeInForceDay(locale: Locale) -> String { L10n.string("orders.detail.time_in_force.day", locale: locale) }
            static func timeInForceGTC(locale: Locale) -> String { L10n.string("orders.detail.time_in_force.gtc", locale: locale) }
            static func timeInForceOPG(locale: Locale) -> String { L10n.string("orders.detail.time_in_force.opg", locale: locale) }
            static func timeInForceCLS(locale: Locale) -> String { L10n.string("orders.detail.time_in_force.cls", locale: locale) }
            static func timeInForceIOC(locale: Locale) -> String { L10n.string("orders.detail.time_in_force.ioc", locale: locale) }
            static func timeInForceFOK(locale: Locale) -> String { L10n.string("orders.detail.time_in_force.fok", locale: locale) }
            static func regularSession(locale: Locale) -> String { L10n.string("orders.detail.session.regular", locale: locale) }
            static func extendedSession(locale: Locale) -> String { L10n.string("orders.detail.session.extended", locale: locale) }
            static func timezoneET(locale: Locale) -> String { L10n.string("orders.detail.timezone.et", locale: locale) }
            static func filledProgress(filledQuantity: String, quantity: String, locale: Locale) -> String {
                L10n.format("orders.detail.filled_progress_format", locale: locale, filledQuantity, quantity)
            }
        }
    }

    enum Risk {
        static var title: LocalizedStringKey { "risk.title" }
        static var globalControls: LocalizedStringKey { "risk.global_controls" }
        static var killSwitch: LocalizedStringKey { "risk.kill_switch" }
        static var requireOrderConfirmation: LocalizedStringKey { "risk.require_order_confirmation" }
        static var unlockLiveTrading: LocalizedStringKey { "risk.unlock_live_trading" }
        static var limits: LocalizedStringKey { "risk.limits" }
        static var maxOrder: LocalizedStringKey { "risk.max_order" }
        static var maxPosition: LocalizedStringKey { "risk.max_position" }
        static var status: LocalizedStringKey { "risk.status" }
        static var paperTradingSelected: LocalizedStringKey { "risk.paper_trading_selected" }
        static var liveTradingSelected: LocalizedStringKey { "risk.live_trading_selected" }
        static func killSwitchDecision(locale: Locale) -> String { L10n.string("risk.decision.kill_switch", locale: locale) }
        static func liveLockedDecision(locale: Locale) -> String { L10n.string("risk.decision.live_locked", locale: locale) }
        static func maxOrderExceededDecision(locale: Locale) -> String { L10n.string("risk.decision.max_order_exceeded", locale: locale) }
        static func accountMissingStaticDecision(locale: Locale) -> String { L10n.string("risk.decision.account_missing_static", locale: locale) }
        static func checksPassedDecision(locale: Locale) -> String { L10n.string("risk.decision.checks_passed", locale: locale) }
    }

    enum Trade {
        static func confirmHoldAction(side: String, locale: Locale) -> String {
            L10n.format("trade.confirm.hold_action_format", locale: locale, side)
        }
        static func confirmHoldProgress(locale: Locale) -> String {
            L10n.string("trade.confirm.hold_progress", locale: locale)
        }
        static func confirmTitle(symbol: String, locale: Locale) -> String {
            L10n.format("trade.confirm_title_format", locale: locale, symbol)
        }
        static func confirmMessage(environment: String, locale: Locale) -> String {
            L10n.format("trade.confirm_message_format", locale: locale, environment)
        }
        static func confirmSide(locale: Locale) -> String {
            L10n.string("trade.confirm.side", locale: locale)
        }
        static func confirmOrderType(locale: Locale) -> String {
            L10n.string("trade.confirm.order_type", locale: locale)
        }
        static func confirmQuantity(locale: Locale) -> String {
            L10n.string("trade.confirm.quantity", locale: locale)
        }
        static func confirmAmount(locale: Locale) -> String {
            L10n.string("trade.confirm.amount", locale: locale)
        }
        static func confirmEstimatedPrice(locale: Locale) -> String {
            L10n.string("trade.confirm.estimated_price", locale: locale)
        }
        static func confirmLimitPrice(locale: Locale) -> String {
            L10n.string("trade.confirm.limit_price", locale: locale)
        }
        static func confirmTimeInForce(locale: Locale) -> String {
            L10n.string("trade.confirm.time_in_force", locale: locale)
        }
        static func confirmSession(locale: Locale) -> String {
            L10n.string("trade.confirm.session", locale: locale)
        }
        static func confirmEnvironment(locale: Locale) -> String {
            L10n.string("trade.confirm.environment", locale: locale)
        }
        static func confirmShortSellTag(locale: Locale) -> String {
            L10n.string("trade.confirm.short_sell_tag", locale: locale)
        }
        static func confirmShortSellWarning(locale: Locale) -> String {
            L10n.string("trade.confirm.short_sell_warning", locale: locale)
        }
        static func addCredentialsBeforeOrder(locale: Locale) -> String {
            L10n.string("trade.add_credentials_before_order", locale: locale)
        }
        static func contextNotLoaded(locale: Locale) -> String {
            L10n.string("trade.error.context_not_loaded", locale: locale)
        }
        static func accountTradingBlocked(locale: Locale) -> String {
            L10n.string("trade.error.account_trading_blocked", locale: locale)
        }
        static func assetNotTradable(locale: Locale) -> String {
            L10n.string("trade.error.asset_not_tradable", locale: locale)
        }
        static func assetNotFractionable(locale: Locale) -> String {
            L10n.string("trade.error.asset_not_fractionable", locale: locale)
        }
        static func fractionalRequiresDay(locale: Locale) -> String {
            L10n.string("trade.error.fractional_requires_day", locale: locale)
        }
        static func notionalRequiresDay(locale: Locale) -> String {
            L10n.string("trade.error.notional_requires_day", locale: locale)
        }
        static func buyExceedsBuyingPower(locale: Locale) -> String {
            L10n.string("trade.error.buy_exceeds_buying_power", locale: locale)
        }
        static func sellExceedsPosition(locale: Locale) -> String {
            L10n.string("trade.error.sell_exceeds_position", locale: locale)
        }
        static func fractionalShortUnsupported(locale: Locale) -> String {
            L10n.string("trade.error.fractional_short_unsupported", locale: locale)
        }
        static func shortExceedsBuyingPower(locale: Locale) -> String {
            L10n.string("trade.error.short_exceeds_buying_power", locale: locale)
        }
        static func marketExtendedHoursUnsupported(locale: Locale) -> String {
            L10n.string("trade.error.market_extended_hours_unsupported", locale: locale)
        }
        static func executionPriceUnavailable(locale: Locale) -> String {
            L10n.string("trade.warning.execution_price_unavailable", locale: locale)
        }
        static func orderSubmitted(locale: Locale) -> String {
            L10n.string("trade.order_submitted", locale: locale)
        }
        static func simpleBuyingPowerAvailable(_ value: String, locale: Locale) -> String {
            L10n.format("trade.simple.buying_power_available_format", locale: locale, value)
        }
        static func simplePositionAvailable(quantity: String, value: String, locale: Locale) -> String {
            L10n.format("trade.simple.position_available_format", locale: locale, quantity, value)
        }
        static func simpleDollars(locale: Locale) -> String {
            L10n.string("trade.simple.dollars", locale: locale)
        }
        static func simpleShares(locale: Locale) -> String {
            L10n.string("trade.simple.shares", locale: locale)
        }
        static func simpleMarketOrder(locale: Locale) -> String {
            L10n.string("trade.simple.market_order", locale: locale)
        }
        static func simpleOrderTypeTitle(orderType: String, locale: Locale) -> String {
            L10n.format("trade.simple.order_type_title_format", locale: locale, orderType)
        }
        static func simpleMax(locale: Locale) -> String {
            L10n.string("trade.simple.max", locale: locale)
        }
        static func simpleEstimatedDebit(locale: Locale) -> String {
            L10n.string("trade.simple.estimated_debit", locale: locale)
        }
        static func simpleEstimatedCredit(locale: Locale) -> String {
            L10n.string("trade.simple.estimated_credit", locale: locale)
        }
        static func simpleReviewOrder(locale: Locale) -> String {
            L10n.string("trade.simple.review_order", locale: locale)
        }
        static func simpleInsufficientBuyingPower(locale: Locale) -> String {
            L10n.string("trade.simple.insufficient_buying_power", locale: locale)
        }
        static func simpleExceedsPosition(locale: Locale) -> String {
            L10n.string("trade.simple.exceeds_position", locale: locale)
        }
        static func simpleShortUnavailable(locale: Locale) -> String {
            L10n.string("trade.simple.short_unavailable", locale: locale)
        }
        static func simpleEnterAmount(locale: Locale) -> String {
            L10n.string("trade.simple.enter_amount", locale: locale)
        }
        static func simpleOrderUnavailable(locale: Locale) -> String {
            L10n.string("trade.simple.order_unavailable", locale: locale)
        }
        static func simpleSubmitting(locale: Locale) -> String {
            L10n.string("trade.simple.submitting", locale: locale)
        }
        static func simpleContinue(locale: Locale) -> String {
            L10n.string("trade.simple.continue", locale: locale)
        }
        static func simpleCloseTrade(locale: Locale) -> String {
            L10n.string("trade.simple.close_trade", locale: locale)
        }
        static func simpleDecimalPoint(locale: Locale) -> String {
            L10n.string("trade.simple.decimal_point", locale: locale)
        }
        static func simpleDelete(locale: Locale) -> String {
            L10n.string("trade.simple.delete", locale: locale)
        }
        static func limitTitle(side: String, symbol: String, locale: Locale) -> String {
            L10n.format("trade.limit.title_format", locale: locale, side, symbol)
        }
        static func limitSharesAvailable(_ quantity: String, locale: Locale) -> String {
            L10n.format("trade.limit.shares_available_format", locale: locale, quantity)
        }
        static func limitNumberOfShares(locale: Locale) -> String {
            L10n.string("trade.limit.number_of_shares", locale: locale)
        }
        static func limitPrice(locale: Locale) -> String {
            L10n.string("trade.limit.price", locale: locale)
        }
        static func limitBidAsk(bid: String, ask: String, locale: Locale) -> String {
            L10n.format("trade.limit.bid_ask_format", locale: locale, bid, ask)
        }
        static func limitBid(locale: Locale) -> String {
            L10n.string("trade.limit.bid", locale: locale)
        }
        static func limitMid(locale: Locale) -> String {
            L10n.string("trade.limit.mid", locale: locale)
        }
        static func limitAsk(locale: Locale) -> String {
            L10n.string("trade.limit.ask", locale: locale)
        }
    }

    enum Order {
        static func sideBuyText(locale: Locale) -> String { L10n.string("order.side.buy", locale: locale) }
        static func sideSellText(locale: Locale) -> String { L10n.string("order.side.sell", locale: locale) }
        static func typeMarketText(locale: Locale) -> String { L10n.string("order.type.market", locale: locale) }
        static func typeLimitText(locale: Locale) -> String { L10n.string("order.type.limit", locale: locale) }
        static func missingSymbol(locale: Locale = .current) -> String { L10n.string("order.error.missing_symbol", locale: locale) }
        static func missingSize(locale: Locale = .current) -> String { L10n.string("order.error.missing_size", locale: locale) }
        static func conflictingSize(locale: Locale = .current) -> String { L10n.string("order.error.conflicting_size", locale: locale) }
        static func invalidQuantity(locale: Locale = .current) -> String { L10n.string("order.error.invalid_quantity", locale: locale) }
        static func invalidQuantityFormat(locale: Locale = .current) -> String { L10n.string("order.error.invalid_quantity_format", locale: locale) }
        static func invalidNotional(locale: Locale = .current) -> String { L10n.string("order.error.invalid_notional", locale: locale) }
        static func missingLimitPrice(locale: Locale = .current) -> String { L10n.string("order.error.missing_limit_price", locale: locale) }
        static func invalidLimitPrice(locale: Locale = .current) -> String { L10n.string("order.error.invalid_limit_price", locale: locale) }
        static func invalidLimitPriceIncrement(locale: Locale = .current) -> String { L10n.string("order.error.invalid_limit_price_increment", locale: locale) }
        static func notionalRequiresDay(locale: Locale = .current) -> String { L10n.string("order.error.notional_requires_day", locale: locale) }
        static func extendedHoursRequiresLimitDayOrGTC(locale: Locale = .current) -> String { L10n.string("order.error.extended_hours_requires_limit_day_or_gtc", locale: locale) }
    }
}
