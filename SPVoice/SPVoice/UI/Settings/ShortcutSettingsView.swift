import SwiftUI

struct ShortcutSettingsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var isRecordingShortcut = false
    @State private var keyMonitor: Any?

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Current shortcut:")
                    Text(appState.shortcutManager.currentCombo.displayString)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(6)

                    Spacer()

                    Button(isRecordingShortcut ? "Press keys…" : "Record New Shortcut") {
                        if !isRecordingShortcut {
                            startRecordingShortcut()
                        }
                    }
                    .foregroundStyle(isRecordingShortcut ? .orange : .blue)
                }

                HStack {
                    Button("Use Right Option Key") {
                        applyRightOptionPreset()
                    }
                    .controlSize(.small)

                    Text("Single-key toggle dictation (press once to start, press again to stop).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isRecordingShortcut {
                    Text("Press a key or modifier key (e.g. R⌥, ⌥Space, ⌘⇧D). Press Escape to cancel.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Mode") {
                Picker("Hotkey mode", selection: modeBinding) {
                    ForEach(HotkeyMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                HStack {
                    Image(systemName: appState.shortcutManager.isRegistered ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(appState.shortcutManager.isRegistered ? .green : .red)
                    Text(appState.shortcutManager.isRegistered ? "Hotkey is active" : "Hotkey not registered")
                }

                if let error = appState.shortcutManager.registrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)

                    if error.localizedCaseInsensitiveContains("input monitoring") {
                        Button("Open Input Monitoring") {
                            appState.permissionsManager.openInputMonitoringSettings()
                        }
                        .controlSize(.small)
                    }
                }

                if !appState.permissionsManager.inputMonitoringGranted {
                    Text("Input Monitoring permission required for global hotkeys.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !appState.shortcutManager.isRegistered {
                    Button("Retry Registration") {
                        appState.permissionsManager.refresh()
                        appState.shortcutManager.register()
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { appState.permissionsManager.refresh() }
        .onDisappear { stopRecordingShortcut() }
    }

    // MARK: - Key Recorder

    private func startRecordingShortcut() {
        isRecordingShortcut = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .keyDown:
                return handleKeyDownRecorderEvent(event)
            case .flagsChanged:
                return handleModifierRecorderEvent(event)
            default:
                return event
            }
        }
    }

    private func stopRecordingShortcut() {
        isRecordingShortcut = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func applyRightOptionPreset() {
        let combo = ShortcutManager.KeyCombo(keyCode: 61, modifierFlags: 0) // Right Option
        appState.shortcutManager.saveCombo(combo)
        appState.shortcutManager.saveMode(.toggleToTalk)
    }

    private func handleKeyDownRecorderEvent(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // Escape — cancel
            stopRecordingShortcut()
            return nil
        }

        if modifierFlag(for: event.keyCode) != nil {
            return nil
        }

        let relevantMask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let flags = UInt64(event.modifierFlags.intersection(relevantMask).rawValue)

        let combo = ShortcutManager.KeyCombo(
            keyCode: event.keyCode,
            modifierFlags: flags
        )
        appState.shortcutManager.saveCombo(combo)
        stopRecordingShortcut()
        return nil
    }

    private func handleModifierRecorderEvent(_ event: NSEvent) -> NSEvent? {
        guard let changedFlag = modifierFlag(for: event.keyCode) else {
            return event
        }

        // flagsChanged fires on both down and up. Capture only on key down.
        guard event.modifierFlags.contains(changedFlag) else {
            return nil
        }

        let combo = ShortcutManager.KeyCombo(keyCode: event.keyCode, modifierFlags: 0)
        appState.shortcutManager.saveCombo(combo)
        appState.shortcutManager.saveMode(.toggleToTalk)
        stopRecordingShortcut()
        return nil
    }

    private func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 63: return .function
        default: return nil
        }
    }

    // MARK: - Helpers

    private var modeBinding: Binding<HotkeyMode> {
        Binding(
            get: { appState.shortcutManager.hotkeyMode },
            set: { appState.shortcutManager.saveMode($0) }
        )
    }

    private var modeDescription: String {
        switch appState.shortcutManager.hotkeyMode {
        case .pushToTalk: return "Hold the hotkey to record, release to transcribe."
        case .toggleToTalk: return "Press once to start recording, press again to stop and transcribe."
        }
    }
}
