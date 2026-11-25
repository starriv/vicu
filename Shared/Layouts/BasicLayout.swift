import SwiftUI

enum BasicLayoutStyle {
    case scroll(spacing: CGFloat = AppTheme.Spacing.section)
    case form
    case list
}

struct BasicLayout<TitleAccessory: View, Content: View>: View {
    private let title: LocalizedStringKey?
    private let titleDisplayMode: NavigationBarItem.TitleDisplayMode
    private let style: BasicLayoutStyle
    private let hasTitleAccessory: Bool
    private let titleAccessory: TitleAccessory
    private let content: Content

    init(
        _ title: LocalizedStringKey,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large,
        style: BasicLayoutStyle = .scroll(),
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleDisplayMode = titleDisplayMode
        self.style = style
        self.hasTitleAccessory = TitleAccessory.self != EmptyView.self
        self.titleAccessory = titleAccessory()
        self.content = content()
    }

    var body: some View {
        contentBody
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
            .modifier(
                BasicLayoutNavigationTitleModifier(
                    title: title,
                    titleDisplayMode: titleDisplayMode
                )
            )
            .toolbar {
                if hasTitleAccessory {
                    ToolbarItem(placement: .topBarTrailing) {
                        titleAccessory
                    }
                }
            }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .list:
            content
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct BasicLayoutNavigationTitleModifier: ViewModifier {
    let title: LocalizedStringKey?
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if let title {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(titleDisplayMode)
        } else {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension BasicLayout where TitleAccessory == EmptyView {
    init(
        style: BasicLayoutStyle = .scroll(),
        @ViewBuilder content: () -> Content
    ) {
        self.title = nil
        self.titleDisplayMode = .inline
        self.style = style
        self.hasTitleAccessory = false
        self.titleAccessory = EmptyView()
        self.content = content()
    }

    init(
        _ title: LocalizedStringKey,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large,
        style: BasicLayoutStyle = .scroll(),
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title,
            titleDisplayMode: titleDisplayMode,
            style: style,
            titleAccessory: { EmptyView() },
            content: content
        )
    }
}
