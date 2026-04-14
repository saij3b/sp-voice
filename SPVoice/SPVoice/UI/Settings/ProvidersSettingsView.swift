import SwiftUI

struct ProvidersSettingsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var validationStates: [ProviderID: ValidationState] = [:]
    @State private var showAllModels = false
    @State private var isRefreshingModels = false

    private enum ValidationState {
        case idle, loading, success, failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            routingCard
            apiKeysCard
            optionsCard
        }
    }

    // MARK: Routing (primary + secondary + model)

    private var routingCard: some View {
        SettingsCard(title: "Transcription routing", subtitle: "Primary provider and fallback", icon: "sparkles") {
            SettingsRow(label: "Primary", description: "Used first for every dictation") {
                EmptyView()
            } trailing: {
                Picker("", selection: primaryBinding) {
                    Text("Auto").tag(Optional<ProviderID>.none)
                    ForEach(ProviderID.allCases, id: \.self) { id in
                        Text(id.displayName).tag(Optional(id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }

            if let primaryID = appState.providerManager.resolvedPrimaryID,
               let provider = appState.providerManager.provider(for: primaryID) {
                Divider().overlay(DS.Palette.strokeSubtle)

                SettingsRow(label: "Model", description: "The specific transcription model") {
                    EmptyView()
                } trailing: {
                    modelPicker(for: provider)
                }

                if provider.id == .openrouter {
                    HStack {
                        Button {
                            refreshOpenRouterModels()
                        } label: {
                            Label("Refresh models", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(GhostButtonStyle(size: .small))
                        .disabled(isRefreshingModels)

                        if isRefreshingModels {
                            ProgressView().controlSize(.small)
                        }

                        Spacer()

                        if let count = (provider as? OpenRouterProvider)?.lastDiscoveryCount {
                            Text("\(count) from API")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                        } else {
                            Text("\(provider.supportedModels.count) built-in")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                    }
                }

                if let caveat = provider.capabilities.caveatNote {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Palette.warnFrom)
                        Text(caveat)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Palette.warnFrom)
                    }
                }
            }

            Divider().overlay(DS.Palette.strokeSubtle)

            SettingsRow(label: "Fallback", description: "Used if the primary provider fails") {
                EmptyView()
            } trailing: {
                Picker("", selection: secondaryBinding) {
                    Text("None").tag(Optional<ProviderID>.none)
                    ForEach(ProviderID.allCases, id: \.self) { id in
                        Text(id.displayName).tag(Optional(id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
        }
    }

    // MARK: API Keys

    private var apiKeysCard: some View {
        SettingsCard(title: "API keys", subtitle: "Stored locally — never leaves this Mac", icon: "key") {
            VStack(spacing: DS.Space.sm) {
                ForEach(Array(ProviderID.allCases.enumerated()), id: \.element) { idx, id in
                    VStack(alignment: .leading, spacing: 6) {
                        CredentialEntryView(providerID: id)
                            .environmentObject(appState)

                        if appState.credentialsStore.hasCredential(for: id) {
                            HStack(spacing: 8) {
                                Button {
                                    testConnection(for: id)
                                } label: {
                                    Label("Test connection", systemImage: "bolt.horizontal")
                                }
                                .buttonStyle(GhostButtonStyle(size: .small))
                                .disabled(isValidationLoading(id))

                                validationStatusView(for: id)

                                Spacer()
                            }
                            .padding(.leading, 130)
                        }
                    }
                    if idx < ProviderID.allCases.count - 1 {
                        Divider().overlay(DS.Palette.strokeSubtle)
                    }
                }
            }
        }
    }

    private var optionsCard: some View {
        SettingsCard(title: "Advanced", subtitle: nil, icon: "slider.horizontal.3") {
            SettingsRow(label: "Show all models", description: "Include unverified and experimental models") {
                EmptyView()
            } trailing: {
                Toggle("", isOn: $showAllModels)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DS.Palette.listenFrom)
            }
        }
    }

    // MARK: Test Connection

    @ViewBuilder
    private func validationStatusView(for id: ProviderID) -> some View {
        let state = validationStates[id]
        if case .loading = state {
            ProgressView().controlSize(.small)
        } else if case .success = state {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Valid")
            }
            .font(DS.Font.caption)
            .foregroundStyle(DS.Palette.goodFrom)
        } else if case .failed(let msg) = state {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                Text(msg).lineLimit(1)
            }
            .font(DS.Font.caption)
            .foregroundStyle(DS.Palette.errorFrom)
        }
    }

    private func isValidationLoading(_ id: ProviderID) -> Bool {
        if case .loading = validationStates[id] { return true }
        return false
    }

    private func testConnection(for id: ProviderID) {
        validationStates[id] = .loading
        Task {
            do {
                try await appState.providerManager.provider(for: id)?.validateCredentials()
                validationStates[id] = .success
            } catch {
                validationStates[id] = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Bindings

    private var primaryBinding: Binding<ProviderID?> {
        Binding(
            get: { appState.providerManager.primaryProviderID },
            set: { appState.providerManager.setPrimary($0) }
        )
    }

    private var secondaryBinding: Binding<ProviderID?> {
        Binding(
            get: { appState.providerManager.secondaryProviderID },
            set: { appState.providerManager.setSecondary($0) }
        )
    }

    // MARK: Model picker

    @ViewBuilder
    private func modelPicker(for provider: TranscriptionProvider) -> some View {
        let baseModels = showAllModels
            ? provider.supportedModels
            : provider.supportedModels.filter(\.isDictationCapable)
        let models = modelsIncludingSavedSelection(baseModels, for: provider.id)
        if !models.isEmpty {
            Picker("", selection: modelBinding(for: provider.id)) {
                ForEach(models, id: \.id) { model in
                    Text(model.displayName + (model.isDictationCapable ? "" : "  (unverified)"))
                        .tag(model.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 260)
        }
    }

    private func refreshOpenRouterModels() {
        isRefreshingModels = true
        Task {
            if let orProvider = appState.providerManager.provider(for: .openrouter) as? OpenRouterProvider {
                await orProvider.refreshModels()
                appState.providerManager.objectWillChange.send()
            }
            isRefreshingModels = false
        }
    }

    private func modelBinding(for id: ProviderID) -> Binding<String> {
        Binding(
            get: {
                appState.providerManager.selectedModel(for: id)?.id
                    ?? appState.providerManager.provider(for: id)?.defaultModel.id
                    ?? ""
            },
            set: { appState.providerManager.setModel($0, for: id) }
        )
    }

    private func modelsIncludingSavedSelection(
        _ models: [TranscriptionModel],
        for providerID: ProviderID
    ) -> [TranscriptionModel] {
        guard let savedModelID = appState.providerManager.selectedModelPerProvider[providerID.rawValue],
              !savedModelID.isEmpty,
              !models.contains(where: { $0.id == savedModelID })
        else { return models }

        var merged = models
        merged.insert(
            TranscriptionModel(
                id: savedModelID,
                displayName: "\(savedModelID) (saved)",
                provider: providerID,
                isDictationCapable: true
            ),
            at: 0
        )
        return merged
    }
}
