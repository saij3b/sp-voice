import SwiftUI

/// Content view shown in the MenuBarExtra popover.
struct MenuBarView: View {

    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Image(systemName: appState.dictationState.menuBarIcon)
                    .foregroundStyle(iconColor)
                Text(appState.dictationState.statusText)
                    .font(.headline)
            }

            Divider()

            // Hotkey status
            if !appState.shortcutManager.isRegistered {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Hotkey not active — open Settings → Diagnostics")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Provider info
            if let id = appState.providerManager.resolvedPrimaryID,
               let model = appState.providerManager.selectedModel(for: id) {
                Text("Provider: \(id.rawValue) / \(model.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No provider configured")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Last transcription preview
            if let text = appState.lastTranscription {
                Text(text)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }

            Divider()

            // Actions
            Button("Settings…") {
                openSettings()
                appState.bringSettingsWindowToFront()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit SP Voice") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .frame(width: 260)
    }

    private var iconColor: Color {
        switch appState.dictationState {
        case .idle: return .primary
        case .listening: return .red
        case .transcribing: return .blue
        case .processing: return .purple
        case .inserting: return .green
        case .success: return .green
        case .error: return .orange
        }
    }
}
