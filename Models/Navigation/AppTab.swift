enum AppTab: String, CaseIterable, Identifiable {
    case home
    case markets
    case orders
    case more

    var id: String { rawValue }
}
