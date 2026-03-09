import Foundation
@testable import SPVoice

final class MockTranscriptionProvider: TranscriptionProvider {

    let id: ProviderID
    let displayName: String
    let capabilities: ProviderCapabilities
    let supportedModels: [TranscriptionModel]
    let defaultModel: TranscriptionModel

    var validateResult: Result<Void, Error> = .success(())
    var transcribeResult: Result<TranscriptionResult, Error>?
    var transcribeCallCount = 0
    var lastTranscribeModel: TranscriptionModel?
    var lastTranscribeOptions: TranscriptionOptions?

    init(
        id: ProviderID = .openai,
        displayName: String = "Mock",
        capabilities: ProviderCapabilities = .openAI,
        models: [TranscriptionModel]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities

        let defaultModels = [
            TranscriptionModel(id: "mock-model", displayName: "Mock Model", provider: id, isDictationCapable: true)
        ]
        self.supportedModels = models ?? defaultModels
        self.defaultModel = supportedModels[0]
    }

    func validateCredentials() async throws {
        try validateResult.get()
    }

    func transcribe(
        audioURL: URL,
        model: TranscriptionModel?,
        options: TranscriptionOptions?
    ) async throws -> TranscriptionResult {
        transcribeCallCount += 1
        lastTranscribeModel = model
        lastTranscribeOptions = options

        if let result = transcribeResult {
            return try result.get()
        }

        return TranscriptionResult(
            text: "Mock transcription",
            provider: id,
            model: model?.id ?? defaultModel.id,
            language: "en",
            latencyMs: 100
        )
    }
}
