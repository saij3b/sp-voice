import XCTest
@testable import SPVoice

final class GeminiClientTests: XCTestCase {

    // MARK: - Test Fixtures

    private func createTestWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_gem_audio_\(UUID().uuidString).wav")
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
            for f in files where f.lastPathComponent.hasPrefix("test_gem_audio_") {
                try? FileManager.default.removeItem(at: f)
            }
        }
        super.tearDown()
    }

    // MARK: - Request Construction

    func testTranscriptionRequestURL() throws {
        let audioURL = try createTestWAV()
        let request = try GeminiClient.buildTranscriptionRequest(
            apiKey: "AIzaTest123", audioURL: audioURL, model: "gemini-2.5-flash"
        )
        XCTAssertTrue(request.url!.absoluteString.contains("gemini-2.5-flash:generateContent"))
        XCTAssertTrue(request.url!.absoluteString.contains("key=AIzaTest123"))
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testTranscriptionRequestContentType() throws {
        let audioURL = try createTestWAV()
        let request = try GeminiClient.buildTranscriptionRequest(
            apiKey: "AIzaTest", audioURL: audioURL, model: "gemini-2.5-flash"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testTranscriptionRequestBodyStructure() throws {
        let audioURL = try createTestWAV()
        let request = try GeminiClient.buildTranscriptionRequest(
            apiKey: "AIzaTest", audioURL: audioURL, model: "gemini-2.5-flash"
        )
        let body = request.httpBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let contents = json?["contents"] as? [[String: Any]]
        XCTAssertNotNil(contents)
        XCTAssertEqual(contents?.count, 1)

        let parts = contents?.first?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 2) // text part + inlineData part
    }

    func testValidationRequest() {
        let request = GeminiClient.buildValidationRequest(apiKey: "AIzaVal123")
        XCTAssertTrue(request.url!.absoluteString.contains("/models?key=AIzaVal123"))
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - Response Parsing

    func testParseTranscriptionSuccess() throws {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"Hello from Gemini"}]}}]}"#
        let data = json.data(using: .utf8)!
        let url = GeminiClient.generateContentURL(model: "gemini-2.5-flash")
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let text = try GeminiClient.parseTranscriptionResponse(data: data, response: response)
        XCTAssertEqual(text, "Hello from Gemini")
    }

    func testParseTranscriptionTrimsWhitespace() throws {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"  Trimmed  \n"}]}}]}"#
        let data = json.data(using: .utf8)!
        let url = GeminiClient.generateContentURL(model: "test")
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let text = try GeminiClient.parseTranscriptionResponse(data: data, response: response)
        XCTAssertEqual(text, "Trimmed")
    }

    func testParseTranscriptionEmptyText() {
        let json = #"{"candidates":[{"content":{"parts":[{"text":""}]}}]}"#
        let data = json.data(using: .utf8)!
        let url = GeminiClient.generateContentURL(model: "test")
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try GeminiClient.parseTranscriptionResponse(data: data, response: response)) { error in
            XCTAssertEqual(error as? ProviderError, .transcriptionEmpty)
        }
    }

    func testParseTranscriptionMalformedJSON() {
        let data = "not json".data(using: .utf8)!
        let url = GeminiClient.generateContentURL(model: "test")
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try GeminiClient.parseTranscriptionResponse(data: data, response: response)) { error in
            XCTAssertEqual(error as? ProviderError, .transcriptionEmpty)
        }
    }

    // MARK: - Error Mapping

    func testMapHTTPError400WithAPIKeyMessage() {
        let data = #"{"error":{"message":"API key not valid"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try GeminiClient.mapHTTPError(statusCode: 400, data: data)) { error in
            XCTAssertEqual(error as? ProviderError, .invalidCredentials)
        }
    }

    func testMapHTTPError403() {
        XCTAssertThrowsError(try GeminiClient.mapHTTPError(statusCode: 403, data: Data())) { error in
            XCTAssertEqual(error as? ProviderError, .invalidCredentials)
        }
    }

    func testMapHTTPError429() {
        XCTAssertThrowsError(try GeminiClient.mapHTTPError(statusCode: 429, data: Data())) { error in
            XCTAssertEqual(error as? ProviderError, .rateLimited(retryAfterSeconds: nil))
        }
    }

    func testMapHTTPError200DoesNotThrow() {
        XCTAssertNoThrow(try GeminiClient.mapHTTPError(statusCode: 200, data: Data()))
    }

    // MARK: - MIME Types

    func testMimeTypes() {
        XCTAssertEqual(GeminiClient.mimeType(for: "wav"), "audio/wav")
        XCTAssertEqual(GeminiClient.mimeType(for: "mp3"), "audio/mp3")
        XCTAssertEqual(GeminiClient.mimeType(for: "flac"), "audio/flac")
        XCTAssertEqual(GeminiClient.mimeType(for: "ogg"), "audio/ogg")
        XCTAssertEqual(GeminiClient.mimeType(for: "xyz"), "application/octet-stream")
    }
}
