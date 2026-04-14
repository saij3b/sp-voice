import Foundation
import os

/// Gemini transcription provider — experimental, prompt-driven via generateContent.
/// Transcription is performed by sending base64 audio inline with a transcription prompt.
final class GeminiProvider: TranscriptionProvider {

    let id: ProviderID = .gemini
    let displayName = "Gemini"
    let capabilities: ProviderCapabilities = .gemini

    let supportedModels: [TranscriptionModel] = [
        TranscriptionModel(
            id: "gemini-2.5-flash-lite",
            displayName: "Gemini 2.5 Flash Lite",
            provider: .gemini,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            provider: .gemini,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            provider: .gemini,
            isDictationCapable: true
        ),
    ]

    var defaultModel: TranscriptionModel { supportedModels[0] }

    private let credentialsStore: CredentialsStoring
    private let session: URLSession

    init(credentialsStore: CredentialsStoring, session: URLSession = .shared) {
        self.credentialsStore = credentialsStore
        self.session = session
    }

    // MARK: - Credential Validation

    func validateCredentials() async throws {
        guard let apiKey = credentialsStore.retrieve(for: .gemini) else {
            throw ProviderError.providerNotConfigured
        }

        let request = GeminiClient.buildValidationRequest(apiKey: apiKey)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw ProviderError.timeout
        } catch {
            throw ProviderError.networkUnavailable
        }

        try GeminiClient.parseValidationResponse(data: data, response: response)
        Logger.provider.info("Gemini credentials validated successfully")
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        model: TranscriptionModel?,
        options: TranscriptionOptions?
    ) async throws -> TranscriptionResult {
        guard let apiKey = credentialsStore.retrieve(for: .gemini) else {
            throw ProviderError.providerNotConfigured
        }

        let selectedModel = model ?? defaultModel
        let start = CFAbsoluteTimeGetCurrent()

        let request = try GeminiClient.buildTranscriptionRequest(
            apiKey: apiKey,
            audioURL: audioURL,
            model: selectedModel.id
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw ProviderError.timeout
        } catch {
            throw ProviderError.networkUnavailable
        }

        let text = try GeminiClient.parseTranscriptionResponse(data: data, response: response)
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        Logger.provider.info("Gemini transcribed \(text.count) chars via \(selectedModel.id) in \(latencyMs)ms")

        return TranscriptionResult(
            text: text,
            provider: .gemini,
            model: selectedModel.id,
            language: options?.language,
            latencyMs: latencyMs
        )
    }
}
