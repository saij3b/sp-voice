import XCTest
@testable import SPVoice

final class OpenAIClientTests: XCTestCase {

    // MARK: - Test Fixtures

    /// Create a tiny WAV file for request-building tests.
    private func createTestWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio_\(UUID().uuidString).wav")
        // Minimal valid WAV: 44-byte header + 2 bytes of silence
        var header = Data()
        let dataSize: UInt32 = 2
        let fileSize: UInt32 = 36 + dataSize
        header.append("RIFF".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // PCM
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // mono
        header.append(withUnsafeBytes(of: UInt32(16000).littleEndian) { Data($0) }) // sample rate
        header.append(withUnsafeBytes(of: UInt32(32000).littleEndian) { Data($0) }) // byte rate
        header.append(withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })  // block align
        header.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // bits per sample
        header.append("data".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        header.append(Data([0, 0])) // silence
        try header.write(to: url)
        return url
    }

    override func tearDown() {
        // Clean up test files
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasPrefix("test_audio_") {
                try? FileManager.default.removeItem(at: f)
            }
        }
        super.tearDown()
    }

    // MARK: - Request Construction

    func testTranscriptionRequestURL() throws {
        let audioURL = try createTestWAV()
        let request = try OpenAIClient.buildTranscriptionRequest(
            apiKey: "sk-test123", audioURL: audioURL, model: "gpt-4o-transcribe", options: nil
        )
        XCTAssertEqual(request.url, OpenAIClient.transcriptionURL)
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testTranscriptionRequestAuthHeader() throws {
        let audioURL = try createTestWAV()
        let request = try OpenAIClient.buildTranscriptionRequest(
            apiKey: "sk-mykey999", audioURL: audioURL, model: "gpt-4o-transcribe", options: nil
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-mykey999")
    }

    func testTranscriptionRequestContentType() throws {
        let audioURL = try createTestWAV()
        let request = try OpenAIClient.buildTranscriptionRequest(
            apiKey: "sk-test", audioURL: audioURL, model: "gpt-4o-transcribe", options: nil
        )
        let ct = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(ct.hasPrefix("multipart/form-data; boundary=SPVoice-"))
    }

    func testTranscriptionRequestBodyContainsModel() throws {
        let audioURL = try createTestWAV()
        let request = try OpenAIClient.buildTranscriptionRequest(
            apiKey: "sk-test", audioURL: audioURL, model: "gpt-4o-mini-transcribe", options: nil
        )
        let body = request.httpBody ?? Data()
        XCTAssertTrue(body.containsUTF8("gpt-4o-mini-transcribe"), "Body should contain model name")
        XCTAssertTrue(body.containsUTF8("name=\"model\""), "Body should have model field")
        XCTAssertTrue(body.containsUTF8("name=\"response_format\""), "Body should have response_format field")
    }

    func testTranscriptionRequestBodyContainsOptionalFields() throws {
        let audioURL = try createTestWAV()
        let options = TranscriptionOptions(language: "en", prompt: "SP Voice test", temperature: 0.2)
        let request = try OpenAIClient.buildTranscriptionRequest(
            apiKey: "sk-test", audioURL: audioURL, model: "gpt-4o-transcribe", options: options
        )
        let body = request.httpBody ?? Data()
        XCTAssertTrue(body.containsUTF8("name=\"language\""))
        XCTAssertTrue(body.containsUTF8("name=\"prompt\""))
        XCTAssertTrue(body.containsUTF8("SP Voice test"))
        XCTAssertTrue(body.containsUTF8("name=\"temperature\""))
        XCTAssertTrue(body.containsUTF8("0.2"))
    }

    func testTranscriptionRequestTimeout() throws {
        let audioURL = try createTestWAV()
        let request = try OpenAIClient.buildTranscriptionRequest(
            apiKey: "sk-test", audioURL: audioURL, model: "gpt-4o-transcribe", options: nil
        )
        XCTAssertEqual(request.timeoutInterval, SPVoiceConstants.Defaults.transcriptionTimeoutSeconds)
    }

    func testTranscriptionRequestRejectsUnsupportedFormat() throws {
        let badURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_audio_bad.ogg")
        try Data([0]).write(to: badURL)
        defer { try? FileManager.default.removeItem(at: badURL) }

        XCTAssertThrowsError(
            try OpenAIClient.buildTranscriptionRequest(
                apiKey: "sk-test", audioURL: badURL, model: "gpt-4o-transcribe", options: nil
            )
        ) { error in
            XCTAssertEqual(error as? ProviderError, .unsupportedAudioFormat)
        }
    }

    // MARK: - Validation Request

    func testValidationRequest() {
        let request = OpenAIClient.buildValidationRequest(apiKey: "sk-val123")
        XCTAssertEqual(request.url, OpenAIClient.modelsURL)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-val123")
    }

    // MARK: - Response Parsing (Success)

    func testParseTranscriptionSuccess() throws {
        let json = #"{"text": "Hello world"}"#
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenAIClient.transcriptionURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let text = try OpenAIClient.parseTranscriptionResponse(data: data, response: response)
        XCTAssertEqual(text, "Hello world")
    }

    func testParseTranscriptionTrimsWhitespace() throws {
        let json = #"{"text": "  Hello world  \n"}"#
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenAIClient.transcriptionURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let text = try OpenAIClient.parseTranscriptionResponse(data: data, response: response)
        XCTAssertEqual(text, "Hello world")
    }

    // MARK: - Response Parsing (Errors)

    func testParseTranscriptionEmptyText() {
        let json = #"{"text": ""}"#
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenAIClient.transcriptionURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OpenAIClient.parseTranscriptionResponse(data: data, response: response)) { error in
            XCTAssertEqual(error as? ProviderError, .transcriptionEmpty)
        }
    }

    func testParseTranscriptionMalformedJSON() {
        let data = "not json".data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenAIClient.transcriptionURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OpenAIClient.parseTranscriptionResponse(data: data, response: response)) { error in
            XCTAssertEqual(error as? ProviderError, .transcriptionEmpty)
        }
    }

    // MARK: - HTTP Error Mapping

    func testMapHTTPError401() {
        let data = #"{"error":{"message":"Invalid key"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try OpenAIClient.mapHTTPError(statusCode: 401, data: data)) { error in
            XCTAssertEqual(error as? ProviderError, .invalidCredentials)
        }
    }

    func testMapHTTPError429() {
        let data = #"{"error":{"message":"Rate limit, retry after 30s"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try OpenAIClient.mapHTTPError(statusCode: 429, data: data)) { error in
            if case .rateLimited(let seconds) = error as? ProviderError {
                XCTAssertEqual(seconds, 30)
            } else {
                XCTFail("Expected rateLimited")
            }
        }
    }

    func testMapHTTPError429NoRetryInfo() {
        let data = #"{"error":{"message":"Too many requests"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try OpenAIClient.mapHTTPError(statusCode: 429, data: data)) { error in
            if case .rateLimited(let seconds) = error as? ProviderError {
                XCTAssertNil(seconds)
            } else {
                XCTFail("Expected rateLimited")
            }
        }
    }

    func testMapHTTPError413() {
        let data = Data()
        XCTAssertThrowsError(try OpenAIClient.mapHTTPError(statusCode: 413, data: data)) { error in
            if case .fileTooLarge(let max) = error as? ProviderError {
                XCTAssertEqual(max, 25)
            } else {
                XCTFail("Expected fileTooLarge")
            }
        }
    }

    func testMapHTTPError500() {
        let data = #"{"error":{"message":"Internal server error"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try OpenAIClient.mapHTTPError(statusCode: 500, data: data)) { error in
            if case .serverError(let code, let msg) = error as? ProviderError {
                XCTAssertEqual(code, 500)
                XCTAssertEqual(msg, "Internal server error")
            } else {
                XCTFail("Expected serverError")
            }
        }
    }

    func testMapHTTPSuccess() {
        XCTAssertNoThrow(try OpenAIClient.mapHTTPError(statusCode: 200, data: Data()))
    }

    // MARK: - MIME Type

    func testMimeTypes() {
        XCTAssertEqual(OpenAIClient.mimeType(for: "wav"), "audio/wav")
        XCTAssertEqual(OpenAIClient.mimeType(for: "mp3"), "audio/mpeg")
        XCTAssertEqual(OpenAIClient.mimeType(for: "m4a"), "audio/m4a")
        XCTAssertEqual(OpenAIClient.mimeType(for: "webm"), "audio/webm")
        XCTAssertEqual(OpenAIClient.mimeType(for: "xyz"), "application/octet-stream")
    }

    // MARK: - Validation Response

    func testParseValidationSuccess() {
        let data = #"{"data":[{"id":"gpt-4o"}]}"#.data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenAIClient.modelsURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertNoThrow(try OpenAIClient.parseValidationResponse(data: data, response: response))
    }

    func testParseValidation401() {
        let data = #"{"error":{"message":"Bad key"}}"#.data(using: .utf8)!
        let response = HTTPURLResponse(url: OpenAIClient.modelsURL, statusCode: 401, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OpenAIClient.parseValidationResponse(data: data, response: response)) { error in
            XCTAssertEqual(error as? ProviderError, .invalidCredentials)
        }
    }
}

// MARK: - Data Search Helper

private extension Data {
    /// Search for a UTF-8 substring within binary data (handles mixed binary/text multipart bodies).
    func containsUTF8(_ string: String) -> Bool {
        guard let needle = string.data(using: .utf8) else { return false }
        return range(of: needle) != nil
    }
}
