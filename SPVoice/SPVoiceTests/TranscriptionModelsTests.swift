import XCTest
@testable import SPVoice

final class TranscriptionModelsTests: XCTestCase {

    // MARK: - ProviderID

    func testProviderIDAllCases() {
        XCTAssertEqual(ProviderID.allCases.count, 3)
        XCTAssertEqual(ProviderID.openai.rawValue, "openai")
        XCTAssertEqual(ProviderID.openrouter.rawValue, "openrouter")
        XCTAssertEqual(ProviderID.gemini.rawValue, "gemini")
    }

    func testProviderIDDisplayName() {
        XCTAssertEqual(ProviderID.openai.displayName, "OpenAI")
        XCTAssertEqual(ProviderID.openrouter.displayName, "OpenRouter")
        XCTAssertEqual(ProviderID.gemini.displayName, "Gemini")
    }

    func testProviderIDKeyPrefixHint() {
        XCTAssertEqual(ProviderID.openai.keyPrefixHint, "sk-")
        XCTAssertEqual(ProviderID.openrouter.keyPrefixHint, "sk-or-")
        XCTAssertNil(ProviderID.gemini.keyPrefixHint)
    }

    // MARK: - TranscriptionModel

    func testModelEquality() {
        let model1 = TranscriptionModel(id: "test", displayName: "Test", provider: .openai, isDictationCapable: true)
        let model2 = TranscriptionModel(id: "test", displayName: "Different Name", provider: .openai, isDictationCapable: false)
        let model3 = TranscriptionModel(id: "test", displayName: "Test", provider: .gemini, isDictationCapable: true)

        XCTAssertEqual(model1, model2, "Equality should be based on id + provider only")
        XCTAssertNotEqual(model1, model3, "Different provider should not be equal")
    }

    func testModelDictationCapableFlag() {
        let capable = TranscriptionModel(id: "a", displayName: "A", provider: .openai, isDictationCapable: true)
        let notCapable = TranscriptionModel(id: "b", displayName: "B", provider: .openrouter, isDictationCapable: false)

        XCTAssertTrue(capable.isDictationCapable)
        XCTAssertFalse(notCapable.isDictationCapable)
    }

    // MARK: - ProviderCapabilities

    func testOpenAICapabilities() {
        let caps = ProviderCapabilities.openAI
        XCTAssertTrue(caps.hasDedicatedTranscriptionEndpoint)
        XCTAssertTrue(caps.isDictationReady)
        XCTAssertTrue(caps.supportsTranscriptionPrompt)
        XCTAssertTrue(caps.supportsLanguageHint)
        XCTAssertEqual(caps.maxAudioFileSizeMB, 25)
        XCTAssertNil(caps.caveatNote)
    }

    func testOpenRouterCapabilities() {
        let caps = ProviderCapabilities.openRouter
        XCTAssertFalse(caps.hasDedicatedTranscriptionEndpoint)
        XCTAssertFalse(caps.isDictationReady)
        XCTAssertTrue(caps.supportsAudioViaChatCompletion)
        XCTAssertNotNil(caps.caveatNote)
    }

    func testGeminiCapabilities() {
        let caps = ProviderCapabilities.gemini
        XCTAssertFalse(caps.hasDedicatedTranscriptionEndpoint)
        XCTAssertFalse(caps.isDictationReady)
        XCTAssertTrue(caps.supportsAudioViaChatCompletion)
        XCTAssertNotNil(caps.caveatNote)
    }

    // MARK: - DictationState

    func testDictationStateIsActive() {
        XCTAssertFalse(DictationState.idle.isActive)
        XCTAssertTrue(DictationState.listening.isActive)
        XCTAssertTrue(DictationState.transcribing.isActive)
        XCTAssertTrue(DictationState.processing.isActive)
        XCTAssertTrue(DictationState.inserting.isActive)
        XCTAssertFalse(DictationState.success(preview: "test").isActive)
        XCTAssertFalse(DictationState.error(message: "err").isActive)
    }

    // MARK: - ProviderError

    func testProviderErrorDescriptions() {
        XCTAssertEqual(ProviderError.invalidCredentials.errorDescription, "Invalid API key")
        XCTAssertEqual(ProviderError.providerNotConfigured.errorDescription, "No provider configured")
        XCTAssertTrue(ProviderError.rateLimited(retryAfterSeconds: 30).errorDescription?.contains("30") ?? false)
        XCTAssertTrue(ProviderError.serverError(statusCode: 500, message: "fail").errorDescription?.contains("500") ?? false)
    }

    // MARK: - HotkeyMode

    func testHotkeyModeAllCases() {
        XCTAssertEqual(HotkeyMode.allCases.count, 2)
        XCTAssertEqual(HotkeyMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(HotkeyMode.toggleToTalk.rawValue, "toggleToTalk")
    }

    // MARK: - TextProcessingMode

    func testTextProcessingModeAllCases() {
        XCTAssertEqual(TextProcessingMode.allCases.count, 4)
        XCTAssertEqual(TextProcessingMode.rawDictation.displayName, "Raw Dictation")
    }
}
