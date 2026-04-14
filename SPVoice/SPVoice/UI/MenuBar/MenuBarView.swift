import SwiftUI

/// Menu bar popover. Glass card with status hero, hotkey keycaps, provider chip,
/// last-transcription preview, and quick actions.
struct MenuBarView: View {

    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header
            hotkeyRow

            if let warning = warningText {
                warningBanner(warning)
            }

            if let preview = appState.lastTranscription, !preview.isEmpty {
                transcriptionPreview(preview)
            }

            Divider().overlay(DS.Palette.strokeSubtle)

            actionBar
        }
        .padding(DS.Space.md)
        .frame(width: 320)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Gradients.surfaceTint)
                    .blendMode(.softLight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Palette.strokeSoft, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }

    // MARK: Header (state hero)

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            heroIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(DS.Font.titleSmall)
                    .foregroundStyle(DS.Palette.textPrimary)

                Text(subtitleText)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }

            Spacer()

            StatusDot(state: appState.dictationState, size: 8)
        }
    }

    @ViewBuilder
    private var heroIcon: some View {
        ZStack {
            Circle()
                .fill(appState.dictationState.accent)
                .frame(width: 38, height: 38)
                .shadow(color: appState.dictationState.accentSolid.opacity(0.5), radius: 10)

            Image(systemName: appState.dictationState.heroIcon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                .frame(width: 38, height: 38)
        )
    }

    private var titleText: String {
        switch appState.dictationState {
        case .idle:         return "SP Voice"
        case .listening:    return "Listening"
        case .transcribing: return "Transcribing"
        case .processing:   return "Polishing"
        case .inserting:    return "Inserting"
        case .success:      return "Delivered"
        case .error:        return "Error"
        }
    }

    private var subtitleText: String {
        switch appState.dictationState {
        case .idle:
            return "Press the hotkey anywhere to dictate"
        case .listening:
            return "Speak naturally"
        case .transcribing, .processing:
            return "One moment…"
        case .inserting:
            return "Sending to focused field"
        case .success(let preview):
            return preview
        case .error(let msg):
            return msg
        }
    }

    // MARK: Hotkey row

    private var hotkeyRow: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "keyboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)

            Text("Hotkey")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.textSecondary)

            Spacer()

            KeycapGroup(display: appState.shortcutManager.currentCombo.displayString, size: 12)

            Text(modeLabel)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.white.opacity(0.06))
                )
        }
    }

    private var modeLabel: String {
        switch appState.shortcutManager.hotkeyMode {
        case .pushToTalk:  return "Hold"
        case .toggleToTalk: return "Toggle"
        }
    }

    // MARK: Warning banner

    private var warningText: String? {
        if !appState.shortcutManager.isRegistered {
            return "Hotkey inactive — check permissions"
        }
        if appState.providerManager.resolvedPrimaryID == nil {
            return "No provider configured"
        }
        return nil
    }

    private func warningBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Gradients.warn)
            Text(text)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(DS.Palette.warnFrom.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .strokeBorder(DS.Palette.warnFrom.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Transcription preview

    private func transcriptionPreview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "text.quote")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
                Text("Last transcription")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                Spacer()
            }

            Text(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1)
        )
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: DS.Space.xs) {
            providerChip

            Spacer()

            Button {
                openSettings()
                appState.bringSettingsWindowToFront()
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(GhostButtonStyle(size: .small))
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(GhostButtonStyle(size: .small))
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit SP Voice")
        }
    }

    @ViewBuilder
    private var providerChip: some View {
        if let id = appState.providerManager.resolvedPrimaryID,
           let model = appState.providerManager.selectedModel(for: id) {
            HStack(spacing: 6) {
                Circle()
                    .fill(DS.Gradients.work)
                    .frame(width: 6, height: 6)
                Text(id.displayName)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("·")
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(model.displayName)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1)
            )
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(DS.Gradients.warn)
                    .frame(width: 6, height: 6)
                Text("No provider")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
    }
}
