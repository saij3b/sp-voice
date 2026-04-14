import SwiftUI

/// Inline API-key entry used by the Providers pane.
/// Glass-styled, password-prompt-free (UserDefaults backed).
struct CredentialEntryView: View {

    let providerID: ProviderID
    @EnvironmentObject private var appState: AppState
    @State private var apiKey: String = ""
    @State private var isEditing: Bool = false
    @State private var saveError: String? = nil

    private var hasKey: Bool {
        appState.credentialsStore.hasCredential(for: providerID)
    }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            providerBadge

            if isEditing {
                SecureField(providerID.keyPrefixHint ?? "API key", text: $apiKey)
                    .textFieldStyle(.plain)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .strokeBorder(DS.Palette.strokeEdge, lineWidth: 1)
                    )

                Button("Save") {
                    guard !apiKey.isEmpty else { return }
                    do {
                        try appState.credentialsStore.store(key: apiKey, for: providerID)
                        apiKey = ""
                        isEditing = false
                        saveError = nil
                        appState.providerManager.refreshAvailableProviders()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .buttonStyle(GradientButtonStyle(gradient: DS.Gradients.good, size: .small))
                .disabled(apiKey.isEmpty)

                Button("Cancel") {
                    apiKey = ""
                    isEditing = false
                    saveError = nil
                }
                .buttonStyle(GhostButtonStyle(size: .small))
            } else {
                if hasKey {
                    Text("••••••••")
                        .font(DS.Font.bodyMedium)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    Button("Change") { isEditing = true }
                        .buttonStyle(GhostButtonStyle(size: .small))
                    Button {
                        try? appState.credentialsStore.delete(for: providerID)
                        appState.providerManager.refreshAvailableProviders()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(GhostButtonStyle(size: .small))
                    .help("Remove API key")
                } else {
                    Text("Not configured")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                    Spacer()
                    Button("Add key") { isEditing = true }
                        .buttonStyle(GradientButtonStyle(gradient: DS.Gradients.listen, size: .small))
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let error = saveError {
                Text(error)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.errorFrom)
                    .offset(y: 24)
            }
        }
    }

    private var providerBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(hasKey ? DS.Gradients.good : DS.Gradients.work)
                .frame(width: 8, height: 8)
            Text(providerID.displayName)
                .font(DS.Font.bodyMedium)
                .foregroundStyle(DS.Palette.textPrimary)
                .frame(width: 110, alignment: .leading)
        }
    }
}
