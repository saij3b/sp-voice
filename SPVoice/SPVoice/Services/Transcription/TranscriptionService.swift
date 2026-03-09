import Foundation
import os

/// Provider-agnostic transcription orchestrator.
/// Resolves the active provider, sends audio, handles fallback.
/// Phase 2: skeleton. Wired end-to-end in Phase 3.
@MainActor
final class TranscriptionService: ObservableObject {

    private let providerManager: ProviderManager

    init(providerManager: ProviderManager) {
        self.providerManager = providerManager
    }

    /// Transcribe audio at the given URL using the active provider.
    /// Falls back to the secondary provider on retryable errors.
    func transcribe(audioURL: URL, options: TranscriptionOptions? = nil) async throws -> TranscriptionResult {
        guard let primary = providerManager.activeProvider else {
            throw ProviderError.providerNotConfigured
        }

        let model = providerManager.selectedModel(for: primary.id)

        do {
            let result = try await primary.transcribe(audioURL: audioURL, model: model, options: options)
            Logger.transcription.info("Transcribed via \(primary.id.rawValue) in \(result.latencyMs)ms")
            return result
        } catch {
            Logger.transcription.error("Primary provider \(primary.id.rawValue) failed: \(error.localizedDescription)")

            // Attempt fallback on retryable errors
            if isRetryable(error), let fallback = providerManager.fallbackProvider {
                Logger.transcription.info("Falling back to \(fallback.id.rawValue)")
                let fallbackModel = providerManager.selectedModel(for: fallback.id)
                return try await fallback.transcribe(audioURL: audioURL, model: fallbackModel, options: options)
            }

            throw error
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        guard let providerError = error as? ProviderError else { return false }
        switch providerError {
        case .rateLimited, .serverError, .timeout, .networkUnavailable:
            return true
        default:
            return false
        }
    }
}
