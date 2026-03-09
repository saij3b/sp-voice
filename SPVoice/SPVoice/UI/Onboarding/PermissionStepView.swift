import SwiftUI

struct PermissionStepView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Permissions")
                .font(.title2.bold())

            Text("SP Voice needs three permissions to work correctly:")
                .foregroundStyle(.secondary)

            // Accessibility
            permissionRow(
                icon: "hand.raised.fill",
                title: "Accessibility",
                description: "Required to detect the focused text field and insert transcribed text.",
                granted: appState.permissionsManager.accessibilityGranted,
                action: { appState.permissionsManager.requestAccessibility() }
            )

            // Microphone
            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                description: "Required to record audio for transcription.",
                granted: appState.permissionsManager.microphoneStatus == .authorized,
                action: {
                    Task { await appState.permissionsManager.requestMicrophone() }
                }
            )

            permissionRow(
                icon: "keyboard",
                title: "Input Monitoring",
                description: "Required to listen for the global hotkey, especially a single modifier key like Right Option.",
                granted: appState.permissionsManager.inputMonitoringGranted,
                action: { appState.permissionsManager.openInputMonitoringSettings() }
            )

            Spacer()
        }
    }

    @ViewBuilder
    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    if granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !granted {
                    Button("Grant Permission") { action() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }
}
