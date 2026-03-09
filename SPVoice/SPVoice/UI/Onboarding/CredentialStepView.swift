import SwiftUI

struct CredentialStepView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Keys")
                .font(.title2.bold())

            Text("Add at least one provider key. OpenRouter is the default primary provider; OpenAI is used as a fallback when both are configured.")
                .foregroundStyle(.secondary)

            ForEach(ProviderID.allCases, id: \.self) { id in
                providerKeySection(id)
            }

            Text("Keys are stored in macOS Keychain and never leave your machine.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    @ViewBuilder
    private func providerKeySection(_ id: ProviderID) -> some View {
        let provider = appState.providerManager.provider(for: id)
        let isExperimental = provider?.capabilities.isDictationReady == false

        OnboardingKeyEntry(
            providerID: id,
            label: id.displayName + (isExperimental ? " (experimental)" : ""),
            placeholder: id.keyPrefixHint ?? "API key",
            credentialsStore: appState.credentialsStore,
            onSave: { appState.providerManager.refreshAvailableProviders() }
        )
    }
}

/// Reusable inline key entry for onboarding.
private struct OnboardingKeyEntry: View {
    let providerID: ProviderID
    let label: String
    let placeholder: String
    let credentialsStore: CredentialsStoring
    let onSave: () -> Void

    @State private var key = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.headline)

            if credentialsStore.hasCredential(for: providerID) || saved {
                HStack {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Spacer()
                    Button("Change") { saved = false }
                        .controlSize(.small)
                }
            } else {
                HStack {
                    SecureField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        guard !key.isEmpty else { return }
                        try? credentialsStore.store(key: key, for: providerID)
                        key = ""
                        saved = true
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(key.isEmpty)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }
}
