import SwiftUI

enum BasicLayoutStyle {
    case scroll(spacing: CGFloat = AppTheme.Spacing.section)
    case form
    case list
}

struct BasicLayout<TitleAccessory: View, Content: View>: View {
    private let title: LocalizedStringKey?
    private let style: BasicLayoutStyle
    private let titleAccessory: TitleAccessory
    private let content: Content

    init(
        _ title: LocalizedStringKey,
        style: BasicLayoutStyle = .scroll(),
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.style = style
        self.titleAccessory = titleAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                pageTitle(title)
            }
            contentBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func pageTitle(_ title: LocalizedStringKey) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(AppTypography.pageTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

            titleAccessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
        .padding(.top, AppTheme.Spacing.pageTitleTop)
        .padding(.bottom, AppTheme.Spacing.pageTitleBottom)
    }

    @ViewBuilder
    private var contentBody: some View {
        switch style {
        case .scroll(let spacing):
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.top, AppTheme.Spacing.pageTop)
                .padding(.bottom, AppTheme.Spacing.pageBottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)

        case .form:
            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .list:
            content
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 0, for: .scrollContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension BasicLayout where TitleAccessory == EmptyView {
    init(
        style: BasicLayoutStyle = .scroll(),
        @ViewBuilder content: () -> Content
    ) {
        self.title = nil
        self.style = style
        self.titleAccessory = EmptyView()
        self.content = content()
    }

    init(
        _ title: LocalizedStringKey,
        style: BasicLayoutStyle = .scroll(),
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title,
            style: style,
            titleAccessory: { EmptyView() },
            content: content
        )
    }
}
