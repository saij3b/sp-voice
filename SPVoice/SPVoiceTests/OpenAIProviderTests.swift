import XCTest
@testable import SPVoice

final class OpenAIProviderTests: XCTestCase {

    var mockCredentials: MockCredentialsStore!

    override func setUp() {
        super.setUp()
        mockCredentials = MockCredentialsStore()
    }

    override func tearDown() {
        mockCredentials.reset()
        super.tearDown()
    }

    // MARK: - Provider Identity

    func testProviderID() {
        let provider = OpenAIProvider(credentialsStore: mockCredentials)
        XCTAssertEqual(provider.id, .openai)
        XCTAssertEqual(provider.displayName, "OpenAI")
        XCTAssertTrue(provider.capabilities.isDictationReady)
    }

    // MARK: - Models

    func testDefaultModelIsGPT4oTranscribe() {
        let provider = OpenAIProvider(credentialsStore: mockCredentials)
        XCTAssertEqual(provider.defaultModel.id, "gpt-4o-transcribe")
        XCTAssertTrue(provider.defaultModel.isDictationCapable)
    }

    func testSupportedModels() {
        let provider = OpenAIProvider(credentialsStore: mockCredentials)
        XCTAssertEqual(provider.supportedModels.count, 2)

        let ids = provider.supportedModels.map(\.id)
        XCTAssertTrue(ids.contains("gpt-4o-transcribe"))
        XCTAssertTrue(ids.contains("gpt-4o-mini-transcribe"))

        // All models should be dictation-capable
        XCTAssertTrue(provider.supportedModels.allSatisfy(\.isDictationCapable))
    }

    // MARK: - Credentials

    func testTranscribeWithoutCredentialsThrows() async {
        let provider = OpenAIProvider(credentialsStore: mockCredentials)
        do {
            _ = try await provider.transcribe(audioURL: URL(fileURLWithPath: "/tmp/test.wav"), model: nil, options: nil)
            XCTFail("Expected providerNotConfigured")
        } catch {
            XCTAssertEqual(error as? ProviderError, .providerNotConfigured)
        }
    }

    func testValidateWithoutCredentialsThrows() async {
        let provider = OpenAIProvider(credentialsStore: mockCredentials)
        do {
            try await provider.validateCredentials()
            XCTFail("Expected providerNotConfigured")
        } catch {
            XCTAssertEqual(error as? ProviderError, .providerNotConfigured)
        }
    }

    // MARK: - Validation with Mock Session

    func testValidateCredentialsSuccess() async throws {
        try mockCredentials.store(key: "sk-testkey123", for: .openai)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url, OpenAIClient.modelsURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-testkey123")

            let data = #"{"data":[{"id":"gpt-4o"}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let provider = OpenAIProvider(credentialsStore: mockCredentials, session: session)
        try await provider.validateCredentials()
    }

    func testValidateCredentials401() async throws {
        try mockCredentials.store(key: "sk-badkey1234", for: .openai)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.handler = { request in
            let data = #"{"error":{"message":"Invalid key"}}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let provider = OpenAIProvider(credentialsStore: mockCredentials, session: session)
        do {
            try await provider.validateCredentials()
            XCTFail("Expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? ProviderError, .invalidCredentials)
        }
    }

    // MARK: - Transcription with Mock Session

    func testTranscribeSuccess() async throws {
        try mockCredentials.store(key: "sk-testkey123", for: .openai)

        // Create a test WAV
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_provider.wav")
        try createMinimalWAV(at: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.handler = { request in
            // Verify it's a POST to the transcription endpoint
            XCTAssertEqual(request.url, OpenAIClient.transcriptionURL)
            XCTAssertEqual(request.httpMethod, "POST")

            let ct = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(ct.contains("multipart/form-data"))

            let data = #"{"text":"Hello from the test"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let provider = OpenAIProvider(credentialsStore: mockCredentials, session: session)
        let result = try await provider.transcribe(audioURL: audioURL, model: nil, options: nil)

        XCTAssertEqual(result.text, "Hello from the test")
        XCTAssertEqual(result.provider, .openai)
        XCTAssertEqual(result.model, "gpt-4o-transcribe") // default model
        XCTAssertGreaterThanOrEqual(result.latencyMs, 0)
    }

    func testTranscribeWithExplicitModel() async throws {
        try mockCredentials.store(key: "sk-testkey123", for: .openai)

        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_provider2.wav")
        try createMinimalWAV(at: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.handler = { request in
            // Check the body contains the mini model
            if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
                XCTAssertTrue(bodyStr.contains("gpt-4o-mini-transcribe"))
            }

            let data = #"{"text":"Mini result"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let provider = OpenAIProvider(credentialsStore: mockCredentials, session: session)
        let miniModel = provider.supportedModels.first { $0.id == "gpt-4o-mini-transcribe" }!
        let result = try await provider.transcribe(audioURL: audioURL, model: miniModel, options: nil)

        XCTAssertEqual(result.text, "Mini result")
        XCTAssertEqual(result.model, "gpt-4o-mini-transcribe")
    }

    // MARK: - Helpers

    private func createMinimalWAV(at url: URL) throws {
        var header = Data()
        let dataSize: UInt32 = 2
        let fileSize: UInt32 = 36 + dataSize
        header.append("RIFF".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt32(16000).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt32(32000).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) })
        header.append("data".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        header.append(Data([0, 0]))
        try header.write(to: url)
    }
}

// MARK: - Mock URLProtocol

/// Intercepts all URLSession requests for testing.
final class MockURLProtocol: URLProtocol {

    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
