import Foundation

// MARK: - Provider Identity

enum ProviderID: String, Codable, CaseIterable, Identifiable {
    case openai
    case openrouter
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .gemini: return "Gemini"
        }
    }

    /// Hint for validating raw key format. Not a guarantee.
    /// Returns nil for providers with no standard prefix (e.g. Gemini).
    var keyPrefixHint: String? {
        switch self {
        case .openai: return "sk-"
        case .openrouter: return "sk-or-"
        case .gemini: return nil // Gemini keys have no standard prefix
        }
    }
}

// MARK: - Transcription Model

struct TranscriptionModel: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let provider: ProviderID

    /// Whether this model is verified for dictation use. Some models behind
    /// chat-completion APIs may produce unreliable transcription.
    let isDictationCapable: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(provider)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.provider == rhs.provider
    }
}

// MARK: - Transcription Options

struct TranscriptionOptions: Equatable {
    var language: String?
    var prompt: String?
    var temperature: Double?
}

// MARK: - Transcription Result

struct TranscriptionResult: Equatable {
    let text: String
    let provider: ProviderID
    let model: String
    let language: String?
    let latencyMs: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.provider == rhs.provider
            && lhs.model == rhs.model && lhs.latencyMs == rhs.latencyMs
    }
}

// MARK: - Provider Error

enum ProviderError: Error, LocalizedError, Equatable {
    case invalidCredentials
    case networkUnavailable
    case rateLimited(retryAfterSeconds: Int?)
    case serverError(statusCode: Int, message: String?)
    case timeout
    case unsupportedAudioFormat
    case fileTooLarge(maxMB: Int)
    case transcriptionEmpty
    case providerNotReady(reason: String)
    case providerNotConfigured

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid API key"
        case .networkUnavailable: return "Network unavailable"
        case .rateLimited(let s):
            return s.map { "Rate limited — retry in \($0)s" } ?? "Rate limited"
        case .serverError(let code, let msg):
            return "Server error \(code)\(msg.map { ": \($0)" } ?? "")"
        case .timeout: return "Transcription timed out"
        case .unsupportedAudioFormat: return "Unsupported audio format"
        case .fileTooLarge(let max): return "Audio file exceeds \(max) MB limit"
        case .transcriptionEmpty: return "Transcription returned empty text"
        case .providerNotReady(let reason): return "Provider not ready: \(reason)"
        case .providerNotConfigured: return "No provider configured"
        }
    }
}

// MARK: - Hotkey Mode

enum HotkeyMode: String, Codable, CaseIterable {
    case pushToTalk
    case toggleToTalk

    var displayName: String {
        switch self {
        case .pushToTalk: return "Push to Talk"
        case .toggleToTalk: return "Toggle to Talk"
        }
    }
}

// MARK: - Text Processing Mode

enum TextProcessingMode: String, Codable, CaseIterable {
    case rawDictation
    case polishedWriting
    case promptMode
    case customTransform

    var displayName: String {
        switch self {
        case .rawDictation: return "Raw Dictation"
        case .polishedWriting: return "Polished Writing"
        case .promptMode: return "Prompt Mode"
        case .customTransform: return "Custom Transform"
        }
    }
}

// MARK: - Dictation State

enum DictationState: Equatable {
    case idle
    case listening
    case transcribing
    case processing
    case inserting
    case success(preview: String)
    case error(message: String)

    var isActive: Bool {
        switch self {
        case .idle, .success, .error: return false
        default: return true
        }
    }
}
