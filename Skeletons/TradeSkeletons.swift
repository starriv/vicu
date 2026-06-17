import SwiftUI

struct TradeSimpleContentSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            TradeSkeletonAmount()
                .padding(.top, 46)

            Spacer(minLength: 0)

            TradeSkeletonCapsule(width: 250, height: 20)
                .padding(.bottom, 14)

            TradeSkeletonQuickFillRow()
                .frame(height: 44)
                .padding(.bottom, 6)

            TradeSkeletonNumberPad()
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TradeSkeletonAmount: View {
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 13) {
                TradeSkeletonCapsule(width: 116, height: 76, cornerRadius: 28)
                TradeSkeletonCapsule(width: 74, height: 18)
            }
            .frame(width: proxy.size.width)
            .position(x: proxy.size.width / 2, y: 130)
        }
        .frame(height: 292)
    }
}

private struct TradeSkeletonQuickFillRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                TradeSkeletonCapsule(height: 38)
            }
        }
    }
}

private struct TradeSkeletonNumberPad: View {
    private let rows = 4
    private let columns = 3

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 10) {
                    ForEach(0..<columns, id: \.self) { _ in
                        TradeSkeletonCapsule(width: 38, height: 38, cornerRadius: 19)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                    }
                }
            }
        }
    }
}

private struct TradeSkeletonCapsule: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat?

    init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat? = nil) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius ?? height / 2, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

#Preview {
    TradeSimpleContentSkeleton()
        .padding(.horizontal, 22)
        .background(AppTheme.ColorToken.pageBackground)
}
