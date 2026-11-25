import SwiftUI

struct TradeSimpleContentSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            VStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TradeSkeletonCapsule(width: 112, height: 64, cornerRadius: 18)
                    TradeSkeletonCapsule(width: 68, height: 34, cornerRadius: 10)
                }

                TradeSkeletonCapsule(width: 148, height: 32, cornerRadius: 16)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 16)

            TradeSkeletonOrderCard()
                .padding(.bottom, 12)

            TradeSkeletonQuickFillRow()
                .padding(.bottom, 10)

            TradeSkeletonCapsule(height: 48, cornerRadius: 24)
                .padding(.bottom, 8)

            TradeSkeletonNumberPad()
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TradeSkeletonOrderCard: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TradeSkeletonCapsule(width: 78, height: 14, cornerRadius: 7)
                    TradeSkeletonCapsule(width: 124, height: 12, cornerRadius: 6)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    TradeSkeletonCapsule(width: 68, height: 14, cornerRadius: 7)
                    TradeSkeletonCapsule(width: 52, height: 12, cornerRadius: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                TradeSkeletonCapsule(width: 84, height: 14, cornerRadius: 7)
                Spacer(minLength: 8)
                TradeSkeletonCapsule(width: 76, height: 14, cornerRadius: 7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TradeSkeletonQuickFillRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { _ in
                TradeSkeletonCapsule(height: 38, cornerRadius: 10)
            }
        }
    }
}

private struct TradeSkeletonNumberPad: View {
    private let rows = 4
    private let columns = 3

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 8) {
                    ForEach(0..<columns, id: \.self) { _ in
                        TradeSkeletonCapsule(width: 34, height: 34, cornerRadius: 17)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
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
        .padding(.horizontal, 20)
        .background(AppTheme.ColorToken.pageBackground)
}
