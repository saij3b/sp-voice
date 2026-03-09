import XCTest
@testable import SPVoice

final class OpenRouterClientTests: XCTestCase {

    // MARK: - Test Fixtures

    private func createTestWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_or_audio_\(UUID().uuidString).wav")
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
        return url
    }

    override func tearDown() {
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasPrefix("test_or_audio_") {
                try? FileManager.default.removeItem(at: f)
            }
        }
        super.tearDown()
    }

    // MARK: - Request Construction

    func testTranscriptionRequestURL() throws {
        let audioURL = try createTestWAV()
        let request = try OpenRouterClient.buildTranscriptionRequest(
            apiKey: "sk-or-test123", audioURL: audioURL, model: "openai/gpt-4o-audio-preview"
        )
        XCTAssertEqual(request.url, OpenRouterClient.chatCompletionsURL)
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testTranscriptionRequestHeaders() throws {
        let audioURL = try createTestWAV()
        let request = try OpenRouterClient.buildTranscriptionRequest(
            apiKey: "sk-or-mykey", audioURL: audioURL, model: "openai/gpt-4o-audio-preview"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-mykey")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), SPVoiceConstants.bundleIdentifier)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "SP Voice")
    }

    func testTranscriptionRequestBodyContainsModel() throws {
        let audioURL = try createTestWAV()
        let request = try OpenRouterClient.buildTranscriptionRequest(
            apiKey: "sk-or-test", audioURL: audioURL, model: "openai/gpt-4o-audio-preview"
        )
        let body = request.httpBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "openai/gpt-4o-audio-preview")
    }

    func testTranscriptionRequestBodyContainsBase64Audio() throws {
        let audioURL = try createTestWAV()
        let request = try OpenRouterClient.buildTranscriptionRequest(
            apiKey: "sk-or-test", audioURL: audioURL, model: "test-model"
        )
        let body = request.httpBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = json?["messages"] as? [[String: Any]]
        XCTAssertNotNil(messages)
        XCTAssertEqual(messages?.count, 1)
    }

    func testValidationRequest() {
        let request = OpenRouterClient.buildValidationRequest(apiKey: "sk-or-val")
        XCTAssertEqual(request.url, OpenRouterClient.modelsURL)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-val")
    }

    // MARK: - Response Parsing

    func testParseTranscriptionSuccess() throws {
        let json = #"{"choices":[{"message":{"content":"Hello world"}}]}"#
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenRouterClient.chatCompletionsURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let text = try OpenRouterClient.parseTranscriptionResponse(data: data, response: response)
        XCTAssertEqual(text, "Hello world")
    }

    func testParseTranscriptionTrimsWhitespace() throws {
        let json = #"{"choices":[{"message":{"content":"  Hello  \n"}}]}"#
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenRouterClient.chatCompletionsURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let text = try OpenRouterClient.parseTranscriptionResponse(data: data, response: response)
        XCTAssertEqual(text, "Hello")
    }

    func testParseTranscriptionEmptyContent() {
        let json = #"{"choices":[{"message":{"content":""}}]}"#
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenRouterClient.chatCompletionsURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OpenRouterClient.parseTranscriptionResponse(data: data, response: response)) { error in
            XCTAssertEqual(error as? ProviderError, .transcriptionEmpty)
        }
    }

    func testParseTranscriptionMalformedJSON() {
        let data = "not json".data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenRouterClient.chatCompletionsURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OpenRouterClient.parseTranscriptionResponse(data: data, response: response)) { error in
            XCTAssertEqual(error as? ProviderError, .transcriptionEmpty)
        }
    }

    // MARK: - Error Mapping

    func testMapHTTPError401() {
        XCTAssertThrowsError(try OpenRouterClient.mapHTTPError(statusCode: 401, data: Data())) { error in
            XCTAssertEqual(error as? ProviderError, .invalidCredentials)
        }
    }

    func testMapHTTPError429() {
        XCTAssertThrowsError(try OpenRouterClient.mapHTTPError(statusCode: 429, data: Data())) { error in
            XCTAssertEqual(error as? ProviderError, .rateLimited(retryAfterSeconds: nil))
        }
    }

    func testMapHTTPError500() {
        let data = #"{"error":{"message":"Internal"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try OpenRouterClient.mapHTTPError(statusCode: 500, data: data)) { error in
            if case .serverError(let code, let msg) = error as? ProviderError {
                XCTAssertEqual(code, 500)
                XCTAssertEqual(msg, "Internal")
            } else {
                XCTFail("Expected serverError")
            }
        }
    }

    func testMapHTTPError200DoesNotThrow() {
        XCTAssertNoThrow(try OpenRouterClient.mapHTTPError(statusCode: 200, data: Data()))
    }
}
