import SwiftUI

struct AppSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: LocalizedStringKey,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(.secondary)

            Spacer()

            trailing()
        }
    }
}
