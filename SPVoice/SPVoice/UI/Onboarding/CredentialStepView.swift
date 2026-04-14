import SwiftUI

struct CredentialStepView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Add at least one provider key. OpenRouter is a great default primary; OpenAI makes a strong fallback.")
                .font(DS.Font.body)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DS.Space.sm) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    providerCard(id)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
                Text("Keys are stored locally in macOS preferences. They never leave this machine.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func providerCard(_ id: ProviderID) -> some View {
        let provider = appState.providerManager.provider(for: id)
        let isExperimental = provider?.capabilities.isDictationReady == false

        OnboardingKeyEntry(
            providerID: id,
            label: id.displayName,
            experimental: isExperimental,
            placeholder: id.keyPrefixHint ?? "API key",
            credentialsStore: appState.credentialsStore,
            onSave: { appState.providerManager.refreshAvailableProviders() }
        )
    }
}

/// Glass-styled API key entry row for the onboarding flow.
private struct OnboardingKeyEntry: View {
    let providerID: ProviderID
    let label: String
    let experimental: Bool
    let placeholder: String
    let credentialsStore: CredentialsStoring
    let onSave: () -> Void

    @State private var key = ""
    @State private var saved = false
    @State private var saveError: String? = nil

    private var hasKey: Bool { credentialsStore.hasCredential(for: providerID) || saved }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.sm) {
            // Logo badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hasKey ? DS.Gradients.good : DS.Gradients.work)
                    .frame(width: 36, height: 36)
                Image(systemName: hasKey ? "checkmark" : "key.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(DS.Font.bodyMedium)
                        .foregroundStyle(DS.Palette.textPrimary)
                    if experimental {
                        Text("experimental")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Palette.warnFrom)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.Palette.warnFrom.opacity(0.12)))
                    }
                }

                if hasKey {
                    Text("Saved")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.goodFrom)
                } else if let error = saveError {
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.errorFrom)
                        .lineLimit(1)
                } else {
                    Text(placeholder)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }

            Spacer()

            if hasKey {
                Button("Change") {
                    saved = false
                    saveError = nil
                }
                .buttonStyle(GhostButtonStyle(size: .small))
            } else {
                SecureField("", text: $key)
                    .textFieldStyle(.plain)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: 180)
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
                    guard !key.isEmpty else { return }
                    do {
                        try credentialsStore.store(key: key, for: providerID)
                        key = ""
                        saved = true
                        saveError = nil
                        onSave()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .buttonStyle(GradientButtonStyle(gradient: DS.Gradients.listen, size: .small))
                .disabled(key.isEmpty)
            }
        }
        .padding(DS.Space.sm)
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
