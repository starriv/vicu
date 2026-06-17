import SwiftUI
import UIKit

struct HoldToConfirmButton: View {
    let title: String
    let progressTitle: String
    let submittingTitle: String
    let tint: Color
    let isSubmitting: Bool
    let action: () async -> Void

    @State private var progress: CGFloat = 0
    @State private var isPressing = false
    @State private var didCompletePress = false

    private let holdDuration: TimeInterval = 1.1

    var body: some View {
        buttonBody
            .frame(height: 44)
            .contentShape(Capsule())
            .onLongPressGesture(
                minimumDuration: holdDuration,
                maximumDistance: 28,
                pressing: handlePressingChanged,
                perform: completePress
            )
            .opacity(isSubmitting ? 0.72 : 1)
            .allowsHitTesting(!isSubmitting)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private var buttonBody: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint.opacity(0.10)).interactive(), in: .capsule)
                .shadow(color: tint.opacity(0.14), radius: 18, y: 7)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(tint.opacity(0.18))
                }
                .shadow(color: tint.opacity(0.16), radius: 18, y: 7)
        }
    }

    private var content: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(tint.opacity(isPressing ? 0.10 : 0.03))

            GeometryReader { proxy in
                Capsule()
                    .fill(tint.opacity(0.64))
                    .frame(width: proxy.size.width * progress)
            }
            .clipShape(Capsule())

            HStack(spacing: 9) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: isPressing ? "hand.raised.fill" : "hand.tap.fill")
                        .font(.callout.weight(.bold))
                }

                Text(labelTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(labelForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
        }
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(isPressing ? 0.24 : 0.16))
        }
        .clipShape(Capsule())
    }

    private var labelForeground: Color {
        if isSubmitting || isPressing || progress > 0.18 {
            return .white
        }

        return tint
    }

    private var labelTitle: String {
        if isSubmitting {
            return submittingTitle
        }

        return isPressing ? progressTitle : title
    }

    private func handlePressingChanged(_ pressing: Bool) {
        guard !isSubmitting else {
            return
        }

        if pressing {
            didCompletePress = false
            isPressing = true
            progress = 0
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            withAnimation(.linear(duration: holdDuration)) {
                progress = 1
            }
        } else {
            isPressing = false
            if !didCompletePress {
                withAnimation(.easeOut(duration: 0.18)) {
                    progress = 0
                }
            }
        }
    }

    private func completePress() {
        guard !isSubmitting else {
            return
        }

        didCompletePress = true
        isPressing = false
        progress = 1
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        Task {
            await action()
            withAnimation(.easeOut(duration: 0.18)) {
                progress = 0
            }
            didCompletePress = false
        }
    }
}
