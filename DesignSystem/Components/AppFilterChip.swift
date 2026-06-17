import SwiftUI

struct AppFilterChip: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if #available(iOS 26.0, *) {
                glassLabel
            } else {
                fallbackLabel
            }
        }
        .buttonStyle(.plain)
    }

    @available(iOS 26.0, *)
    private var glassLabel: some View {
        let glassTint: Color? = isSelected ? AppTheme.ColorToken.brand.opacity(0.94) : Color.white.opacity(0.18)

        return label
            .glassEffect(
                .regular.tint(glassTint).interactive(),
                in: .capsule
            )
            .shadow(
                color: .black.opacity(isSelected ? AppTheme.Shadow.chipSelectedOpacity : AppTheme.Shadow.chipDefaultOpacity),
                radius: AppTheme.Shadow.chipRadius,
                y: AppTheme.Shadow.chipY
            )
    }

    private var fallbackLabel: some View {
        label
            .background(
                isSelected ? AppTheme.ColorToken.brand : AppTheme.ColorToken.groupedSurface,
                in: Capsule()
            )
            .shadow(
                color: .black.opacity(isSelected ? AppTheme.Shadow.chipSelectedOpacity : AppTheme.Shadow.chipDefaultOpacity),
                radius: AppTheme.Shadow.chipRadius,
                y: AppTheme.Shadow.chipY
            )
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(AppTypography.chip)
                .foregroundStyle(isSelected ? selectedForeground : tint)
                .frame(width: 17, height: 17)

            Text(title)
                .font(AppTypography.chip)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(isSelected ? selectedForeground : .primary)
        .padding(.horizontal, 9)
        .frame(height: 40)
        .contentShape(Capsule())
    }

    private var selectedForeground: Color {
        .black
    }
}
