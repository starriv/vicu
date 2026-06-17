import SwiftUI
import UIKit

struct AppCopyableIdentifier: View {
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.locale) private var locale

    let value: String
    var displayValue: String?
    var copyLabel: LocalizedStringKey = L10n.Common.copy
    var accessibilityLabel: LocalizedStringKey?

    var body: some View {
        copyableContent
            .contextMenu {
                Button(action: copy) {
                    Label(copyLabel, systemImage: "doc.on.doc")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel ?? copyLabel)
            .accessibilityValue(value)
            .accessibilityHint(L10n.Common.copyToClipboardHint)
    }

    @ViewBuilder
    private var copyableContent: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.14)).interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(0.14))
                }
        }
    }

    private var content: some View {
        Text(visibleValue)
            .font(.body.monospaced())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Capsule())
    }

    private var visibleValue: String {
        AppFormatter.displayText(displayValue ?? value)
    }

    private func copy() {
        UIPasteboard.general.string = value
        toastCenter.show(L10n.Common.copiedToClipboard(locale: locale))
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 16) {
        AppCopyableIdentifier(value: "8db26a59-d2b7-4b46-9984-3a87fbb37f4b")
        AppCopyableIdentifier(value: "2d9e926c-e17c-47c3-ad8c-26c7a594e48f")
            .frame(width: 220)
    }
    .environment(AppToastCenter())
    .padding()
}
