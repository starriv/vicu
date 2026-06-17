import Foundation

extension AppModel {
    func normalizedMarketSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
