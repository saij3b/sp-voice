import Foundation
@testable import SPVoice

final class MockCredentialsStore: CredentialsStoring {

    private var storage: [ProviderID: String] = [:]

    func store(key: String, for provider: ProviderID) throws {
        storage[provider] = key
    }

    func retrieve(for provider: ProviderID) -> String? {
        storage[provider]
    }

    func delete(for provider: ProviderID) throws {
        storage.removeValue(forKey: provider)
    }

    func hasCredential(for provider: ProviderID) -> Bool {
        storage[provider] != nil
    }

    func configuredProviders() -> [ProviderID] {
        Array(storage.keys)
    }

    // Test helpers
    func reset() { storage.removeAll() }
}
