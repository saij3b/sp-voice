import Foundation
import os

/// Low-level HTTP transport for the OpenRouter API.
/// Uses chat completions with base64-encoded audio input for transcription.
enum OpenRouterClient {

    static let chatCompletionsURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!

    /// System prompt that instructs the model to act as a pure transcriber.
    static let transcriptionPrompt =
        "Transcribe the following audio exactly as spoken. Output only the transcription text, with no preamble, commentary, or formatting."

    // MARK: - Request Builders

    /// Build a chat completion request with base64-encoded audio.
    static func buildTranscriptionRequest(
        apiKey: String,
        audioURL: URL,
        model: String
    ) throws -> URLRequest {
        let fileData = try Data(contentsOf: audioURL)
        let fileSizeMB = Double(fileData.count) / (1024 * 1024)
        let maxMB = ProviderCapabilities.openRouter.maxAudioFileSizeMB
        guard fileSizeMB <= Double(maxMB) else {
            throw ProviderError.fileTooLarge(maxMB: maxMB)
        }

        let ext = audioURL.pathExtension.lowercased()
        guard ProviderCapabilities.openRouter.supportedAudioFormats.contains(ext) else {
            throw ProviderError.unsupportedAudioFormat
        }

        let base64Audio = fileData.base64EncodedString()

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": transcriptionPrompt],
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": base64Audio,
                                "format": ext,
                            ],
                        ],
                    ],
                ] as [String: Any],
            ],
        ]

        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SPVoiceConstants.bundleIdentifier, forHTTPHeaderField: "HTTP-Referer")
        request.setValue("SP Voice", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = SPVoiceConstants.Defaults.transcriptionTimeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    /// Build a GET /api/v1/models request for credential validation.
    static func buildValidationRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        return request
    }

    // MARK: - Response Parsers

    /// Parse the chat completion response and extract transcription text.
    static func parseTranscriptionResponse(data: Data, response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.networkUnavailable
        }

        try mapHTTPError(statusCode: http.statusCode, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            Logger.provider.error("OpenRouter response: unexpected JSON structure")
            throw ProviderError.transcriptionEmpty
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Model Discovery

    /// Fetch audio-capable models from the OpenRouter API.
    /// Returns models whose modality includes "audio" in the input.
    static func fetchAudioModels(apiKey: String, session: URLSession = .shared) async throws -> [TranscriptionModel] {
        let request = buildValidationRequest(apiKey: apiKey)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.networkUnavailable
        }
        try mapHTTPError(statusCode: http.statusCode, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["data"] as? [[String: Any]]
        else {
            return []
        }

        var results: [TranscriptionModel] = []
        var seenIDs = Set<String>()
        for model in modelsArray {
            guard let id = model["id"] as? String else { continue }
            guard seenIDs.insert(id).inserted else { continue }
            guard modelAcceptsAudioInput(model) else { continue }

            let name = (model["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayBase = (name?.isEmpty == false ? name : nil) ?? id
            let displayName = displayBase + " (via OpenRouter)"

            results.append(TranscriptionModel(
                id: id,
                displayName: displayName,
                provider: .openrouter,
                isDictationCapable: true
            ))
        }

        Logger.provider.info("OpenRouter model discovery: found \(results.count) audio-capable models")
        return results
    }

    // MARK: - Error Mapping

    static func mapHTTPError(statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299:
            return
        case 401, 403:
            throw ProviderError.invalidCredentials
        case 413:
            throw ProviderError.fileTooLarge(maxMB: ProviderCapabilities.openRouter.maxAudioFileSizeMB)
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

    private static func modelAcceptsAudioInput(_ model: [String: Any]) -> Bool {
        if let architecture = model["architecture"] as? [String: Any] {
            if let modality = architecture["modality"] as? String,
               containsAudioToken(modality) {
                return true
            }
            if let modalities = architecture["modalities"] as? [Any],
               containsAudioToken(modalities) {
                return true
            }
            if let inputModalities = architecture["input_modalities"] as? [Any],
               containsAudioToken(inputModalities) {
                return true
            }
        }

        if let modalities = model["modalities"] as? [Any],
           containsAudioToken(modalities) {
            return true
        }
        if let inputModalities = model["input_modalities"] as? [Any],
           containsAudioToken(inputModalities) {
            return true
        }

        return false
    }

    private static func containsAudioToken(_ value: String) -> Bool {
        value.lowercased().contains("audio")
    }

    private static func containsAudioToken(_ values: [Any]) -> Bool {
        values.contains { value in
            if let text = value as? String {
                return containsAudioToken(text)
            }
            return false
        }
    }
}
