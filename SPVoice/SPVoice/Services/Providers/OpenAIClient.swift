import Foundation
import os

/// Low-level HTTP transport for the OpenAI API.
/// All methods are static and pure (no side effects beyond building requests / parsing responses)
/// to enable unit testing without network access.
enum OpenAIClient {

    static let transcriptionURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    static let modelsURL = URL(string: "https://api.openai.com/v1/models")!

    // MARK: - Request Builders

    /// Build a multipart/form-data request for POST /v1/audio/transcriptions.
    static func buildTranscriptionRequest(
        apiKey: String,
        audioURL: URL,
        model: String,
        options: TranscriptionOptions?
    ) throws -> URLRequest {
        // Validate file exists and check size
        let fileData = try Data(contentsOf: audioURL)
        let fileSizeMB = Double(fileData.count) / (1024 * 1024)
        let maxMB = ProviderCapabilities.openAI.maxAudioFileSizeMB
        guard fileSizeMB <= Double(maxMB) else {
            throw ProviderError.fileTooLarge(maxMB: maxMB)
        }

        // Validate audio format
        let ext = audioURL.pathExtension.lowercased()
        guard ProviderCapabilities.openAI.supportedAudioFormats.contains(ext) else {
            throw ProviderError.unsupportedAudioFormat
        }

        let boundary = "SPVoice-\(UUID().uuidString)"
        var request = URLRequest(url: transcriptionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = SPVoiceConstants.Defaults.transcriptionTimeoutSeconds

        var body = Data()

        // file field
        body.appendMultipart(boundary: boundary, name: "file", filename: audioURL.lastPathComponent, mimeType: mimeType(for: ext), data: fileData)

        // model field
        body.appendMultipart(boundary: boundary, name: "model", value: model)

        // response_format — always json for structured parsing
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")

        // Optional fields
        if let language = options?.language {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }
        if let prompt = options?.prompt {
            body.appendMultipart(boundary: boundary, name: "prompt", value: prompt)
        }
        if let temperature = options?.temperature {
            body.appendMultipart(boundary: boundary, name: "temperature", value: String(temperature))
        }

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        return request
    }

    /// Build a GET /v1/models request for credential validation.
    static func buildValidationRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        return request
    }

    // MARK: - Response Parsers

    /// Parse the transcription response. Returns the transcribed text.
    static func parseTranscriptionResponse(data: Data, response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.networkUnavailable
        }

        try mapHTTPError(statusCode: http.statusCode, data: data)

        // Parse JSON {"text": "..."}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            Logger.provider.error("OpenAI response: unexpected JSON structure")
            throw ProviderError.transcriptionEmpty
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderError.transcriptionEmpty
        }

        return trimmed
    }

    /// Parse the validation response. Throws on failure.
    static func parseValidationResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.networkUnavailable
        }
        try mapHTTPError(statusCode: http.statusCode, data: data)
        // 200 = credentials valid
    }

    // MARK: - Error Mapping

    static func mapHTTPError(statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299:
            return // success
        case 401:
            throw ProviderError.invalidCredentials
        case 413:
            throw ProviderError.fileTooLarge(maxMB: ProviderCapabilities.openAI.maxAudioFileSizeMB)
        case 429:
            let retryAfter = parseRetryAfter(data: data)
            throw ProviderError.rateLimited(retryAfterSeconds: retryAfter)
        case 500...599:
            let message = parseErrorMessage(data: data)
            throw ProviderError.serverError(statusCode: statusCode, message: message)
        default:
            let message = parseErrorMessage(data: data)
            throw ProviderError.serverError(statusCode: statusCode, message: message)
        }
    }

    // MARK: - Helpers

    private static func parseErrorMessage(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        return message
    }

    private static func parseRetryAfter(data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        // OpenAI sometimes includes "Please retry after Xs" in the message
        let pattern = /retry after (\d+)/
        if let match = message.firstMatch(of: pattern),
           let seconds = Int(match.1) {
            return seconds
        }
        return nil
    }

    static func mimeType(for ext: String) -> String {
        switch ext {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/m4a"
        case "mp4": return "audio/mp4"
        case "mpeg", "mpga": return "audio/mpeg"
        case "webm": return "audio/webm"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Multipart Helpers

extension Data {

    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
