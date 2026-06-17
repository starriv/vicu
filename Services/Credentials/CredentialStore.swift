import Foundation
import Security

protocol CredentialStore: Sendable {
    func load(environment: TradeEnvironment) throws -> AlpacaCredentials?
    func save(_ credentials: AlpacaCredentials) throws
    func delete(environment: TradeEnvironment) throws
}

enum KeychainCredentialAccessPolicy: Sendable {
    case whenUnlockedThisDeviceOnly
    case userPresenceThisDeviceOnly
}

struct KeychainCredentialStore: CredentialStore {
    private let service = "com.starriv.vicu.alpaca"
    private let accountPrefix = "alpaca-trading-api"
    private let accessPolicy: KeychainCredentialAccessPolicy

    init(accessPolicy: KeychainCredentialAccessPolicy = .whenUnlockedThisDeviceOnly) {
        self.accessPolicy = accessPolicy
    }

    func load(environment: TradeEnvironment) throws -> AlpacaCredentials? {
        try load(account: account(for: environment), environment: environment)
    }

    func save(_ credentials: AlpacaCredentials) throws {
        let account = account(for: credentials.environment)
        let data = try JSONEncoder().encode(credentials)
        let query = itemQuery(account: account)
        var updateAttributes = try protectionAttributes()
        updateAttributes[kSecValueData as String] = data
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(updateStatus)
        }

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        addQuery.merge(try protectionAttributes()) { _, new in new }
        let status = SecItemAdd(applyAccessGroup(to: addQuery) as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(retryStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    func delete(environment: TradeEnvironment) throws {
        try delete(account: account(for: environment), allowMissing: false)
    }

    private func load(account: String, environment: TradeEnvironment) throws -> AlpacaCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(applyAccessGroup(to: query) as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        let credentials = try JSONDecoder().decode(AlpacaCredentials.self, from: data)
        guard credentials.environment == environment else {
            throw KeychainError.invalidData
        }

        return credentials
    }

    private func delete(account: String, allowMissing: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(applyAccessGroup(to: query) as CFDictionary)
        if allowMissing, status == errSecItemNotFound {
            return
        }

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func account(for environment: TradeEnvironment) -> String {
        "\(accountPrefix)-\(environment.rawValue)"
    }

    private func itemQuery(account: String) -> [String: Any] {
        applyAccessGroup(to: [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ])
    }

    private func protectionAttributes() throws -> [String: Any] {
        switch accessPolicy {
        case .whenUnlockedThisDeviceOnly:
            return [
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        case .userPresenceThisDeviceOnly:
            var error: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                &error
            ) else {
                throw KeychainError.accessControlUnavailable(error?.takeRetainedValue().localizedDescription)
            }

            return [
                kSecAttrAccessControl as String: accessControl
            ]
        }
    }

    private func applyAccessGroup(to query: [String: Any]) -> [String: Any] {
        guard let accessGroup else {
            return query
        }

        var query = query
        query[kSecAttrAccessGroup as String] = accessGroup
        return query
    }

    private var accessGroup: String? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return nil
        }

        if let prefix = Bundle.main.object(forInfoDictionaryKey: "VicuAppIdentifierPrefix") as? String {
            let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedPrefix.isEmpty {
                return "\(normalizedPrefix)\(bundleIdentifier)"
            }
        }

        #if targetEnvironment(simulator)
        return "FAKETEAMID.\(bundleIdentifier)"
        #else
        return nil
        #endif
    }

}

enum KeychainError: LocalizedError {
    case invalidData
    case accessControlUnavailable(String?)
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "Keychain item is not valid credential data."
        case .accessControlUnavailable(let message):
            message ?? "Keychain access control is unavailable."
        case .unhandledStatus(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}
