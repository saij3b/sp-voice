import SwiftUI

struct DiagnosticsView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Last Operation") {
                diagRow("Provider", value: appState.diagnosticsService.lastProviderUsed)
                diagRow("Model", value: appState.diagnosticsService.lastModelUsed)
                diagRow("Latency", value: appState.diagnosticsService.lastTranscriptionLatencyMs.map { "\($0) ms" })
                diagRow("Insertion Strategy", value: appState.diagnosticsService.lastInsertionStrategy)
                diagRow("Focused App", value: appState.diagnosticsService.lastFocusedApp)
                diagRow("Target Role", value: appState.diagnosticsService.lastTargetRole)
                diagRow("Bundle ID", value: appState.diagnosticsService.lastTargetBundleID)
                if appState.diagnosticsService.lastTargetIsChromium {
                    diagRow("Chromium Path", value: "Yes")
                }
            }

            Section("Errors") {
                diagRow("Provider Error", value: appState.diagnosticsService.lastProviderError)
                diagRow("Insertion Error", value: appState.diagnosticsService.lastInsertionError)
            }

            Section("System") {
                diagRow("Sessions", value: "\(appState.diagnosticsService.sessionCount)")
                diagRow("Accessibility", value: appState.permissionsManager.accessibilityGranted ? "Granted" : "Not Granted")
                diagRow("Input Monitoring", value: appState.permissionsManager.inputMonitoringGranted ? "Granted" : "Not Granted")
                diagRow("Microphone", value: micStatusText)
                diagRow("Hotkey", value: appState.shortcutManager.currentCombo.displayString)
                diagRow("Hotkey Registered", value: appState.shortcutManager.isRegistered ? "Yes" : "No")
                if let regError = appState.shortcutManager.registrationError {
                    diagRow("Registration Error", value: regError)
                }
                diagRow("Configured Providers", value: configuredProvidersText)
                diagRow("Primary Provider", value: appState.providerManager.resolvedPrimaryID?.displayName)
                diagRow("Selected Model", value: selectedModelText)
                diagRow("Fallback Provider", value: appState.providerManager.fallbackProvider?.displayName)
                diagRow("OpenRouter Models", value: openRouterModelCountText)
            }

            if !appState.shortcutManager.isRegistered {
                Section("Hotkey Recovery") {
                    Text("The hotkey is not registered. This usually means Input Monitoring permission is not granted for this build of SP Voice.")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Button("Re-register Hotkey") {
                        appState.ensureHotkeyRegistered()
                    }

                    Button("Open Input Monitoring Settings") {
                        appState.permissionsManager.openInputMonitoringSettings()
                    }

                    Button("Reset TCC & Re-register") {
                        appState.resetTCCAndReregister()
                    }
                    .help("Runs tccutil to clear stale Input Monitoring grants for this app, then requests fresh permission.")

                    Text("If the hotkey still won't register after granting Input Monitoring:\n1. Remove SP Voice from Input Monitoring list\n2. Click 'Reset TCC & Re-register'\n3. Re-add SP Voice when prompted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Reset Diagnostics") {
                    appState.diagnosticsService.reset()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var micStatusText: String {
        switch appState.permissionsManager.microphoneStatus {
        case .authorized: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not Determined"
        }
    }

    private var configuredProvidersText: String {
        let names = appState.providerManager.configuredProviders.map(\.displayName)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private var selectedModelText: String {
        guard let id = appState.providerManager.resolvedPrimaryID,
              let model = appState.providerManager.selectedModel(for: id)
        else { return "—" }
        return model.displayName
    }

    private var openRouterModelCountText: String {
        guard let orProvider = appState.providerManager.provider(for: .openrouter) as? OpenRouterProvider else {
            return "—"
        }
        if let count = orProvider.lastDiscoveryCount {
            return "\(orProvider.supportedModels.count) total (\(count) from API)"
        }
        return "\(orProvider.supportedModels.count) built-in"
    }

    @ViewBuilder
    private func diagRow(_ label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(value == nil ? .tertiary : .primary)
        }
    }
}
