import SwiftUI

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
        VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text(providerID.rawValue.capitalized)
                .frame(width: 90, alignment: .leading)

            if isEditing {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

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
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    apiKey = ""
                    isEditing = false
                    saveError = nil
                }
            } else {
                if hasKey {
                    Text("••••••••")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Change") { isEditing = true }
                    Button("Remove") {
                        try? appState.credentialsStore.delete(for: providerID)
                        appState.providerManager.refreshAvailableProviders()
                    }
                    .foregroundColor(.red)
                } else {
                    Text("Not configured")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Key") { isEditing = true }
                }
            }
        }
        if let error = saveError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.leading, 94)
        }
        }
    }
}
