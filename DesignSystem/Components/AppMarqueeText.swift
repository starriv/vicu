import SwiftUI

struct AppMarqueeText: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let startDelay: Double
    let pointsPerSecond: Double
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var containerSize: CGSize = .zero
    @State private var contentSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    @State private var isRevealing = false
    @State private var revealRequestID = 0

    init(
        _ text: String,
        font: Font,
        foregroundColor: Color = .primary,
        startDelay: Double = 0.12,
        pointsPerSecond: Double = 28,
        height: CGFloat = 30
    ) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
        self.startDelay = startDelay
        self.pointsPerSecond = pointsPerSecond
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                marqueeContent

                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .background(AppMarqueeSizeReader<AppMarqueeContentSizeKey>())
            }
            .frame(width: proxy.size.width, height: height, alignment: .leading)
            .clipped()
            .onAppear {
                containerSize = proxy.size
            }
            .onChange(of: proxy.size) { _, newValue in
                containerSize = newValue
            }
            .contentShape(Rectangle())
            .onTapGesture {
                revealIfNeeded()
            }
        }
        .frame(height: height)
        .onPreferenceChange(AppMarqueeContentSizeKey.self) { contentSize = $0 }
        .task(id: animationID) {
            await animateIfNeeded()
        }
        .accessibilityLabel(text)
    }

    @ViewBuilder
    private var marqueeContent: some View {
        if shouldAnimate {
            marqueeLabel
            .offset(x: offset)
        } else {
            staticLabel
        }
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var staticLabel: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var overflowDistance: CGFloat {
        max(contentSize.width - containerSize.width, 0)
    }

    private var revealDistance: CGFloat {
        overflowDistance
    }

    private var shouldAnimate: Bool {
        isRevealing && !reduceMotion && overflowDistance > 6
    }

    private var animationID: String {
        [
            text,
            String(Int(containerSize.width.rounded())),
            String(Int(contentSize.width.rounded())),
            String(revealRequestID),
            isRevealing ? "reveal" : "idle",
            reduceMotion ? "reduce" : "motion"
        ].joined(separator: "|")
    }

    @MainActor
    private func animateIfNeeded() async {
        resetOffsetWithoutAnimation()
        guard shouldAnimate else {
            return
        }

        guard await sleep(startDelay) else { return }

        let distance = revealDistance
        guard distance > 0 else {
            isRevealing = false
            return
        }

        let scrollDuration = max(Double(distance) / pointsPerSecond, 2.4)
        withAnimation(.linear(duration: scrollDuration)) {
            offset = -distance
        }

        guard await sleep(scrollDuration + 0.7) else { return }
        isRevealing = false
        resetOffsetWithoutAnimation()
    }

    @MainActor
    private func revealIfNeeded() {
        guard !reduceMotion, overflowDistance > 6 else {
            return
        }

        revealRequestID += 1
        isRevealing = true
    }

    @MainActor
    private func resetOffsetWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = 0
        }
    }

    private func sleep(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }
}

private struct AppMarqueeSizeReader<Key: PreferenceKey>: View where Key.Value == CGSize {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: Key.self, value: proxy.size)
        }
    }
}

private struct AppMarqueeContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let nextValue = nextValue()
        guard nextValue != .zero else {
            return
        }

        value = nextValue
    }
}
