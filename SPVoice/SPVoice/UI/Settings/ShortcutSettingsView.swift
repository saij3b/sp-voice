import SwiftUI

struct ShortcutSettingsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var isRecordingShortcut = false
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            currentShortcutCard
            modeCard
            statusCard
        }
        .onAppear { appState.permissionsManager.refresh() }
        .onDisappear { stopRecordingShortcut() }
    }

    // MARK: Current shortcut

    private var currentShortcutCard: some View {
        SettingsCard(title: "Global hotkey", subtitle: "The key combination used to start dictation", icon: "command") {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                // Big keycap display
                HStack {
                    Spacer()
                    KeycapGroup(
                        display: appState.shortcutManager.currentCombo.displayString,
                        size: 22
                    )
                    Spacer()
                }
                .padding(.vertical, DS.Space.md)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1)
                )

                HStack(spacing: DS.Space.xs) {
                    Button {
                        if !isRecordingShortcut { startRecordingShortcut() }
                    } label: {
                        Label(
                            isRecordingShortcut ? "Press any key…" : "Record new shortcut",
                            systemImage: isRecordingShortcut ? "dot.radiowaves.left.and.right" : "record.circle"
                        )
                    }
                    .buttonStyle(GradientButtonStyle(
                        gradient: isRecordingShortcut ? DS.Gradients.warn : DS.Gradients.listen,
                        size: .small
                    ))

                    Button {
                        applyRightOptionPreset()
                    } label: {
                        Label("Use Right ⌥", systemImage: "option")
                    }
                    .buttonStyle(GhostButtonStyle(size: .small))

                    Spacer()
                }

                if isRecordingShortcut {
                    Text("Press any key or modifier (e.g. R⌥, ⌥Space, ⌘⇧D). Press Escape to cancel.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.warnFrom)
                } else {
                    Text("Tip: Right Option (R⌥) makes a great single-key toggle.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
    }

    // MARK: Mode

    private var modeCard: some View {
        SettingsCard(title: "Activation", subtitle: "How the hotkey starts and stops recording", icon: "hand.tap") {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(HotkeyMode.allCases, id: \.self) { mode in
                        modeButton(mode)
                    }
                }

                Text(modeDescription)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func modeButton(_ mode: HotkeyMode) -> some View {
        let isSelected = appState.shortcutManager.hotkeyMode == mode
        Button {
            appState.shortcutManager.saveMode(mode)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode == .pushToTalk ? "hand.point.up.left" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Text(mode.displayName)
                    .font(DS.Font.bodyMedium)
            }
            .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .strokeBorder(isSelected ? DS.Palette.strokeEdge : DS.Palette.strokeSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Status

    private var statusCard: some View {
        SettingsCard(title: "Status", subtitle: nil, icon: "waveform.path.ecg") {
            HStack(spacing: DS.Space.sm) {
                Circle()
                    .fill(appState.shortcutManager.isRegistered ? DS.Gradients.good : DS.Gradients.error)
                    .frame(width: 10, height: 10)
                    .shadow(color: (appState.shortcutManager.isRegistered ? DS.Palette.goodFrom : DS.Palette.errorFrom).opacity(0.6), radius: 4)

                Text(appState.shortcutManager.isRegistered ? "Hotkey is active" : "Hotkey not registered")
                    .font(DS.Font.bodyMedium)
                    .foregroundStyle(DS.Palette.textPrimary)

                Spacer()

                if !appState.shortcutManager.isRegistered {
                    Button {
                        appState.permissionsManager.refresh()
                        appState.shortcutManager.register()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GhostButtonStyle(size: .small))
                }
            }

            if let error = appState.shortcutManager.registrationError {
                Divider().overlay(DS.Palette.strokeSubtle)
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.errorFrom)
                    if error.localizedCaseInsensitiveContains("input monitoring") {
                        Button("Open Input Monitoring") {
                            appState.permissionsManager.openInputMonitoringSettings()
                        }
                        .buttonStyle(GhostButtonStyle(size: .small))
                    }
                }
            }

            if !appState.permissionsManager.inputMonitoringGranted {
                Text("Input Monitoring permission is required for global hotkeys.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.warnFrom)
            }
        }
    }

    // MARK: - Key Recorder

    private func startRecordingShortcut() {
        isRecordingShortcut = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .keyDown:      return handleKeyDownRecorderEvent(event)
            case .flagsChanged: return handleModifierRecorderEvent(event)
            default:            return event
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
        let combo = ShortcutManager.KeyCombo(keyCode: 61, modifierFlags: 0)
        appState.shortcutManager.saveCombo(combo)
        appState.shortcutManager.saveMode(.toggleToTalk)
    }

    private func handleKeyDownRecorderEvent(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {
            stopRecordingShortcut()
            return nil
        }
        if modifierFlag(for: event.keyCode) != nil { return nil }

        let relevantMask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let flags = UInt64(event.modifierFlags.intersection(relevantMask).rawValue)

        let combo = ShortcutManager.KeyCombo(keyCode: event.keyCode, modifierFlags: flags)
        appState.shortcutManager.saveCombo(combo)
        stopRecordingShortcut()
        return nil
    }

    private func handleModifierRecorderEvent(_ event: NSEvent) -> NSEvent? {
        guard let changedFlag = modifierFlag(for: event.keyCode) else { return event }
        guard event.modifierFlags.contains(changedFlag) else { return nil }

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
        case 63:     return .function
        default:     return nil
        }
    }

    private var modeDescription: String {
        switch appState.shortcutManager.hotkeyMode {
        case .pushToTalk:   return "Hold the hotkey to record, release to transcribe."
        case .toggleToTalk: return "Press once to start recording, press again to stop."
        }
    }
}
