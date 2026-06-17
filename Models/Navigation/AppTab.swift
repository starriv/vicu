enum AppTab: String, CaseIterable, Identifiable {
    case home
    case markets
    case search
    case orders
    case more

    var id: String { rawValue }
}
