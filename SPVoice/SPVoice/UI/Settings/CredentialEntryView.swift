import SwiftUI

struct CredentialEntryView: View {

    let providerID: ProviderID
    @EnvironmentObject private var appState: AppState
    @State private var apiKey: String = ""
    @State private var isEditing: Bool = false

    private var hasKey: Bool {
        appState.credentialsStore.hasCredential(for: providerID)
    }

    var body: some View {
        HStack {
            Text(providerID.rawValue.capitalized)
                .frame(width: 90, alignment: .leading)

            if isEditing {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    guard !apiKey.isEmpty else { return }
                    try? appState.credentialsStore.store(key: apiKey, for: providerID)
                    apiKey = ""
                    isEditing = false
                    appState.providerManager.refreshAvailableProviders()
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    apiKey = ""
                    isEditing = false
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
    }
}
