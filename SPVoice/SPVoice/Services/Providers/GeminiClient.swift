import Foundation
import os

/// Low-level HTTP transport for the Google Gemini API.
/// Uses generateContent with inline base64 audio for transcription.
enum GeminiClient {

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    /// System prompt that instructs the model to act as a pure transcriber.
    static let transcriptionPrompt =
        "Transcribe the following audio exactly as spoken. Output only the transcription text, with no preamble, commentary, or formatting."

    // MARK: - URLs
    // Keys go in the x-goog-api-key header, not the query string, so they
    // don't land in URL caches, proxies, or os_log URL traces.

    static func generateContentURL(model: String) -> URL {
        URL(string: "\(baseURL)/models/\(model):generateContent")!
    }

    static func modelsURL() -> URL {
        URL(string: "\(baseURL)/models")!
    }

    // MARK: - Request Builders

    /// Build a generateContent request with inline base64 audio.
    static func buildTranscriptionRequest(
        apiKey: String,
        audioURL: URL,
        model: String
    ) throws -> URLRequest {
        let fileData = try Data(contentsOf: audioURL)
        let fileSizeMB = Double(fileData.count) / (1024 * 1024)
        let maxMB = ProviderCapabilities.gemini.maxAudioFileSizeMB
        guard fileSizeMB <= Double(maxMB) else {
            throw ProviderError.fileTooLarge(maxMB: maxMB)
        }

        let ext = audioURL.pathExtension.lowercased()
        guard ProviderCapabilities.gemini.supportedAudioFormats.contains(ext) else {
            throw ProviderError.unsupportedAudioFormat
        }

        let base64Audio = fileData.base64EncodedString()
        let mimeType = self.mimeType(for: ext)

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": transcriptionPrompt],
                        [
                            "inlineData": [
                                "mimeType": mimeType,
                                "data": base64Audio,
                            ],
                        ],
                    ],
                ] as [String: Any],
            ],
        ]

        let url = generateContentURL(model: model)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = SPVoiceConstants.Defaults.transcriptionTimeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    /// Build a GET /models request for credential validation.
    static func buildValidationRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: modelsURL())
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 10
        return request
    }

    // MARK: - Response Parsers

    /// Parse the generateContent response and extract transcription text.
    /// Response shape: `{candidates: [{content: {parts: [{text: "..."}]}}]}`
    static func parseTranscriptionResponse(data: Data, response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.networkUnavailable
        }

        try mapHTTPError(statusCode: http.statusCode, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let textPart = parts.first(where: { $0["text"] != nil }),
              let text = textPart["text"] as? String
        else {
            Logger.provider.error("Gemini response: unexpected JSON structure")
            throw ProviderError.transcriptionEmpty
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderError.transcriptionEmpty
        }

        return trimmed
    }

    /// Parse validation response. Throws on failure.
    static func parseValidationResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.networkUnavailable
        }
        try mapHTTPError(statusCode: http.statusCode, data: data)
    }

    // MARK: - Error Mapping

    static func mapHTTPError(statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299:
            return
        case 400:
            // Gemini returns 400 for invalid API key
            let message = parseErrorMessage(data: data)
            if message?.lowercased().contains("api key") == true {
                throw ProviderError.invalidCredentials
            }
            throw ProviderError.serverError(statusCode: statusCode, message: message)
        case 401, 403:
            throw ProviderError.invalidCredentials
        case 429:
            throw ProviderError.rateLimited(retryAfterSeconds: nil)
        case 500...599:
            let message = parseErrorMessage(data: data)
            throw ProviderError.serverError(statusCode: statusCode, message: message)
        default:
            let message = parseErrorMessage(data: data)
            throw ProviderError.serverError(statusCode: statusCode, message: message)
        }
    }

    private static func parseErrorMessage(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        return message
    }

    // MARK: - Helpers

    static func mimeType(for ext: String) -> String {
        switch ext {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mp3"
        case "aiff": return "audio/aiff"
        case "aac": return "audio/aac"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        case "m4a": return "audio/m4a"
        default: return "application/octet-stream"
        }
    }
}
