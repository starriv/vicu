import Foundation

/// Deep links shared by the app and the widget extension.
///
/// `vicu://order/<id>` opens the order detail; `vicu://order/<id>?action=cancel`
/// additionally arms the cancel confirmation sheet. Cancellation always goes
/// through the in-app confirmation, never a one-tap network call from the Lock
/// Screen — a brokerage action that can move real money deserves the same
/// confirmation it gets inside the app.
enum VicuDeepLink {
    enum Destination: Equatable, Sendable {
        case orderDetail(orderID: String, symbol: String?, armsCancellation: Bool)
    }

    static let scheme = "vicu"

    static func order(orderID: String, symbol: String? = nil, armsCancellation: Bool = false) -> URL? {
        guard var components = URLComponents(string: "\(scheme)://order/\(orderID)") else {
            return nil
        }

        var queryItems: [URLQueryItem] = []
        if let symbol, !symbol.isEmpty {
            queryItems.append(URLQueryItem(name: "symbol", value: symbol))
        }
        if armsCancellation {
            queryItems.append(URLQueryItem(name: "action", value: "cancel"))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        return components.url
    }

    static func destination(for url: URL) -> Destination? {
        guard url.scheme?.lowercased() == scheme else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let orderID = url.pathComponents
            .dropFirst()
            .joined(separator: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard url.host?.lowercased() == "order", !orderID.isEmpty else {
            return nil
        }

        let symbol = queryItems.first { $0.name == "symbol" }?.value
        let armsCancellation = queryItems.contains { $0.name == "action" && $0.value?.lowercased() == "cancel" }

        return .orderDetail(orderID: orderID, symbol: symbol, armsCancellation: armsCancellation)
    }
}
