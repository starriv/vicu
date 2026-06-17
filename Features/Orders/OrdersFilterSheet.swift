import SwiftUI

struct OrdersFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @Binding private var criteria: OrdersFilterCriteria
    @State private var draft: OrdersFilterCriteria

    let orders: [AlpacaOrder]
    let availableSymbols: [String]

    private let compactColumns = [
        GridItem(.adaptive(minimum: 92), spacing: 8)
    ]

    private var draftResultCount: Int {
        draft.filteredOrders(from: orders).count
    }

    init(criteria: Binding<OrdersFilterCriteria>, orders: [AlpacaOrder], availableSymbols: [String]) {
        _criteria = criteria
        _draft = State(initialValue: criteria.wrappedValue)
        self.orders = orders
        self.availableSymbols = availableSymbols
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sideSection
                    statusSection
                    timeSection
                    symbolSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollContentBackground(.hidden)
        }
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 58, height: 5)
                .padding(.top, 10)

            HStack(alignment: .center) {
                Button(L10n.Orders.filterReset(locale: locale)) {
                    withAnimation(.snappy) {
                        draft = OrdersFilterCriteria()
                    }
                }
                .font(AppTypography.control)
                .foregroundStyle(draft.isDefault ? Color(.tertiaryLabel) : AppTheme.ColorToken.brand)
                .disabled(draft.isDefault)

                Spacer(minLength: 12)

                VStack(spacing: 2) {
                    Text(L10n.Orders.filterTitle(locale: locale))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(draftResultCount) / \(orders.count)")
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button(L10n.Orders.filterApply(locale: locale)) {
                    criteria = draft.normalized()
                    dismiss()
                }
                .font(AppTypography.control)
                .foregroundStyle(AppTheme.ColorToken.brand)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var statusSection: some View {
        CompactFilterSection(title: L10n.Orders.filterStatus(locale: locale)) {
            LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
                ForEach(OrderStatusFilter.allCases) { filter in
                    CompactFilterChip(
                        title: filter.title(locale: locale),
                        systemImage: filter.systemImage,
                        isSelected: draft.status == filter
                    ) {
                        withAnimation(.snappy) {
                            draft.status = filter
                        }
                    }
                }
            }
        }
    }

    private var timeSection: some View {
        CompactFilterSection(title: L10n.Orders.filterTime(locale: locale)) {
            VStack(spacing: 10) {
                LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
                    ForEach(OrderTimeFilter.allCases) { filter in
                        CompactFilterChip(
                            title: filter.title(locale: locale),
                            isSelected: draft.timeRange == filter
                        ) {
                            withAnimation(.snappy) {
                                draft.timeRange = filter
                            }
                        }
                    }
                }

                if draft.timeRange == .custom {
                    VStack(spacing: 8) {
                        compactDatePicker(
                            title: L10n.Orders.filterStartDate(locale: locale),
                            selection: $draft.customStartDate
                        )
                        .onChange(of: draft.customStartDate) { _, newValue in
                            if newValue > draft.customEndDate {
                                draft.customEndDate = newValue
                            }
                        }

                        compactDatePicker(
                            title: L10n.Orders.filterEndDate(locale: locale),
                            selection: $draft.customEndDate
                        )
                        .onChange(of: draft.customEndDate) { _, newValue in
                            if newValue < draft.customStartDate {
                                draft.customStartDate = newValue
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var symbolSection: some View {
        CompactFilterSection(title: L10n.Orders.filterSymbols(locale: locale), style: .plain) {
            if availableSymbols.isEmpty {
                Text(L10n.Orders.filterNoSymbols(locale: locale))
                    .font(AppTypography.rowMeta)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                SymbolFilterDropdown(
                    availableSymbols: availableSymbols,
                    selectedSymbols: $draft.symbols
                )
            }
        }
    }

    private var sideSection: some View {
        CompactFilterSection(title: L10n.Orders.filterSide(locale: locale), style: .plain) {
            Picker(L10n.Orders.filterSide(locale: locale), selection: $draft.side) {
                ForEach(OrderSideFilter.allCases) { filter in
                    Text(filter.title(locale: locale))
                        .tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
        }
    }

    private func compactDatePicker(title: String, selection: Binding<Date>) -> some View {
        DatePicker(title, selection: selection, displayedComponents: .date)
            .font(AppTypography.rowMeta)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

}

private enum CompactFilterSectionStyle {
    case card
    case plain
}

private struct CompactFilterSection<Content: View>: View {
    let title: String
    let style: CompactFilterSectionStyle
    let content: Content

    init(
        title: String,
        style: CompactFilterSectionStyle = .card,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(.secondary)

            sectionContent
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch style {
        case .card:
            content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .plain:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SymbolFilterDropdown: View {
    @Environment(\.locale) private var locale
    @Binding var selectedSymbols: Set<String>
    let availableSymbols: [String]

    @State private var isExpanded = false
    @State private var query = ""

    init(availableSymbols: [String], selectedSymbols: Binding<Set<String>>) {
        self.availableSymbols = availableSymbols
        _selectedSymbols = selectedSymbols
    }

    private var filteredSymbols: [String] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedQuery.isEmpty else {
            return availableSymbols
        }

        return availableSymbols.filter { $0.uppercased().contains(normalizedQuery) }
    }

    private var summary: String {
        guard !selectedSymbols.isEmpty else {
            return L10n.Orders.filterAllSymbols(locale: locale)
        }

        let selectedAvailableSymbols = availableSymbols.filter { selectedSymbols.contains($0) }
        if selectedAvailableSymbols.count == 1, let symbol = selectedAvailableSymbols.first {
            return symbol
        }

        return L10n.Orders.filterSymbolSelectionCount(selectedSymbols.count, locale: locale)
    }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)

                    Text(summary)
                        .font(AppTypography.control)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.18))
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                VStack(spacing: 8) {
                    searchField
                    symbolList
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                "",
                text: $query,
                prompt: Text(L10n.Orders.filterSymbolSearchPlaceholder(locale: locale))
                    .foregroundStyle(.secondary)
            )
            .font(AppTypography.rowMeta)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Common.clear)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var symbolList: some View {
        VStack(spacing: 0) {
            symbolRow(
                title: L10n.Orders.filterAllSymbols(locale: locale),
                isSelected: selectedSymbols.isEmpty
            ) {
                withAnimation(.snappy(duration: 0.16)) {
                    selectedSymbols.removeAll()
                }
            }

            Divider()
                .padding(.leading, 44)

            if filteredSymbols.isEmpty {
                Text(L10n.Orders.filterSymbolNoMatches(locale: locale))
                    .font(AppTypography.rowMeta)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSymbols, id: \.self) { symbol in
                            symbolRow(
                                title: symbol,
                                isSelected: selectedSymbols.contains(symbol)
                            ) {
                                withAnimation(.snappy(duration: 0.16)) {
                                    toggleSymbol(symbol)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 210)
                .scrollIndicators(.visible)
            }
        }
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.18))
        }
    }

    private func symbolRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.ColorToken.brand : .secondary)
                    .frame(width: 22)

                Text(title)
                    .font(AppTypography.rowMeta.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggleSymbol(_ symbol: String) {
        if selectedSymbols.contains(symbol) {
            selectedSymbols.remove(symbol)
        } else {
            selectedSymbols.insert(symbol)
        }
    }
}

private struct CompactFilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 16, height: 16)
                }

                Text(title)
                    .font(AppTypography.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AppTheme.ColorToken.brandForeground : .primary)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(chipBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(chipBorder)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var chipBackground: Color {
        isSelected ? AppTheme.ColorToken.brand : Color(.tertiarySystemGroupedBackground)
    }

    private var chipBorder: Color {
        isSelected ? AppTheme.ColorToken.brand.opacity(0.2) : Color(.separator).opacity(0.25)
    }
}
