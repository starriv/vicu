import SwiftUI

enum AppPriceTextNotation: Equatable {
    case standard
    case compact
}

struct AppPriceText: View {
    let value: Double?
    let currencyCode: String
    let fractionLength: Int
    let placeholder: String
    let font: Font
    let minimumScaleFactor: CGFloat
    let isAnimated: Bool
    let isSigned: Bool
    let notation: AppPriceTextNotation
    let usesCompactFormatting: Bool

    init(
        _ value: Double?,
        currencyCode: String = "USD",
        fractionLength: Int = 2,
        placeholder: String = AppFormatter.placeholder,
        font: Font,
        minimumScaleFactor: CGFloat = 0.8,
        isAnimated: Bool = false,
        isSigned: Bool = false,
        notation: AppPriceTextNotation = .standard,
        usesCompactFormatting: Bool = true
    ) {
        self.value = value
        self.currencyCode = currencyCode
        self.fractionLength = fractionLength
        self.placeholder = placeholder
        self.font = font
        self.minimumScaleFactor = minimumScaleFactor
        self.isAnimated = isAnimated
        self.isSigned = isSigned
        self.notation = notation
        self.usesCompactFormatting = usesCompactFormatting
    }

    init(
        _ value: String?,
        currencyCode: String = "USD",
        fractionLength: Int = 2,
        placeholder: String = AppFormatter.placeholder,
        font: Font,
        minimumScaleFactor: CGFloat = 0.8,
        isAnimated: Bool = false,
        isSigned: Bool = false,
        notation: AppPriceTextNotation = .standard,
        usesCompactFormatting: Bool = true
    ) {
        self.init(
            NumberParser.double(from: value),
            currencyCode: currencyCode,
            fractionLength: fractionLength,
            placeholder: placeholder,
            font: font,
            minimumScaleFactor: minimumScaleFactor,
            isAnimated: isAnimated,
            isSigned: isSigned,
            notation: notation,
            usesCompactFormatting: usesCompactFormatting
        )
    }

    var body: some View {
        Text(priceText)
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
            .contentTransition(isAnimated ? .numericText(value: value ?? 0) : .identity)
            .animation(isAnimated ? .snappy(duration: 0.18) : nil, value: value)
            .accessibilityLabel(accessibilityText)
    }

    private var priceText: String {
        if isSigned {
            if notation == .compact {
                return AppFormatter.signedCompactMoney(
                    value,
                    currencyCode: currencyCode,
                    standardFractionLength: fractionLength,
                    usesCompactFormatting: usesCompactFormatting,
                    placeholder: placeholder
                )
            }

            return AppFormatter.signedMoney(
                value,
                currencyCode: currencyCode,
                fractionLength: fractionLength,
                placeholder: placeholder
            )
        }

        if notation == .compact {
            return AppFormatter.compactMoney(
                value,
                currencyCode: currencyCode,
                standardFractionLength: fractionLength,
                usesCompactFormatting: usesCompactFormatting,
                placeholder: placeholder
            )
        }

        return AppFormatter.money(
            value,
            currencyCode: currencyCode,
            fractionLength: fractionLength,
            placeholder: placeholder
        )
    }

    private var accessibilityText: String {
        if isSigned {
            return AppFormatter.signedMoney(
                value,
                currencyCode: currencyCode,
                fractionLength: fractionLength,
                placeholder: placeholder
            )
        }

        return AppFormatter.money(
            value,
            currencyCode: currencyCode,
            fractionLength: fractionLength,
            placeholder: placeholder
        )
    }
}
