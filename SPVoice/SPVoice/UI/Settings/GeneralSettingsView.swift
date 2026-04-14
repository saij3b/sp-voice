import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {

    @EnvironmentObject private var appState: AppState
    @AppStorage(SPVoiceConstants.UserDefaultsKeys.autoInsertEnabled) private var autoInsert = true
    @AppStorage(SPVoiceConstants.UserDefaultsKeys.historyEnabled) private var historyEnabled = true
    @AppStorage(SPVoiceConstants.UserDefaultsKeys.textProcessingMode) private var processingMode = TextProcessingMode.rawDictation.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            startupCard
            dictationCard
            historyCard
            permissionsCard
        }
        .onAppear { appState.permissionsManager.refresh() }
    }

    // MARK: Startup

    private var startupCard: some View {
        SettingsCard(title: "Startup", subtitle: "Launch behavior", icon: "power") {
            SettingsRow(label: "Launch at login", description: "Start SP Voice when you sign in") {
                EmptyView()
            } trailing: {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DS.Palette.listenFrom)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
    }

    // MARK: Dictation

    private var dictationCard: some View {
        SettingsCard(title: "Dictation", subtitle: "How transcriptions are delivered", icon: "waveform") {
            SettingsRow(label: "Auto-insert into focused field", description: "Paste transcribed text into the active app") {
                EmptyView()
            } trailing: {
                Toggle("", isOn: $autoInsert)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DS.Palette.listenFrom)
            }

            Divider().overlay(DS.Palette.strokeSubtle)

            SettingsRow(label: "Text processing", description: "Apply cleanup or AI polishing to raw speech") {
                EmptyView()
            } trailing: {
                Picker("", selection: $processingMode) {
                    ForEach(TextProcessingMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
        }
    }

    // MARK: History

    private var historyCard: some View {
        SettingsCard(title: "History", subtitle: "Keep a local log of recent dictations", icon: "clock") {
            SettingsRow(label: "Save dictation history", description: "Entries are stored on-device only") {
                EmptyView()
            } trailing: {
                Toggle("", isOn: $historyEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DS.Palette.listenFrom)
            }

            if historyEnabled {
                Divider().overlay(DS.Palette.strokeSubtle)
                HStack {
                    Text("\(appState.historyStore.entries.count) entries saved")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                    Spacer()
                    Button {
                        appState.historyStore.clear()
                    } label: {
                        Label("Clear history", systemImage: "trash")
                    }
                    .buttonStyle(GhostButtonStyle(size: .small))
                }
            }
        }
    }

    // MARK: Permissions

    private var permissionsCard: some View {
        SettingsCard(title: "Permissions", subtitle: "Grants are permanent once given", icon: "lock.shield") {
            permissionRow(
                title: "Accessibility",
                granted: appState.permissionsManager.accessibilityGranted,
                action: appState.permissionsManager.accessibilityGranted ? nil : ("Open Settings", { appState.permissionsManager.openAccessibilitySettings() })
            )
            Divider().overlay(DS.Palette.strokeSubtle)
            permissionRow(
                title: "Input Monitoring",
                granted: appState.permissionsManager.inputMonitoringGranted,
                action: appState.permissionsManager.inputMonitoringGranted ? nil : ("Open Settings", { appState.permissionsManager.openInputMonitoringSettings() })
            )
            Divider().overlay(DS.Palette.strokeSubtle)
            micRow
            Divider().overlay(DS.Palette.strokeSubtle)
            hotkeyRow

            HStack {
                Spacer()
                Button {
                    appState.permissionsManager.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GhostButtonStyle(size: .small))
            }
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool, action: (String, () -> Void)?) -> some View {
        HStack(spacing: DS.Space.sm) {
            Circle()
                .fill(granted ? DS.Gradients.good : DS.Gradients.warn)
                .frame(width: 10, height: 10)
                .shadow(color: (granted ? DS.Palette.goodFrom : DS.Palette.warnFrom).opacity(0.6), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.bodyMedium)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(granted ? "Granted" : "Not granted")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer()
            if let (label, handler) = action {
                Button(label, action: handler)
                    .buttonStyle(GhostButtonStyle(size: .small))
            }
        }
        .padding(.vertical, 4)
    }

    private var micRow: some View {
        let status = appState.permissionsManager.microphoneStatus
        let granted = status == .authorized
        let title = "Microphone"
        let subtitle: String = {
            switch status {
            case .authorized: return "Granted"
            case .denied: return "Denied"
            case .notDetermined: return "Not requested"
            }
        }()

        return HStack(spacing: DS.Space.sm) {
            Circle()
                .fill(granted ? DS.Gradients.good : DS.Gradients.warn)
                .frame(width: 10, height: 10)
                .shadow(color: (granted ? DS.Palette.goodFrom : DS.Palette.warnFrom).opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.bodyMedium).foregroundStyle(DS.Palette.textPrimary)
                Text(subtitle).font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer()
            if status == .notDetermined {
                Button("Request") {
                    Task { await appState.permissionsManager.requestMicrophone() }
                }
                .buttonStyle(GhostButtonStyle(size: .small))
            } else if status == .denied {
                Button("Open Settings") {
                    appState.permissionsManager.openMicrophoneSettings()
                }
                .buttonStyle(GhostButtonStyle(size: .small))
            }
        }
        .padding(.vertical, 4)
    }

    private var hotkeyRow: some View {
        HStack(spacing: DS.Space.sm) {
            Circle()
                .fill(appState.shortcutManager.isRegistered ? DS.Gradients.good : DS.Gradients.warn)
                .frame(width: 10, height: 10)
                .shadow(color: (appState.shortcutManager.isRegistered ? DS.Palette.goodFrom : DS.Palette.warnFrom).opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hotkey").font(DS.Font.bodyMedium).foregroundStyle(DS.Palette.textPrimary)
                Text(appState.shortcutManager.isRegistered ? "Registered and active" : "Not registered")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer()
            if !appState.shortcutManager.isRegistered {
                Button("Re-register") {
                    appState.ensureHotkeyRegistered()
                }
                .buttonStyle(GhostButtonStyle(size: .small))
            }
        }
        .padding(.vertical, 4)
    }
}
