import Foundation
import os

/// OpenAI transcription provider — first-class, dedicated /audio/transcriptions endpoint.
final class OpenAIProvider: TranscriptionProvider {

    let id: ProviderID = .openai
    let displayName = "OpenAI"
    let capabilities: ProviderCapabilities = .openAI

    let supportedModels: [TranscriptionModel] = [
        TranscriptionModel(
            id: "gpt-4o-transcribe",
            displayName: "GPT-4o Transcribe",
            provider: .openai,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "gpt-4o-mini-transcribe",
            displayName: "GPT-4o Mini Transcribe",
            provider: .openai,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "whisper-1",
            displayName: "Whisper v1",
            provider: .openai,
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
        guard let apiKey = credentialsStore.retrieve(for: .openai) else {
            throw ProviderError.providerNotConfigured
        }

        let request = OpenAIClient.buildValidationRequest(apiKey: apiKey)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw ProviderError.timeout
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            throw ProviderError.networkUnavailable
        } catch {
            throw ProviderError.networkUnavailable
        }

        try OpenAIClient.parseValidationResponse(data: data, response: response)
        Logger.provider.info("OpenAI credentials validated successfully")
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        model: TranscriptionModel?,
        options: TranscriptionOptions?
    ) async throws -> TranscriptionResult {
        guard let apiKey = credentialsStore.retrieve(for: .openai) else {
            throw ProviderError.providerNotConfigured
        }

        let selectedModel = model ?? defaultModel
        let start = CFAbsoluteTimeGetCurrent()

        // Build multipart request
        let request = try OpenAIClient.buildTranscriptionRequest(
            apiKey: apiKey,
            audioURL: audioURL,
            model: selectedModel.id,
            options: options
        )

        // Send
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw ProviderError.timeout
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            throw ProviderError.networkUnavailable
        } catch {
            throw ProviderError.networkUnavailable
        }

        // Parse
        let text = try OpenAIClient.parseTranscriptionResponse(data: data, response: response)
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        Logger.provider.info("OpenAI transcribed \(text.count) chars via \(selectedModel.id) in \(latencyMs)ms")

        return TranscriptionResult(
            text: text,
            provider: .openai,
            model: selectedModel.id,
            language: options?.language,
            latencyMs: latencyMs
        )
    }
}
