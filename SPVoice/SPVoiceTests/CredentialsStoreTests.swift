import XCTest
@testable import SPVoice

final class CredentialsStoreTests: XCTestCase {

    // Use a unique service name to avoid polluting real Keychain
    private let testService = "com.spvoice.tests.credentials.\(UUID().uuidString)"
    private var store: CredentialsStore!

    override func setUp() {
        super.setUp()
        store = CredentialsStore(service: testService)
    }

    override func tearDown() {
        // Clean up all test entries
        for provider in ProviderID.allCases {
            try? store.delete(for: provider)
        }
        super.tearDown()
    }

    // MARK: - Store & Retrieve

    func testStoreAndRetrieve() throws {
        try store.store(key: "sk-test123456", for: .openai)
        let retrieved = store.retrieve(for: .openai)
        XCTAssertEqual(retrieved, "sk-test123456")
    }

    func testRetrieveNonExistent() {
        XCTAssertNil(store.retrieve(for: .openai))
    }

    func testHasCredential() throws {
        XCTAssertFalse(store.hasCredential(for: .openai))
        try store.store(key: "sk-test123456", for: .openai)
        XCTAssertTrue(store.hasCredential(for: .openai))
    }

    // MARK: - Delete

    func testDelete() throws {
        try store.store(key: "sk-test123456", for: .openai)
        XCTAssertTrue(store.hasCredential(for: .openai))

        try store.delete(for: .openai)
        XCTAssertFalse(store.hasCredential(for: .openai))
        XCTAssertNil(store.retrieve(for: .openai))
    }

    // MARK: - Overwrite

    func testOverwrite() throws {
        try store.store(key: "sk-old123456", for: .openai)
        try store.store(key: "sk-new123456", for: .openai)
        XCTAssertEqual(store.retrieve(for: .openai), "sk-new123456")
    }

    // MARK: - Key Format Validation

    func testInvalidKeyFormatOpenAI() {
        XCTAssertThrowsError(try store.store(key: "bad-key", for: .openai)) { error in
            guard let credError = error as? CredentialsError else {
                XCTFail("Expected CredentialsError"); return
            }
            if case .invalidKeyFormat = credError { /* OK */ }
            else { XCTFail("Expected invalidKeyFormat, got \(credError)") }
        }
    }

    func testInvalidKeyFormatOpenRouter() {
        XCTAssertThrowsError(try store.store(key: "sk-notright", for: .openrouter)) { error in
            guard let credError = error as? CredentialsError else {
                XCTFail("Expected CredentialsError"); return
            }
            if case .invalidKeyFormat = credError { /* OK */ }
            else { XCTFail("Expected invalidKeyFormat") }
        }
    }

    func testGeminiAcceptsAnyFormat() throws {
        // Gemini has no prefix hint — any non-empty key should be accepted
        try store.store(key: "any-key-format", for: .gemini)
        XCTAssertEqual(store.retrieve(for: .gemini), "any-key-format")
    }

    // MARK: - Configured Providers

    func testConfiguredProviders() throws {
        XCTAssertTrue(store.configuredProviders().isEmpty)

        try store.store(key: "sk-test123456", for: .openai)
        try store.store(key: "some-gemini-key", for: .gemini)

        let configured = store.configuredProviders()
        XCTAssertEqual(configured.count, 2)
        XCTAssertTrue(configured.contains(.openai))
        XCTAssertTrue(configured.contains(.gemini))
    }

    // MARK: - Isolation

    func testProviderIsolation() throws {
        try store.store(key: "sk-openaikey", for: .openai)
        try store.store(key: "gemini-key", for: .gemini)

        XCTAssertEqual(store.retrieve(for: .openai), "sk-openaikey")
        XCTAssertEqual(store.retrieve(for: .gemini), "gemini-key")
        XCTAssertNil(store.retrieve(for: .openrouter))

        try store.delete(for: .openai)
        XCTAssertNil(store.retrieve(for: .openai))
        XCTAssertEqual(store.retrieve(for: .gemini), "gemini-key")
    }
}
