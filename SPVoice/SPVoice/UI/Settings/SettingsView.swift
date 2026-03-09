import SwiftUI

/// Tabbed settings window.
struct SettingsView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .environmentObject(appState)

            ProvidersSettingsView()
                .tabItem { Label("Providers", systemImage: "cloud") }
                .environmentObject(appState)

            ShortcutSettingsView()
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
                .environmentObject(appState)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .environmentObject(appState)

            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .environmentObject(appState)
        }
        .frame(width: 520, height: 420)
    }
}
