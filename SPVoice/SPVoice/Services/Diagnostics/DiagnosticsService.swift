import Foundation
import os

/// Diagnostic information for debugging provider and insertion issues.
/// Phase 2: skeleton. Full implementation in Phase 7.
@MainActor
final class DiagnosticsService: ObservableObject {

    @Published var lastProviderError: String?
    @Published var lastInsertionError: String?
    @Published var lastTranscriptionLatencyMs: Int?
    @Published var lastInsertionStrategy: String?
    @Published var lastFocusedApp: String?
    @Published var lastTargetRole: String?
    @Published var lastTargetBundleID: String?
    @Published var lastTargetIsChromium: Bool = false
    @Published var lastProviderUsed: String?
    @Published var lastModelUsed: String?
    @Published var sessionCount: Int = 0

    func recordProviderError(_ error: Error) {
        lastProviderError = error.localizedDescription
        Logger.diagnostics.error("Provider error: \(error.localizedDescription)")
    }

    func recordInsertionOutcome(
        _ outcome: InsertionOutcome,
        app: String?,
        role: String? = nil,
        bundleID: String? = nil,
        isChromium: Bool = false
    ) {
        lastFocusedApp = app
        lastTargetRole = role
        lastTargetBundleID = bundleID
        lastTargetIsChromium = isChromium
        switch outcome {
        case .directAXSuccess: lastInsertionStrategy = "Direct AX"
        case .axValueReplaceSuccess: lastInsertionStrategy = "AX Value Replace"
        case .clipboardPasteSuccess:
            lastInsertionStrategy = isChromium ? "Chromium Paste" : "Clipboard Paste"
        case .clipboardCopied: lastInsertionStrategy = "Clipboard Copy"
        case .failed(let err):
            lastInsertionError = err.localizedDescription
            lastInsertionStrategy = "Failed"
        }
        Logger.diagnostics.info(
            "Insertion: strategy=\(self.lastInsertionStrategy ?? "nil") app=\(app ?? "nil") role=\(role ?? "nil") bundle=\(bundleID ?? "nil") chromium=\(isChromium)"
        )
    }

    func recordLatency(_ ms: Int) {
        lastTranscriptionLatencyMs = ms
    }

    func recordLastProvider(_ provider: ProviderID, model: String) {
        lastProviderUsed = provider.displayName
        lastModelUsed = model
    }

    func incrementSessionCount() {
        sessionCount += 1
    }

    func reset() {
        lastProviderError = nil
        lastInsertionError = nil
        lastTranscriptionLatencyMs = nil
        lastInsertionStrategy = nil
        lastFocusedApp = nil
        lastTargetRole = nil
        lastTargetBundleID = nil
        lastTargetIsChromium = false
        lastProviderUsed = nil
        lastModelUsed = nil
        sessionCount = 0
    }
}
