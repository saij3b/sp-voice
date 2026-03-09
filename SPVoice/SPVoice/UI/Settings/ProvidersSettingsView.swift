import SwiftUI

struct ProvidersSettingsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var validationStates: [ProviderID: ValidationState] = [:]
    @State private var showAllModels = false

    private enum ValidationState {
        case idle, loading, success, failed(String)
    }

    var body: some View {
        Form {
            Section("Primary Provider") {
                Picker("Provider", selection: primaryBinding) {
                    Text("Auto").tag(Optional<ProviderID>.none)
                    ForEach(ProviderID.allCases, id: \.self) { id in
                        providerLabel(id).tag(Optional(id))
                    }
                }

                if let primaryID = appState.providerManager.resolvedPrimaryID,
                   let provider = appState.providerManager.provider(for: primaryID) {
                    modelPicker(for: provider)

                    if let caveat = provider.capabilities.caveatNote {
                        Text(caveat)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Secondary Provider (Fallback)") {
                Picker("Provider", selection: secondaryBinding) {
                    Text("None").tag(Optional<ProviderID>.none)
                    ForEach(ProviderID.allCases, id: \.self) { id in
                        providerLabel(id).tag(Optional(id))
                    }
                }
            }

            Section("API Keys") {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    VStack(alignment: .leading, spacing: 4) {
                        CredentialEntryView(providerID: id)
                            .environmentObject(appState)

                        if appState.credentialsStore.hasCredential(for: id) {
                            HStack(spacing: 8) {
                                testConnectionButton(for: id)
                                validationStatusView(for: id)
                            }
                            .padding(.leading, 90)
                        }
                    }
                }
            }

            Section {
                Toggle("Show all models (including unverified)", isOn: $showAllModels)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Test Connection

    @ViewBuilder
    private func testConnectionButton(for id: ProviderID) -> some View {
        let isLoading = isValidationLoading(id)
        Button("Test Connection") {
            testConnection(for: id)
        }
        .controlSize(.small)
        .disabled(isLoading)
    }

    @ViewBuilder
    private func validationStatusView(for id: ProviderID) -> some View {
        let state = validationStates[id]
        if case .loading = state {
            ProgressView()
                .controlSize(.small)
        } else if case .success = state {
            Label("Valid", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if case .failed(let msg) = state {
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
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

    // MARK: - Bindings

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

    @ViewBuilder
    private func providerLabel(_ id: ProviderID) -> some View {
        let caps = appState.providerManager.provider(for: id)?.capabilities
        HStack {
            Text(id.displayName)
            if caps?.isDictationReady == false {
                Text("(experimental)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func modelPicker(for provider: TranscriptionProvider) -> some View {
        let baseModels = showAllModels
            ? provider.supportedModels
            : provider.supportedModels.filter(\.isDictationCapable)
        let models = modelsIncludingSavedSelection(baseModels, for: provider.id)
        if !models.isEmpty {
            Picker("Model", selection: modelBinding(for: provider.id)) {
                ForEach(models, id: \.id) { model in
                    HStack {
                        Text(model.displayName)
                        if !model.isDictationCapable {
                            Text("(unverified)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .tag(model.id)
                }
            }

            if provider.id == .openrouter {
                HStack {
                    Button("Refresh Models") {
                        refreshOpenRouterModels()
                    }
                    .controlSize(.small)
                    .disabled(isRefreshingModels)

                    if isRefreshingModels {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let count = (provider as? OpenRouterProvider)?.lastDiscoveryCount {
                        Text("\(count) from API")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(provider.supportedModels.count) built-in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @State private var isRefreshingModels = false

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
