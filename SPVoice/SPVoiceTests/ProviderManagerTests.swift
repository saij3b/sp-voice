import XCTest
@testable import SPVoice

@MainActor
final class ProviderManagerTests: XCTestCase {

    var mockCredentials: MockCredentialsStore!

    override func setUp() {
        super.setUp()
        mockCredentials = MockCredentialsStore()
        // Clear UserDefaults test keys
        UserDefaults.standard.removeObject(forKey: SPVoiceConstants.UserDefaultsKeys.selectedPrimaryProvider)
        UserDefaults.standard.removeObject(forKey: SPVoiceConstants.UserDefaultsKeys.selectedSecondaryProvider)
        UserDefaults.standard.removeObject(forKey: SPVoiceConstants.UserDefaultsKeys.modelPerProvider)
    }

    override func tearDown() {
        mockCredentials.reset()
        UserDefaults.standard.removeObject(forKey: SPVoiceConstants.UserDefaultsKeys.selectedPrimaryProvider)
        UserDefaults.standard.removeObject(forKey: SPVoiceConstants.UserDefaultsKeys.selectedSecondaryProvider)
        UserDefaults.standard.removeObject(forKey: SPVoiceConstants.UserDefaultsKeys.modelPerProvider)
        super.tearDown()
    }

    // MARK: - Auto-Default

    func testAutoDefaultSingleProvider() throws {
        try mockCredentials.store(key: "sk-test123", for: .openai)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        XCTAssertEqual(manager.resolvedPrimaryID, .openai, "Single configured provider should auto-default")
    }

    func testAutoDefaultNoProviders() {
        let manager = ProviderManager(credentialsStore: mockCredentials)
        XCTAssertNil(manager.resolvedPrimaryID, "No configured providers → nil resolved primary")
    }

    func testAutoDefaultMultipleProviders() throws {
        try mockCredentials.store(key: "sk-test123", for: .openai)
        try mockCredentials.store(key: "sk-or-test", for: .openrouter)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        XCTAssertEqual(manager.resolvedPrimaryID, .openrouter, "OpenRouter has highest auto-default priority")
    }

    func testAutoDefaultPriorityOrder() throws {
        // Only OpenAI and Gemini configured → OpenAI wins (higher priority than Gemini)
        try mockCredentials.store(key: "sk-test123", for: .openai)
        try mockCredentials.store(key: "gemini-key", for: .gemini)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        XCTAssertEqual(manager.resolvedPrimaryID, .openai, "OpenAI has higher priority than Gemini")
    }

    func testAutoSecondaryDefaultsToOpenAI() throws {
        try mockCredentials.store(key: "sk-test123", for: .openai)
        try mockCredentials.store(key: "sk-or-test", for: .openrouter)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        // No explicit secondary set — should auto-default to OpenAI
        XCTAssertEqual(manager.resolvedSecondaryID, .openai, "Auto-secondary should be OpenAI when OpenRouter is primary")
        XCTAssertEqual(manager.fallbackProvider?.id, .openai)
    }

    func testAutoSecondaryNilWhenOnlyOneConfigured() throws {
        try mockCredentials.store(key: "sk-or-test", for: .openrouter)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        XCTAssertNil(manager.resolvedSecondaryID, "No secondary when only one provider configured")
    }

    // MARK: - Explicit Selection

    func testExplicitPrimaryOverridesAutoDefault() throws {
        try mockCredentials.store(key: "sk-test123", for: .openai)
        try mockCredentials.store(key: "sk-or-test", for: .openrouter)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        manager.setPrimary(.openrouter)
        XCTAssertEqual(manager.resolvedPrimaryID, .openrouter)
    }

    func testExplicitPrimaryWithMissingCredentialFallsBack() throws {
        try mockCredentials.store(key: "sk-test123", for: .openai)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        // Set primary to a provider without credentials
        manager.setPrimary(.gemini)
        // Should auto-default to the only configured one
        XCTAssertEqual(manager.resolvedPrimaryID, .openai)
    }

    // MARK: - Fallback

    func testFallbackProviderWithExplicitSelection() throws {
        try mockCredentials.store(key: "sk-test123", for: .openai)
        try mockCredentials.store(key: "sk-or-test", for: .openrouter)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        manager.setPrimary(.openai)
        manager.setSecondary(.openrouter)

        XCTAssertNotNil(manager.fallbackProvider)
        XCTAssertEqual(manager.fallbackProvider?.id, .openrouter)
    }

    func testFallbackProviderNilWhenExplicitSameAsPrimary() throws {
        try mockCredentials.store(key: "sk-test123", for: .openai)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        manager.setPrimary(.openai)
        manager.setSecondary(.openai)

        XCTAssertNil(manager.fallbackProvider, "Fallback should be nil when same as primary")
    }

    // MARK: - Model Selection

    func testDefaultModelSelection() throws {
        try mockCredentials.store(key: "sk-test123", for: .openai)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        let model = manager.selectedModel(for: .openai)
        XCTAssertNotNil(model)
        XCTAssertTrue(model!.isDictationCapable, "Default OpenAI model should be dictation-capable")
    }

    func testCustomModelSelection() throws {
        try mockCredentials.store(key: "sk-test123", for: .openai)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        let provider = manager.provider(for: .openai)!
        let models = provider.supportedModels
        guard models.count > 1 else { return } // Skip if only one model

        let altModel = models[1]
        manager.setModel(altModel.id, for: .openai)
        XCTAssertEqual(manager.selectedModel(for: .openai)?.id, altModel.id)
    }

    func testSavedModelSelectionPersistsWhenProviderListIsMissingModel() throws {
        try mockCredentials.store(key: "sk-or-test", for: .openrouter)
        let manager = ProviderManager(credentialsStore: mockCredentials)

        let savedModelID = "acme/audio-transcribe-v1"
        manager.setModel(savedModelID, for: .openrouter)

        let resolved = manager.selectedModel(for: .openrouter)
        XCTAssertEqual(resolved?.id, savedModelID)
        XCTAssertEqual(resolved?.displayName, "\(savedModelID) (saved)")
    }

    // MARK: - Configured Providers

    func testConfiguredProviders() throws {
        let manager = ProviderManager(credentialsStore: mockCredentials)
        XCTAssertTrue(manager.configuredProviders.isEmpty)

        try mockCredentials.store(key: "sk-test123", for: .openai)
        manager.refreshAvailableProviders()
        XCTAssertEqual(manager.configuredProviders.count, 1)
        XCTAssertEqual(manager.configuredProviders.first?.id, .openai)
    }

    // MARK: - Provider Lookup

    func testProviderForID() {
        let manager = ProviderManager(credentialsStore: mockCredentials)

        XCTAssertNotNil(manager.provider(for: .openai))
        XCTAssertNotNil(manager.provider(for: .openrouter))
        XCTAssertNotNil(manager.provider(for: .gemini))
        XCTAssertEqual(manager.provider(for: .openai)?.id, .openai)
    }

    func testProviderCapabilities() {
        let manager = ProviderManager(credentialsStore: mockCredentials)

        XCTAssertTrue(manager.provider(for: .openai)!.capabilities.isDictationReady)
        XCTAssertFalse(manager.provider(for: .openrouter)!.capabilities.isDictationReady)
        XCTAssertFalse(manager.provider(for: .gemini)!.capabilities.isDictationReady)
    }
}
