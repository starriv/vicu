import SwiftUI

enum AppTheme {
    enum ColorToken {
        static let brand = Color(red: 0.988, green: 0.843, blue: 0.169)
        static let brandForeground = Color(red: 0.220, green: 0.259, blue: 0.282)
        static let brandAlt = Color(red: 0.855, green: 0.706, blue: 0.000)
        static let brandDark = Color(red: 0.945, green: 0.780, blue: 0.012)
        static let positive = Color.green
        static let negative = Color.red
        static let warning = Color.orange
        static let icon = Color(.secondaryLabel)
        static let pageBackground = Color(.systemGroupedBackground)
        static let groupedSurface = Color(.secondarySystemGroupedBackground)
    }

    enum Spacing {
        static let pageHorizontal: CGFloat = 20
        static let pageTop: CGFloat = 12
        static let pageTitleTop: CGFloat = 8
        static let pageTitleBottom: CGFloat = 6
        static let pageBottom: CGFloat = 36
        static let section: CGFloat = 28
        static let group: CGFloat = 12
        static let rowVertical: CGFloat = 14
    }

    enum CornerRadius {
        static let groupedSurface: CGFloat = 18
        static let chip: CGFloat = 20
    }

    enum Shadow {
        static let chipRadius: CGFloat = 10
        static let chipY: CGFloat = 4
        static let chipSelectedOpacity: Double = 0.10
        static let chipDefaultOpacity: Double = 0.05
    }
}
