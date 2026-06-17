import SwiftUI

struct AppInfiniteScrollView<LoadMoreTrigger: Equatable, Content: View, LoadingFooter: View>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat
    private let showsIndicators: Bool
    private let contentMargins: EdgeInsets
    private let canLoadMore: Bool
    private let isLoadingMore: Bool
    private let loadMoreTrigger: LoadMoreTrigger
    private let loadMore: @MainActor () async -> Void
    private let content: Content
    private let loadingFooter: LoadingFooter

    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = AppTheme.Spacing.section,
        showsIndicators: Bool = true,
        contentMargins: EdgeInsets = EdgeInsets(
            top: AppTheme.Spacing.pageTop,
            leading: AppTheme.Spacing.pageHorizontal,
            bottom: AppTheme.Spacing.pageBottom,
            trailing: AppTheme.Spacing.pageHorizontal
        ),
        canLoadMore: Bool,
        isLoadingMore: Bool,
        loadMoreTrigger: LoadMoreTrigger,
        loadMore: @MainActor @escaping () async -> Void,
        @ViewBuilder loadingFooter: () -> LoadingFooter,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.showsIndicators = showsIndicators
        self.contentMargins = contentMargins
        self.canLoadMore = canLoadMore
        self.isLoadingMore = isLoadingMore
        self.loadMoreTrigger = loadMoreTrigger
        self.loadMore = loadMore
        self.loadingFooter = loadingFooter()
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            LazyVStack(alignment: alignment, spacing: spacing) {
                content

                if canLoadMore {
                    loadingFooter
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            Task { await loadMoreIfNeeded() }
                        }
                        .task(id: loadMoreTrigger) {
                            await loadMoreIfNeeded()
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, contentMargins.top)
            .padding(.leading, contentMargins.leading)
            .padding(.bottom, contentMargins.bottom)
            .padding(.trailing, contentMargins.trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
    }

    @MainActor
    private func loadMoreIfNeeded() async {
        guard canLoadMore, !isLoadingMore else {
            return
        }

        await loadMore()
    }
}

extension AppInfiniteScrollView where LoadingFooter == AppInfiniteScrollLoadingFooter {
    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = AppTheme.Spacing.section,
        showsIndicators: Bool = true,
        contentMargins: EdgeInsets = EdgeInsets(
            top: AppTheme.Spacing.pageTop,
            leading: AppTheme.Spacing.pageHorizontal,
            bottom: AppTheme.Spacing.pageBottom,
            trailing: AppTheme.Spacing.pageHorizontal
        ),
        canLoadMore: Bool,
        isLoadingMore: Bool,
        loadMoreTrigger: LoadMoreTrigger,
        loadMore: @MainActor @escaping () async -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            spacing: spacing,
            showsIndicators: showsIndicators,
            contentMargins: contentMargins,
            canLoadMore: canLoadMore,
            isLoadingMore: isLoadingMore,
            loadMoreTrigger: loadMoreTrigger,
            loadMore: loadMore,
            loadingFooter: {
                AppInfiniteScrollLoadingFooter(isLoading: isLoadingMore)
            },
            content: content
        )
    }
}

struct AppInfiniteScrollLoadingFooter: View {
    let isLoading: Bool

    var body: some View {
        if isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.Common.loadingMore)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}
