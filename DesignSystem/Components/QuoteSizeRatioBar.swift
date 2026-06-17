import SwiftUI

struct QuoteSizeRatioBar: View {
    let bidSize: Double?
    let askSize: Double?
    var centerText: String?
    var height: CGFloat = 18
    var spacing: CGFloat = 8
    var cornerRadius: CGFloat = 4
    var bidOpacity: Double = 0.75
    var askOpacity: Double = 0.75
    var animatesChanges = true

    var body: some View {
        GeometryReader { proxy in
            let metrics = barMetrics(totalWidth: proxy.size.width)

            HStack(spacing: spacing) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.ColorToken.positive.opacity(bidOpacity))
                    .frame(width: metrics.bidWidth)

                if let centerText {
                    Text(centerText)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(width: metrics.labelWidth)
                }

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.ColorToken.negative.opacity(askOpacity))
                    .frame(width: metrics.askWidth)
            }
            .animation(animation, value: animationKey)
        }
        .frame(height: height)
        .accessibilityLabel(accessibilityText)
    }

    private var animation: Animation? {
        animatesChanges ? .easeOut(duration: 0.14) : nil
    }

    private var animationKey: Int {
        Int((bidRatio * 250).rounded())
    }

    private var bidRatio: Double {
        let bid = max(bidSize ?? 0, 0)
        let ask = max(askSize ?? 0, 0)
        let total = bid + ask
        guard total > 0 else {
            return 0.5
        }

        return bid / total
    }

    private var accessibilityText: Text {
        Text("Bid size \(sizeText(bidSize)), ask size \(sizeText(askSize))")
    }

    private func barMetrics(totalWidth: CGFloat) -> (bidWidth: CGFloat, askWidth: CGFloat, labelWidth: CGFloat) {
        let labelWidth = centerText == nil ? 0 : min(max(totalWidth * 0.24, 88), 116)
        let gapCount: CGFloat = centerText == nil ? 1 : 2
        let barWidth = max(totalWidth - labelWidth - spacing * gapCount, 0)
        guard barWidth > 0 else {
            return (barWidth / 2, barWidth / 2, labelWidth)
        }

        let bidWidth = barWidth * CGFloat(bidRatio)
        return (bidWidth, barWidth - bidWidth, labelWidth)
    }

    private func sizeText(_ value: Double?) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
