import SwiftUI

struct DiagnosticsView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            lastOperationCard
            errorsCard
            systemCard
            if !appState.shortcutManager.isRegistered {
                hotkeyRecoveryCard
            }
            resetCard
        }
    }

    private var lastOperationCard: some View {
        SettingsCard(title: "Last operation", subtitle: nil, icon: "clock.arrow.circlepath") {
            diagRow("Provider", value: appState.diagnosticsService.lastProviderUsed)
            diagRow("Model", value: appState.diagnosticsService.lastModelUsed)
            diagRow("Latency", value: appState.diagnosticsService.lastTranscriptionLatencyMs.map { "\($0) ms" })
            diagRow("Insertion strategy", value: appState.diagnosticsService.lastInsertionStrategy)
            diagRow("Focused app", value: appState.diagnosticsService.lastFocusedApp)
            diagRow("Target role", value: appState.diagnosticsService.lastTargetRole)
            diagRow("Bundle ID", value: appState.diagnosticsService.lastTargetBundleID)
            if appState.diagnosticsService.lastTargetIsChromium {
                diagRow("Chromium path", value: "Yes")
            }
        }
    }

    private var errorsCard: some View {
        SettingsCard(title: "Recent errors", subtitle: nil, icon: "exclamationmark.triangle") {
            diagRow("Provider error", value: appState.diagnosticsService.lastProviderError, accent: .error)
            diagRow("Insertion error", value: appState.diagnosticsService.lastInsertionError, accent: .error)
        }
    }

    private var systemCard: some View {
        SettingsCard(title: "System", subtitle: nil, icon: "cpu") {
            diagRow("Sessions", value: "\(appState.diagnosticsService.sessionCount)")
            diagRow("Accessibility", value: appState.permissionsManager.accessibilityGranted ? "Granted" : "Not granted",
                    accent: appState.permissionsManager.accessibilityGranted ? .good : .warn)
            diagRow("Input Monitoring", value: appState.permissionsManager.inputMonitoringGranted ? "Granted" : "Not granted",
                    accent: appState.permissionsManager.inputMonitoringGranted ? .good : .warn)
            diagRow("Microphone", value: micStatusText,
                    accent: appState.permissionsManager.microphoneStatus == .authorized ? .good : .warn)
            diagRow("Hotkey", value: appState.shortcutManager.currentCombo.displayString)
            diagRow("Hotkey registered", value: appState.shortcutManager.isRegistered ? "Yes" : "No",
                    accent: appState.shortcutManager.isRegistered ? .good : .warn)
            if let regError = appState.shortcutManager.registrationError {
                diagRow("Registration error", value: regError, accent: .error)
            }
            diagRow("Configured providers", value: configuredProvidersText)
            diagRow("Primary provider", value: appState.providerManager.resolvedPrimaryID?.displayName)
            diagRow("Selected model", value: selectedModelText)
            diagRow("Fallback provider", value: appState.providerManager.fallbackProvider?.displayName)
            diagRow("OpenRouter models", value: openRouterModelCountText)
        }
    }

    private var hotkeyRecoveryCard: some View {
        SettingsCard(title: "Hotkey recovery", subtitle: "Fix a hotkey that won't register", icon: "wand.and.stars") {
            Text("Input Monitoring permission is usually the cause. Grant it, then re-register.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.warnFrom)

            HStack {
                Button {
                    appState.ensureHotkeyRegistered()
                } label: {
                    Label("Re-register", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GradientButtonStyle(gradient: DS.Gradients.listen, size: .small))

                Button {
                    appState.permissionsManager.openInputMonitoringSettings()
                } label: {
                    Label("Open Input Monitoring", systemImage: "lock.shield")
                }
                .buttonStyle(GhostButtonStyle(size: .small))

                Spacer()

                Button {
                    appState.resetTCCAndReregister()
                } label: {
                    Label("Reset TCC", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(GhostButtonStyle(size: .small))
                .help("Clear stale Input Monitoring grants for SP Voice")
            }
        }
    }

    private var resetCard: some View {
        SettingsCard(title: "Maintenance", subtitle: nil, icon: "hammer") {
            HStack {
                Text("Clear diagnostic counters without affecting permissions or keys")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                Spacer()
                Button {
                    appState.diagnosticsService.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(GhostButtonStyle(size: .small))
            }
        }
    }

    // MARK: - Helpers

    private enum DiagAccent { case none, good, warn, error }

    private var micStatusText: String {
        switch appState.permissionsManager.microphoneStatus {
        case .authorized:   return "Granted"
        case .denied:       return "Denied"
        case .notDetermined: return "Not requested"
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
    private func diagRow(_ label: String, value: String?, accent: DiagAccent = .none) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(DS.Font.bodyMedium)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer(minLength: DS.Space.md)
            Text(value ?? "—")
                .font(DS.Font.captionMono)
                .foregroundStyle(accentColor(accent, hasValue: value != nil))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }

    private func accentColor(_ accent: DiagAccent, hasValue: Bool) -> Color {
        if !hasValue { return DS.Palette.textTertiary }
        switch accent {
        case .none:  return DS.Palette.textPrimary
        case .good:  return DS.Palette.goodFrom
        case .warn:  return DS.Palette.warnFrom
        case .error: return DS.Palette.errorFrom
        }
    }
}
