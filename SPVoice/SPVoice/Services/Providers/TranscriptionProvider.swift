import Foundation

// MARK: - Provider Capabilities

/// Describes what a specific provider can and cannot do for transcription.
/// OpenAI is the only first-class dictation provider in v1. OpenRouter and Gemini
/// are capability-dependent — they may or may not produce reliable transcription
/// depending on the model and audio quality.
struct ProviderCapabilities: Codable, Equatable {
    /// Provider has a dedicated speech-to-text endpoint (e.g., OpenAI /audio/transcriptions).
    let hasDedicatedTranscriptionEndpoint: Bool

    /// Provider supports audio input via multimodal chat completions.
    let supportsAudioViaChatCompletion: Bool

    /// Provider supports vocabulary hints / prompts to improve proper noun accuracy.
    let supportsTranscriptionPrompt: Bool

    /// Provider supports explicit language hint.
    let supportsLanguageHint: Bool

    /// Maximum audio file size in MB.
    let maxAudioFileSizeMB: Int

    /// Audio formats the provider accepts (e.g., ["m4a", "wav", "mp3"]).
    let supportedAudioFormats: [String]

    /// Whether this provider is considered production-ready for dictation in v1.
    /// `true` = verified, `false` = experimental / best-effort.
    let isDictationReady: Bool

    /// Optional caveat shown in UI for experimental providers.
    let caveatNote: String?
}

// MARK: - Well-Known Capabilities

extension ProviderCapabilities {
    /// OpenAI: first-class, dedicated transcription endpoint, production-ready.
    static let openAI = ProviderCapabilities(
        hasDedicatedTranscriptionEndpoint: true,
        supportsAudioViaChatCompletion: false,
        supportsTranscriptionPrompt: true,
        supportsLanguageHint: true,
        maxAudioFileSizeMB: 25,
        supportedAudioFormats: ["m4a", "mp3", "mp4", "mpeg", "mpga", "wav", "webm"],
        isDictationReady: true,
        caveatNote: nil
    )

    /// OpenRouter: chat-completions-based, experimental for dictation.
    static let openRouter = ProviderCapabilities(
        hasDedicatedTranscriptionEndpoint: false,
        supportsAudioViaChatCompletion: true,
        supportsTranscriptionPrompt: false,
        supportsLanguageHint: false,
        maxAudioFileSizeMB: 20,
        supportedAudioFormats: ["wav", "mp3", "m4a"],
        isDictationReady: false,
        caveatNote: "Transcription via chat completion — quality depends on model and prompt. Not all models support audio input."
    )

    /// Gemini: prompt-driven transcription, experimental for dictation.
    static let gemini = ProviderCapabilities(
        hasDedicatedTranscriptionEndpoint: false,
        supportsAudioViaChatCompletion: true,
        supportsTranscriptionPrompt: false,
        supportsLanguageHint: false,
        maxAudioFileSizeMB: 20,
        supportedAudioFormats: ["wav", "mp3", "aiff", "aac", "ogg", "flac"],
        isDictationReady: false,
        caveatNote: "Transcription is prompt-driven — the model may add formatting or miss words."
    )
}

// MARK: - Transcription Provider Protocol

/// The single interface that TranscriptionService uses. Every provider must conform.
/// Provider implementations live in separate files (OpenAIProvider, etc.).
protocol TranscriptionProvider {
    var id: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    var supportedModels: [TranscriptionModel] { get }
    var defaultModel: TranscriptionModel { get }

    /// Validate that the stored API key is well-formed and the provider is reachable.
    func validateCredentials() async throws

    /// Transcribe audio at the given URL. Returns a normalized result.
    func transcribe(
        audioURL: URL,
        model: TranscriptionModel?,
        options: TranscriptionOptions?
    ) async throws -> TranscriptionResult
}

extension TranscriptionProvider {
    /// Whether this provider can be used as a primary dictation provider today.
    var isDictationReady: Bool { capabilities.isDictationReady }
}
