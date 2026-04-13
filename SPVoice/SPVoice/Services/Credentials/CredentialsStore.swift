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

// MARK: - UserDefaults-backed Implementation (no Keychain, no password prompts)

final class CredentialsStore: CredentialsStoring {

    private let defaults = UserDefaults.standard
    private let keyPrefix = "spvoice.apikey."

    init(service: String = SPVoiceConstants.keychainService) {
        // Migrate any existing keychain entries to UserDefaults once
        migrateFromKeychainIfNeeded()
    }

    func store(key: String, for provider: ProviderID) throws {
        // Trim whitespace/newlines — pasted keys often have trailing characters
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        // Lightweight format validation
        if let prefix = provider.keyPrefixHint {
            guard trimmedKey.hasPrefix(prefix) else {
                throw CredentialsError.invalidKeyFormat(
                    hint: "Key should start with \"\(prefix)\""
                )
            }
        }

        defaults.set(trimmedKey, forKey: keyPrefix + provider.rawValue)
        Logger.credentials.info("Stored credential for \(provider.rawValue, privacy: .public)")
    }

    func retrieve(for provider: ProviderID) -> String? {
        guard let key = defaults.string(forKey: keyPrefix + provider.rawValue) else {
            return nil
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func delete(for provider: ProviderID) throws {
        defaults.removeObject(forKey: keyPrefix + provider.rawValue)
        Logger.credentials.info("Deleted credential for \(provider.rawValue, privacy: .public)")
    }

    func hasCredential(for provider: ProviderID) -> Bool {
        retrieve(for: provider) != nil
    }

    func configuredProviders() -> [ProviderID] {
        ProviderID.allCases.filter { hasCredential(for: $0) }
    }

    // MARK: - Keychain migration

    private func migrateFromKeychainIfNeeded() {
        let migrationKey = "spvoice.keychainMigrationDone"
        guard !defaults.bool(forKey: migrationKey) else { return }

        for provider in ProviderID.allCases {
            if let data = try? KeychainHelper.load(
                    service: SPVoiceConstants.keychainService,
                    account: provider.rawValue),
               let key = String(data: data, encoding: .utf8) {
                let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    defaults.set(trimmed, forKey: keyPrefix + provider.rawValue)
                    Logger.credentials.info("Migrated keychain credential for \(provider.rawValue, privacy: .public)")
                }
                try? KeychainHelper.delete(service: SPVoiceConstants.keychainService, account: provider.rawValue)
            }
        }

        defaults.set(true, forKey: migrationKey)
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
