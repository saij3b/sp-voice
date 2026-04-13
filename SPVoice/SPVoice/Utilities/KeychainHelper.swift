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

    /// Build a SecAccess that lets any application read this item without a password prompt.
    /// Passing an empty array to SecAccessCreate means "any app is trusted".
    private static func makeOpenAccess(label: String) -> SecAccess? {
        var access: SecAccess?
        let status = SecAccessCreate(label as CFString, [] as CFArray, &access)
        return status == errSecSuccess ? access : nil
    }

    static func save(service: String, account: String, data: Data) throws {
        // Delete any existing item first so we can recreate it with the open access policy.
        // This avoids the "wrong ACL owner" prompt that occurs after re-signing.
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)   // ignore errors — item may not exist

        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
        ]

        // Attach the open-access policy so no password dialog appears.
        if let access = makeOpenAccess(label: service) {
            query[kSecAttrAccess] = access
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
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
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func exists(service: String, account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
