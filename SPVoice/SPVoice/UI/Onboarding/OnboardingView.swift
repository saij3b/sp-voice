import SwiftUI

struct OnboardingView: View {

    @EnvironmentObject private var appState: AppState
    @State private var currentStep = 0

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("SP Voice")
                    .font(.largeTitle.bold())
                Text("Global push-to-talk dictation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Step content
            Group {
                switch currentStep {
                case 0:
                    PermissionStepView()
                        .environmentObject(appState)
                case 1:
                    CredentialStepView()
                        .environmentObject(appState)
                case 2:
                    readyStepView
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)

            // Navigation
            HStack {
                // Step indicator
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.blue : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep > 0 {
                    Button("Back") { currentStep -= 1 }
                }

                if currentStep < totalSteps - 1 {
                    Button("Next") { currentStep += 1 }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAdvance)
                } else {
                    Button("Get Started") {
                        appState.completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canFinish)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 560)
    }

    private var canAdvance: Bool {
        switch currentStep {
        case 0: return appState.permissionsManager.allPermissionsGranted
        case 1: return !appState.providerManager.configuredProviders.isEmpty
        default: return true
        }
    }

    private var canFinish: Bool {
        appState.permissionsManager.allPermissionsGranted
            && !appState.providerManager.configuredProviders.isEmpty
    }

    private var readyStepView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("You're all set!")
                .font(.title2.bold())

            Text("Press \(appState.shortcutManager.currentCombo.displayString) to start dictating.\nYour speech will be transcribed and inserted into the focused text field.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let id = appState.providerManager.resolvedPrimaryID {
                Text("Using \(id.rawValue.capitalized) for transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
