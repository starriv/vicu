import Foundation

enum AppFormatter {
    static let placeholder = "--"
    static let compactMoneyThreshold: Double = 10_000

    private static let moneyLocale = Locale(identifier: "en_US")
    private static let compactMoneyUnits: [(divisor: Double, suffix: String)] = [
        (1_000_000_000_000, "T"),
        (1_000_000_000, "B"),
        (1_000_000, "M"),
        (1_000, "K")
    ]

    static func displayText(
        _ value: String?,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        guard let value else {
            return placeholder
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? placeholder : normalized
    }

    static func money(
        _ value: String?,
        currencyCode: String = "USD",
        fractionLength: Int = 2,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        guard let decimal = NumberParser.decimal(from: value) else {
            return placeholder
        }

        return money(decimal, currencyCode: currencyCode, fractionLength: fractionLength, placeholder: placeholder)
    }

    static func money(
        _ value: Decimal?,
        currencyCode: String = "USD",
        fractionLength: Int = 2,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        guard let value else {
            return placeholder
        }

        return money(
            NSDecimalNumber(decimal: value).doubleValue,
            currencyCode: currencyCode,
            fractionLength: fractionLength,
            placeholder: placeholder
        )
    }

    static func money(
        _ value: Double?,
        currencyCode: String = "USD",
        fractionLength: Int = 2,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        guard let value else {
            return placeholder
        }

        return value.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(fractionLength))
                .locale(moneyLocale)
        )
    }

    static func compactMoney(
        _ value: String?,
        currencyCode: String = "USD",
        fractionLength: Int = 1,
        standardFractionLength: Int = 2,
        threshold: Double = AppFormatter.compactMoneyThreshold,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        compactMoney(
            NumberParser.double(from: value),
            currencyCode: currencyCode,
            fractionLength: fractionLength,
            standardFractionLength: standardFractionLength,
            threshold: threshold,
            placeholder: placeholder
        )
    }

    static func compactMoney(
        _ value: Decimal?,
        currencyCode: String = "USD",
        fractionLength: Int = 1,
        standardFractionLength: Int = 2,
        threshold: Double = AppFormatter.compactMoneyThreshold,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        guard let value else {
            return placeholder
        }

        return compactMoney(
            NSDecimalNumber(decimal: value).doubleValue,
            currencyCode: currencyCode,
            fractionLength: fractionLength,
            standardFractionLength: standardFractionLength,
            threshold: threshold,
            placeholder: placeholder
        )
    }

    static func compactMoney(
        _ value: Double?,
        currencyCode: String = "USD",
        fractionLength: Int = 1,
        standardFractionLength: Int = 2,
        threshold: Double = AppFormatter.compactMoneyThreshold,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        guard let value else {
            return placeholder
        }

        let magnitude = abs(value)
        guard magnitude >= threshold,
              let unit = compactMoneyUnits.first(where: { magnitude >= $0.divisor }) else {
            return money(
                value,
                currencyCode: currencyCode,
                fractionLength: standardFractionLength,
                placeholder: placeholder
            )
        }

        let sign = value < 0 ? "-" : ""
        let scaledValue = magnitude / unit.divisor
        let scaledText = scaledValue.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(0...fractionLength))
                .locale(moneyLocale)
        )

        return "\(sign)\(scaledText)\(unit.suffix)"
    }

    static func signedMoney(
        _ value: Double?,
        currencyCode: String = "USD",
        fractionLength: Int = 2,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        guard let value else {
            return placeholder
        }

        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(money(value, currencyCode: currencyCode, fractionLength: fractionLength, placeholder: placeholder))"
    }

    static func signedCompactMoney(
        _ value: Double?,
        currencyCode: String = "USD",
        fractionLength: Int = 1,
        standardFractionLength: Int = 2,
        threshold: Double = AppFormatter.compactMoneyThreshold,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        guard let value else {
            return placeholder
        }

        let sign = value >= 0 ? "+" : ""
        let compactText = compactMoney(
            value,
            currencyCode: currencyCode,
            fractionLength: fractionLength,
            standardFractionLength: standardFractionLength,
            threshold: threshold,
            placeholder: placeholder
        )
        return "\(sign)\(compactText)"
    }

    static func percent(_ value: Double, fractionLength: Int = 2) -> String {
        value.formatted(.percent.precision(.fractionLength(fractionLength)))
    }

    static func signedPercent(
        _ value: Double?,
        fractionLength: Int = 2,
        placeholder: String = AppFormatter.placeholder
    ) -> String {
        guard let value else {
            return placeholder
        }

        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(percent(value, fractionLength: fractionLength))"
    }

    static func numberText(_ value: String?, placeholder: String = AppFormatter.placeholder) -> String {
        guard let value else {
            return placeholder
        }

        let normalized = NumberText.trimTrailingZeros(value)
        return normalized.isEmpty ? placeholder : normalized
    }

    static func latency(milliseconds: Int?, placeholder: String = AppFormatter.placeholder) -> String {
        guard let milliseconds else {
            return placeholder
        }

        return "\(milliseconds) ms"
    }

    static func httpStatus(_ statusCode: Int?, placeholder: String = AppFormatter.placeholder) -> String {
        guard let statusCode else {
            return placeholder
        }

        return String(statusCode)
    }

    static func time(_ date: Date?, placeholder: String = AppFormatter.placeholder) -> String {
        guard let date else {
            return placeholder
        }

        return date.formatted(date: .omitted, time: .standard)
    }
}

enum NumberParser {
    static let apiLocale = Locale(identifier: "en_US_POSIX")

    static func decimal(from text: String?) -> Decimal? {
        guard let text else {
            return nil
        }

        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return nil
        }

        return Decimal(string: cleanText, locale: apiLocale)
    }

    static func double(from text: String?) -> Double? {
        guard let text else {
            return nil
        }

        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return nil
        }

        return Double(cleanText)
    }
}

enum NumberText {
    static func trimTrailingZeros(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(".") else {
            return trimmed
        }

        let withoutZeros = trimmed.replacingOccurrences(
            of: #"0+$"#,
            with: "",
            options: .regularExpression
        )

        let normalized = withoutZeros.replacingOccurrences(
            of: #"\.$"#,
            with: "",
            options: .regularExpression
        )

        return normalized == "-0" ? "0" : normalized
    }

    static func nilIfEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
