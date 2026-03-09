import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {

    @EnvironmentObject private var appState: AppState
    @AppStorage(SPVoiceConstants.UserDefaultsKeys.autoInsertEnabled) private var autoInsert = true
    @AppStorage(SPVoiceConstants.UserDefaultsKeys.historyEnabled) private var historyEnabled = true
    @AppStorage(SPVoiceConstants.UserDefaultsKeys.textProcessingMode) private var processingMode = TextProcessingMode.rawDictation.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Dictation") {
                Toggle("Auto-insert into focused field", isOn: $autoInsert)

                Picker("Text processing", selection: $processingMode) {
                    ForEach(TextProcessingMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
            }

            Section("History") {
                Toggle("Save dictation history", isOn: $historyEnabled)
                if historyEnabled {
                    Button("Clear History") {
                        appState.historyStore.clear()
                    }
                }
            }

            Section("Permissions") {
                HStack {
                    Label(
                        appState.permissionsManager.accessibilityGranted ? "Accessibility: Granted" : "Accessibility: Not Granted",
                        systemImage: appState.permissionsManager.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(appState.permissionsManager.accessibilityGranted ? .green : .red)

                    Spacer()

                    if !appState.permissionsManager.accessibilityGranted {
                        Button("Open Settings") { appState.permissionsManager.openAccessibilitySettings() }
                    }
                }

                HStack {
                    Label(
                        appState.permissionsManager.inputMonitoringGranted ? "Input Monitoring: Granted" : "Input Monitoring: Not Granted",
                        systemImage: appState.permissionsManager.inputMonitoringGranted ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(appState.permissionsManager.inputMonitoringGranted ? .green : .red)

                    Spacer()

                    if !appState.permissionsManager.inputMonitoringGranted {
                        Button("Open Settings") { appState.permissionsManager.openInputMonitoringSettings() }
                    }
                }

                HStack {
                    let micStatus = appState.permissionsManager.microphoneStatus
                    Label(
                        micStatus == .authorized ? "Microphone: Granted" : (micStatus == .denied ? "Microphone: Denied" : "Microphone: Not Requested"),
                        systemImage: micStatus == .authorized ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(micStatus == .authorized ? .green : .red)

                    Spacer()

                    if micStatus == .notDetermined {
                        Button("Request Permission") {
                            Task { await appState.permissionsManager.requestMicrophone() }
                        }
                    } else if micStatus == .denied {
                        Button("Open Settings") { appState.permissionsManager.openMicrophoneSettings() }
                    }
                }

                HStack {
                    Label(
                        appState.shortcutManager.isRegistered ? "Hotkey: Registered" : "Hotkey: Not Registered",
                        systemImage: appState.shortcutManager.isRegistered ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(appState.shortcutManager.isRegistered ? .green : .red)

                    Spacer()

                    if !appState.shortcutManager.isRegistered {
                        Button("Re-register") {
                            appState.ensureHotkeyRegistered()
                        }
                    }
                }

                Button("Refresh Permissions") {
                    appState.permissionsManager.refresh()
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { appState.permissionsManager.refresh() }
    }
}
