import SwiftUI

enum AppTypography {
    static let pageTitle = Font.largeTitle.weight(.bold)

    static let heroLabel = Font.subheadline.weight(.semibold)
    static let heroValue = Font.largeTitle.weight(.semibold).monospacedDigit()
    static let heroDelta = Font.callout.weight(.semibold).monospacedDigit()

    static let sectionHeader = Font.subheadline.weight(.semibold)
    static let rowTitle = Font.body
    static let rowValue = Font.body.weight(.semibold).monospacedDigit()
    static let rowMeta = Font.subheadline

    static let control = Font.subheadline.weight(.semibold)
    static let chip = Font.footnote.weight(.semibold)
    static let badge = Font.caption.weight(.medium)
    static let caption = Font.caption
    static let detail = Font.footnote
    static let description = Font.callout
    static let emptyIcon = Font.title.weight(.regular)

    static let secondaryLineSpacing: CGFloat = 2
}
