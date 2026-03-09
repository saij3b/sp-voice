import Combine
import Foundation
import os

/// Registry and router for transcription providers.
/// Handles auto-default selection, primary/secondary preference, and fallback.
@MainActor
final class ProviderManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var availableProviders: [TranscriptionProvider] = []
    @Published var primaryProviderID: ProviderID?
    @Published var secondaryProviderID: ProviderID?

    /// Model selection per provider, keyed by ProviderID raw value.
    @Published var selectedModelPerProvider: [String: String] = [:]

    // MARK: - Dependencies

    private let credentialsStore: CredentialsStoring
    private var allProviders: [TranscriptionProvider] = []

    init(credentialsStore: CredentialsStoring) {
        self.credentialsStore = credentialsStore

        // Register all known providers
        allProviders = [
            OpenAIProvider(credentialsStore: credentialsStore),
            OpenRouterProvider(credentialsStore: credentialsStore),
            GeminiProvider(credentialsStore: credentialsStore),
        ]

        loadPreferences()
        refreshAvailableProviders()
    }

    // MARK: - Provider Access

    /// Providers that have stored credentials.
    var configuredProviders: [TranscriptionProvider] {
        allProviders.filter { credentialsStore.hasCredential(for: $0.id) }
    }

    /// The active primary provider, resolved via auto-default or explicit selection.
    var activeProvider: TranscriptionProvider? {
        if let id = resolvedPrimaryID {
            return allProviders.first { $0.id == id }
        }
        return nil
    }

    /// Resolves which provider should be secondary (fallback).
    /// Uses explicit selection if set, otherwise auto-defaults to the next
    /// highest-priority configured provider after the primary.
    var resolvedSecondaryID: ProviderID? {
        // Explicit selection, still valid?
        if let explicit = secondaryProviderID,
           explicit != resolvedPrimaryID,
           credentialsStore.hasCredential(for: explicit) {
            return explicit
        }

        // Auto-default: next highest-priority configured provider after primary
        let primary = resolvedPrimaryID
        let configured = Set(credentialsStore.configuredProviders())
        return Self.priorityOrder.first { $0 != primary && configured.contains($0) }
    }

    /// The fallback provider if the primary fails.
    var fallbackProvider: TranscriptionProvider? {
        guard let secondary = resolvedSecondaryID else { return nil }
        return allProviders.first { $0.id == secondary }
    }

    /// Provider for a specific ID.
    func provider(for id: ProviderID) -> TranscriptionProvider? {
        allProviders.first { $0.id == id }
    }

    /// Selected model for a given provider, or the provider's default.
    func selectedModel(for providerID: ProviderID) -> TranscriptionModel? {
        guard let provider = provider(for: providerID) else { return nil }
        if let modelID = selectedModelPerProvider[providerID.rawValue] {
            if let resolved = provider.supportedModels.first(where: { $0.id == modelID }) {
                return resolved
            }
            // Keep using persisted selections even when the provider's live model list
            // has not been refreshed yet.
            return TranscriptionModel(
                id: modelID,
                displayName: "\(modelID) (saved)",
                provider: providerID,
                isDictationCapable: true
            )
        }
        return provider.defaultModel
    }

    // MARK: - Auto-Default Logic

    /// Priority order for auto-default selection when multiple providers are configured.
    static let priorityOrder: [ProviderID] = [.openrouter, .openai, .gemini]

    /// Resolves which provider should be primary.
    /// - If user explicitly chose one, use that (if still configured).
    /// - If one or more providers have keys, pick the highest-priority configured one.
    var resolvedPrimaryID: ProviderID? {
        // Explicit selection, still valid?
        if let explicit = primaryProviderID, credentialsStore.hasCredential(for: explicit) {
            return explicit
        }

        // Auto-default: pick the highest-priority configured provider
        let configured = Set(credentialsStore.configuredProviders())
        return Self.priorityOrder.first { configured.contains($0) }
    }

    // MARK: - Refresh

    func refreshAvailableProviders() {
        availableProviders = configuredProviders
        objectWillChange.send()
    }

    // MARK: - Persistence

    func setPrimary(_ id: ProviderID?) {
        primaryProviderID = id
        if let id {
            UserDefaults.standard.set(id.rawValue, forKey: SPVoiceConstants.UserDefaultsKeys.selectedPrimaryProvider)
        } else {
            UserDefaults.standard.removeObject(forKey: SPVoiceConstants.UserDefaultsKeys.selectedPrimaryProvider)
        }
        Logger.provider.info("Primary provider set to: \(id?.rawValue ?? "none", privacy: .public)")
    }

    func setSecondary(_ id: ProviderID?) {
        secondaryProviderID = id
        if let id {
            UserDefaults.standard.set(id.rawValue, forKey: SPVoiceConstants.UserDefaultsKeys.selectedSecondaryProvider)
        } else {
            UserDefaults.standard.removeObject(forKey: SPVoiceConstants.UserDefaultsKeys.selectedSecondaryProvider)
        }
    }

    func setModel(_ modelID: String, for providerID: ProviderID) {
        selectedModelPerProvider[providerID.rawValue] = modelID
        UserDefaults.standard.set(selectedModelPerProvider, forKey: SPVoiceConstants.UserDefaultsKeys.modelPerProvider)
    }

    private func loadPreferences() {
        primaryProviderID = UserDefaults.standard.string(forKey: SPVoiceConstants.UserDefaultsKeys.selectedPrimaryProvider)
            .flatMap { ProviderID(rawValue: $0) }
        secondaryProviderID = UserDefaults.standard.string(forKey: SPVoiceConstants.UserDefaultsKeys.selectedSecondaryProvider)
            .flatMap { ProviderID(rawValue: $0) }
        selectedModelPerProvider = (UserDefaults.standard.dictionary(forKey: SPVoiceConstants.UserDefaultsKeys.modelPerProvider) as? [String: String]) ?? [:]
    }
}
