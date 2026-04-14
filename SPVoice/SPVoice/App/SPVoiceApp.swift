import SwiftUI

@main
struct SPVoiceApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Menu bar item — the primary UI surface
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label("SP Voice", systemImage: appState.dictationState.menuBarIcon)
        }

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // Onboarding window (opens on first launch)
        Window("Welcome to SP Voice", id: "onboarding") {
            OnboardingView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 560)
    }
}

// MARK: - DictationState UI Helpers

extension DictationState {

    var menuBarIcon: String {
        switch self {
        case .idle: return "waveform"
        case .listening: return "waveform.and.mic"
        case .transcribing: return "waveform.path.ecg"
        case .processing: return "sparkles"
        case .inserting: return "text.cursor"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var statusText: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .processing: return "Processing…"
        case .inserting: return "Inserting…"
        case .success(let preview): return preview
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
