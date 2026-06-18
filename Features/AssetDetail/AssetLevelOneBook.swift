import SwiftUI

struct AssetLevelOneBook: View {
    let bidPrice: Double?
    let askPrice: Double?
    let bidSize: Double?
    let askSize: Double?
    let bidExchange: String?
    let askExchange: String?
    let spread: Double?
    let quoteTime: String?
    let showHistory: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            AssetLevelOneQuoteContent(
                bidPrice: bidPrice,
                askPrice: askPrice,
                bidSize: bidSize,
                askSize: askSize,
                spread: spread,
                sizeUnit: "shares"
            )

            HStack {
                Text("Indicative quote")
                Spacer()
                Text(AssetQuoteTimeFormatter.shortTime(quoteTime) ?? AppFormatter.placeholder)

                Button(action: showHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(.thinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(Color(.separator).opacity(0.18))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quote history")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AssetLevelOneQuoteContent: View {
    let bidPrice: Double?
    let askPrice: Double?
    let bidSize: Double?
    let askSize: Double?
    let spread: Double?
    let sizeUnit: String
    let priceFormatter: (Double?) -> String

    init(
        bidPrice: Double?,
        askPrice: Double?,
        bidSize: Double?,
        askSize: Double?,
        spread: Double?,
        sizeUnit: String = "shares",
        priceFormatter: @escaping (Double?) -> String = { AppFormatter.money($0) }
    ) {
        self.bidPrice = bidPrice
        self.askPrice = askPrice
        self.bidSize = bidSize
        self.askSize = askSize
        self.spread = spread
        self.sizeUnit = sizeUnit
        self.priceFormatter = priceFormatter
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AssetBookQuoteSide(
                title: "Bid",
                price: bidPrice,
                size: bidSize,
                sizeUnit: sizeUnit,
                priceFormatter: priceFormatter,
                alignment: .leading,
                tint: AppTheme.ColorToken.positive
            )

            AssetOrderSizeBalance(
                bidSize: bidSize,
                askSize: askSize,
                spread: spread,
                priceFormatter: priceFormatter
            )
            .frame(width: 92)

            AssetBookQuoteSide(
                title: "Ask",
                price: askPrice,
                size: askSize,
                sizeUnit: sizeUnit,
                priceFormatter: priceFormatter,
                alignment: .trailing,
                tint: AppTheme.ColorToken.negative
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AssetBookQuoteSide: View {
    enum AlignmentMode {
        case leading
        case trailing
    }

    let title: String
    let price: Double?
    let size: Double?
    let sizeUnit: String
    let priceFormatter: (Double?) -> String
    let alignment: AlignmentMode
    let tint: Color

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 5) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)

            Text(priceFormatter(price))
                .font(.callout.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text("\(AssetQuoteNumber.format(size)) \(sizeUnit)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var horizontalAlignment: HorizontalAlignment {
        alignment == .leading ? .leading : .trailing
    }

    private var frameAlignment: Alignment {
        alignment == .leading ? .leading : .trailing
    }
}

private struct AssetOrderSizeBalance: View {
    let bidSize: Double?
    let askSize: Double?
    let spread: Double?
    let priceFormatter: (Double?) -> String

    var body: some View {
        VStack(spacing: 6) {
            QuoteSizeRatioBar(
                bidSize: bidSize,
                askSize: askSize,
                height: 30,
                spacing: 2,
                cornerRadius: 3,
                bidOpacity: 0.62,
                askOpacity: 0.62
            )

            Text("Spread \(priceFormatter(spread))")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(height: 52)
    }
}

private enum AssetQuoteNumber {
    static func format(_ value: Double?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private enum AssetQuoteTimeFormatter {
    static func shortTime(_ text: String?) -> String? {
        guard let date = AlpacaDateParser.date(text) else {
            return nil
        }

        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}
