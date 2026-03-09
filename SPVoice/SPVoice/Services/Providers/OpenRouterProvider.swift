import Foundation
import os

/// OpenRouter transcription provider — experimental, chat-completions with audio input.
/// Transcription is performed via base64 audio in a chat completion request.
final class OpenRouterProvider: TranscriptionProvider {

    let id: ProviderID = .openrouter
    let displayName = "OpenRouter"
    let capabilities: ProviderCapabilities = .openRouter

    /// Built-in fallback models (always available even without API fetch).
    /// Gemini 2.5 Flash Lite is first → default for new installs.
    static let builtInModels: [TranscriptionModel] = [
        TranscriptionModel(
            id: "google/gemini-2.5-flash-lite-preview",
            displayName: "Gemini 2.5 Flash Lite (via OpenRouter)",
            provider: .openrouter,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "google/gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash (via OpenRouter)",
            provider: .openrouter,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "openai/gpt-4o-audio-preview",
            displayName: "GPT-4o Audio Preview (via OpenRouter)",
            provider: .openrouter,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "openai/gpt-4o-mini-audio-preview",
            displayName: "GPT-4o Mini Audio Preview (via OpenRouter)",
            provider: .openrouter,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "google/gemini-3-flash-preview",
            displayName: "Gemini 3 Flash Preview (via OpenRouter)",
            provider: .openrouter,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "google/gemini-3.1-flash-lite-preview",
            displayName: "Gemini 3.1 Flash Lite Preview (via OpenRouter)",
            provider: .openrouter,
            isDictationCapable: true
        ),
        TranscriptionModel(
            id: "google/gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro (via OpenRouter)",
            provider: .openrouter,
            isDictationCapable: true
        ),
    ]

    /// Current model list — starts with built-ins, updated by refreshModels().
    private(set) var supportedModels: [TranscriptionModel] = OpenRouterProvider.builtInModels

    /// Number of models from last API discovery (nil = never fetched).
    private(set) var lastDiscoveryCount: Int?

    var defaultModel: TranscriptionModel { supportedModels[0] }

    private let credentialsStore: CredentialsStoring
    private let session: URLSession
    private static let discoveredModelsCacheKey = "openrouterDiscoveredModelsCache"

    init(credentialsStore: CredentialsStoring, session: URLSession = .shared) {
        self.credentialsStore = credentialsStore
        self.session = session
        restoreDiscoveredModels()
    }

    // MARK: - Credential Validation

    func validateCredentials() async throws {
        guard let apiKey = credentialsStore.retrieve(for: .openrouter) else {
            throw ProviderError.providerNotConfigured
        }

        let request = OpenRouterClient.buildValidationRequest(apiKey: apiKey)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw ProviderError.timeout
        } catch {
            throw ProviderError.networkUnavailable
        }

        try OpenRouterClient.parseValidationResponse(data: data, response: response)
        Logger.provider.info("OpenRouter credentials validated successfully")
    }

    // MARK: - Model Discovery

    /// Fetch audio-capable models from the OpenRouter API and update the model list.
    /// Falls back to built-in models if the fetch fails.
    func refreshModels() async {
        guard let apiKey = credentialsStore.retrieve(for: .openrouter) else { return }

        do {
            let fetched = try await OpenRouterClient.fetchAudioModels(apiKey: apiKey, session: session)
            if !fetched.isEmpty {
                // Merge: fetched models first, then any built-ins not already present
                var merged = fetched
                for builtIn in Self.builtInModels where !merged.contains(where: { $0.id == builtIn.id }) {
                    merged.append(builtIn)
                }
                supportedModels = merged
                lastDiscoveryCount = fetched.count
                persistDiscoveredModels(fetched)
                Logger.provider.info("OpenRouter models updated: \(merged.count) total (\(fetched.count) from API)")
            }
        } catch {
            Logger.provider.warning("OpenRouter model discovery failed: \(error.localizedDescription)")
            // Keep existing models
        }
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        model: TranscriptionModel?,
        options: TranscriptionOptions?
    ) async throws -> TranscriptionResult {
        guard let apiKey = credentialsStore.retrieve(for: .openrouter) else {
            throw ProviderError.providerNotConfigured
        }

        let selectedModel = model ?? defaultModel
        let start = CFAbsoluteTimeGetCurrent()

        let request = try OpenRouterClient.buildTranscriptionRequest(
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

        let text = try OpenRouterClient.parseTranscriptionResponse(data: data, response: response)
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        Logger.provider.info("OpenRouter transcribed \(text.count) chars via \(selectedModel.id) in \(latencyMs)ms")

        return TranscriptionResult(
            text: text,
            provider: .openrouter,
            model: selectedModel.id,
            language: options?.language,
            latencyMs: latencyMs
        )
    }

    private func restoreDiscoveredModels() {
        guard let data = UserDefaults.standard.data(forKey: Self.discoveredModelsCacheKey),
              let cached = try? JSONDecoder().decode([TranscriptionModel].self, from: data),
              !cached.isEmpty
        else {
            return
        }

        var merged = cached
        for builtIn in Self.builtInModels where !merged.contains(where: { $0.id == builtIn.id }) {
            merged.append(builtIn)
        }
        supportedModels = merged
        lastDiscoveryCount = cached.count
    }

    private func persistDiscoveredModels(_ models: [TranscriptionModel]) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: Self.discoveredModelsCacheKey)
    }
}
