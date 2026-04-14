import SwiftUI

struct PermissionStepView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            permissionCard(
                icon: "hand.raised.fill",
                title: "Accessibility",
                description: "Needed to detect the focused text field and insert transcribed text.",
                granted: appState.permissionsManager.accessibilityGranted,
                actionLabel: "Grant",
                action: { appState.permissionsManager.requestAccessibility() }
            )

            permissionCard(
                icon: "mic.fill",
                title: "Microphone",
                description: "Needed to record audio for transcription.",
                granted: appState.permissionsManager.microphoneStatus == .authorized,
                actionLabel: "Grant",
                action: { Task { await appState.permissionsManager.requestMicrophone() } }
            )

            permissionCard(
                icon: "keyboard",
                title: "Input Monitoring",
                description: "Needed to listen for the global hotkey — especially a single modifier key like Right Option.",
                granted: appState.permissionsManager.inputMonitoringGranted,
                actionLabel: "Open Settings",
                action: { appState.permissionsManager.openInputMonitoringSettings() }
            )

            HStack {
                Spacer()
                Button {
                    appState.permissionsManager.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GhostButtonStyle(size: .small))
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(granted ? DS.Gradients.good.opacity(0.18) : DS.Gradients.warn.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(granted ? DS.Gradients.good : DS.Gradients.warn)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Palette.textPrimary)

                    if granted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Granted")
                                .font(DS.Font.caption)
                        }
                        .foregroundStyle(DS.Palette.goodFrom)
                    }

                    Spacer()
                }

                Text(description)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !granted {
                    Button(action: action) {
                        Label(actionLabel, systemImage: "arrow.up.right")
                    }
                    .buttonStyle(GradientButtonStyle(gradient: DS.Gradients.listen, size: .small))
                    .padding(.top, 4)
                }
            }
        }
        .padding(DS.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1)
        )
    }
}
