import Foundation
import Security

/// Low-level Keychain Services wrapper. CredentialsStore uses this.
enum KeychainHelper {

    enum KeychainError: Error, LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case dataConversionError

        var errorDescription: String? {
            switch self {
            case .duplicateItem: return "Keychain item already exists"
            case .itemNotFound: return "Keychain item not found"
            case .unexpectedStatus(let s): return "Keychain error: \(s)"
            case .dataConversionError: return "Could not convert keychain data"
            }
        }
    }

    // MARK: - CRUD

    static func save(service: String, account: String, data: Data) throws {
        // Use Data Protection keychain — no per-app password prompts
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecUseDataProtectionKeychain: true,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Update existing
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecUseDataProtectionKeychain: true,
            ]
            let attributes: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func load(service: String, account: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            // Fall back to legacy keychain for keys stored before migration
            return try loadLegacy(service: service, account: account)
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.dataConversionError
        }
        return data
    }

    /// Read from legacy (non-Data-Protection) keychain for backward compat.
    private static func loadLegacy(service: String, account: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.dataConversionError
        }
        return data
    }

    static func delete(service: String, account: String) throws {
        // Delete from Data Protection keychain
        let dpQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
        SecItemDelete(dpQuery as CFDictionary)

        // Also delete from legacy keychain
        let legacyQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(legacyQuery as CFDictionary)
    }

    static func exists(service: String, account: String) -> Bool {
        // Check Data Protection keychain first
        let dpQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        if SecItemCopyMatching(dpQuery as CFDictionary, nil) == errSecSuccess {
            return true
        }

        // Fall back to legacy keychain
        let legacyQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(legacyQuery as CFDictionary, nil) == errSecSuccess
    }
}
