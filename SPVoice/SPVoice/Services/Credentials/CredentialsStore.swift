import Foundation
import os

// MARK: - Protocol

protocol CredentialsStoring {
    func store(key: String, for provider: ProviderID) throws
    func retrieve(for provider: ProviderID) -> String?
    func delete(for provider: ProviderID) throws
    func hasCredential(for provider: ProviderID) -> Bool
    func configuredProviders() -> [ProviderID]
}

// MARK: - Keychain-backed Implementation

final class CredentialsStore: CredentialsStoring {

    private let service: String

    init(service: String = SPVoiceConstants.keychainService) {
        self.service = service
    }

    func store(key: String, for provider: ProviderID) throws {
        // Trim whitespace/newlines — pasted keys often have trailing characters
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = trimmedKey.data(using: .utf8) else {
            throw CredentialsError.encodingFailed
        }

        // Lightweight format validation
        if let prefix = provider.keyPrefixHint {
            guard trimmedKey.hasPrefix(prefix) else {
                throw CredentialsError.invalidKeyFormat(
                    hint: "Key should start with \"\(prefix)\""
                )
            }
        }

        try KeychainHelper.save(service: service, account: provider.rawValue, data: data)
        Logger.credentials.info("Stored credential for \(provider.rawValue, privacy: .public)")
    }

    func retrieve(for provider: ProviderID) -> String? {
        guard let data = try? KeychainHelper.load(service: service, account: provider.rawValue),
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return key
    }

    func delete(for provider: ProviderID) throws {
        try KeychainHelper.delete(service: service, account: provider.rawValue)
        Logger.credentials.info("Deleted credential for \(provider.rawValue, privacy: .public)")
    }

    func hasCredential(for provider: ProviderID) -> Bool {
        KeychainHelper.exists(service: service, account: provider.rawValue)
    }

    func configuredProviders() -> [ProviderID] {
        ProviderID.allCases.filter { hasCredential(for: $0) }
    }
}

// MARK: - Errors

enum CredentialsError: Error, LocalizedError {
    case encodingFailed
    case invalidKeyFormat(hint: String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode API key"
        case .invalidKeyFormat(let hint): return "Invalid key format: \(hint)"
        }
    }
}
