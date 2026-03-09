import XCTest
@testable import SPVoice

final class TextProcessingServiceTests: XCTestCase {

    // MARK: - Raw Dictation

    func testRawDictationPassthrough() async throws {
        let result = try await TextProcessingService.process("hello world", mode: .rawDictation)
        XCTAssertEqual(result, "hello world")
    }

    // MARK: - Polished Writing

    func testPolishCapitalizesFirstLetter() {
        let result = TextProcessingService.polishText("hello world")
        XCTAssertTrue(result.hasPrefix("H"))
    }

    func testPolishAddsTrailingPeriod() {
        let result = TextProcessingService.polishText("Hello world")
        XCTAssertTrue(result.hasSuffix("."))
    }

    func testPolishPreservesExistingPunctuation() {
        let result = TextProcessingService.polishText("Is this a question?")
        XCTAssertTrue(result.hasSuffix("?"))
        XCTAssertFalse(result.hasSuffix("?."))
    }

    func testPolishRemovesFillerWords() {
        let result = TextProcessingService.polishText("um I went to uh the store")
        XCTAssertFalse(result.lowercased().contains(" um "))
        XCTAssertFalse(result.lowercased().contains(" uh "))
    }

    func testPolishCollapsesMultipleSpaces() {
        let result = TextProcessingService.polishText("hello   world")
        XCTAssertFalse(result.contains("  "))
    }

    func testPolishTrimsWhitespace() {
        let result = TextProcessingService.polishText("  hello world  ")
        XCTAssertEqual(result.first, "H")
        XCTAssertTrue(result.hasSuffix("."))
    }

    func testPolishEmptyString() {
        let result = TextProcessingService.polishText("")
        XCTAssertEqual(result, "")
    }

    func testPolishRemovesYouKnow() {
        let result = TextProcessingService.polishText("so you know it was great")
        XCTAssertFalse(result.lowercased().contains("you know"))
    }

    // MARK: - Prompt Mode (passthrough)

    func testPromptModePassthrough() async throws {
        let result = try await TextProcessingService.process("test input", mode: .promptMode)
        XCTAssertEqual(result, "test input")
    }

    // MARK: - Custom Transform (passthrough)

    func testCustomTransformPassthrough() async throws {
        let result = try await TextProcessingService.process("test input", mode: .customTransform)
        XCTAssertEqual(result, "test input")
    }

    // MARK: - Insertion Error Descriptions

    func testInsertionErrorDescriptions() {
        XCTAssertNotNil(InsertionError.accessibilityNotTrusted.errorDescription)
        XCTAssertNotNil(InsertionError.noFocusedElement.errorDescription)
        XCTAssertNotNil(InsertionError.elementNotEditable.errorDescription)
        XCTAssertNotNil(InsertionError.axInsertionFailed("test").errorDescription)
        XCTAssertNotNil(InsertionError.clipboardPasteFailed.errorDescription)
    }

    // MARK: - Provider Error Descriptions

    func testProviderErrorDescriptions() {
        XCTAssertEqual(ProviderError.invalidCredentials.errorDescription, "Invalid API key")
        XCTAssertEqual(ProviderError.networkUnavailable.errorDescription, "Network unavailable")
        XCTAssertEqual(ProviderError.timeout.errorDescription, "Transcription timed out")
        XCTAssertEqual(ProviderError.transcriptionEmpty.errorDescription, "Transcription returned empty text")
        XCTAssertNotNil(ProviderError.rateLimited(retryAfterSeconds: 30).errorDescription)
        XCTAssertNotNil(ProviderError.serverError(statusCode: 500, message: "fail").errorDescription)
    }
}
