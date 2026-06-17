import SwiftUI

struct AppMetricRow: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .frame(width: 30)
                .foregroundStyle(AppTheme.ColorToken.icon)

            Text(title)
                .font(AppTypography.rowTitle)

            Spacer()

            Text(value)
                .font(AppTypography.rowValue)
        }
        .padding(.vertical, AppTheme.Spacing.rowVertical)
    }
}
