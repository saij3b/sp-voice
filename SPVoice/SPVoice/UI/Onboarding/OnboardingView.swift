import SwiftUI

struct OnboardingView: View {

    @EnvironmentObject private var appState: AppState
    @State private var currentStep = 0
    @State private var heroPulse = false

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            heroHeader

            // Step content
            ScrollView {
                Group {
                    switch currentStep {
                    case 0: PermissionStepView().environmentObject(appState)
                    case 1: CredentialStepView().environmentObject(appState)
                    case 2: readyStep
                    default: EmptyView()
                    }
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.lg)
            }
            .scrollContentBackground(.hidden)

            navBar
        }
        .frame(width: 560, height: 620)
        .glassWindowBackground()
    }

    // MARK: Hero

    private var heroHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                // Glow
                Circle()
                    .fill(DS.Gradients.listen)
                    .frame(width: 88, height: 88)
                    .blur(radius: 20)
                    .opacity(0.55)
                    .scaleEffect(heroPulse ? 1.12 : 0.95)

                // Core badge
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(DS.Gradients.listen)
                    .frame(width: 72, height: 72)
                    .shadow(color: DS.Palette.listenFrom.opacity(0.6), radius: 18)

                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 100)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                    heroPulse.toggle()
                }
            }

            Text(stepTitle)
                .font(DS.Font.title)
                .foregroundStyle(DS.Palette.textPrimary)

            Text(stepSubtitle)
                .font(DS.Font.body)
                .foregroundStyle(DS.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .padding(.top, DS.Space.xl)
        .padding(.bottom, DS.Space.md)
        .frame(maxWidth: .infinity)
    }

    private var stepTitle: String {
        switch currentStep {
        case 0: return "Welcome to SP Voice"
        case 1: return "Connect a provider"
        case 2: return "You're all set"
        default: return ""
        }
    }

    private var stepSubtitle: String {
        switch currentStep {
        case 0: return "Grant three permissions so dictation can capture audio, detect the focused field, and listen for your hotkey."
        case 1: return "Add an API key from OpenAI, Groq, or OpenRouter. Keys stay on this Mac."
        case 2: return "Press your hotkey anywhere to dictate. Text is inserted into whatever field you're focused on."
        default: return ""
        }
    }

    // MARK: Ready step

    private var readyStep: some View {
        VStack(spacing: DS.Space.lg) {
            ZStack {
                Circle()
                    .fill(DS.Gradients.good)
                    .frame(width: 78, height: 78)
                    .shadow(color: DS.Palette.goodFrom.opacity(0.7), radius: 16)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Your hotkey")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                KeycapGroup(display: appState.shortcutManager.currentCombo.displayString, size: 22)
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1)
            )

            if let id = appState.providerManager.resolvedPrimaryID {
                HStack(spacing: 6) {
                    Circle()
                        .fill(DS.Gradients.work)
                        .frame(width: 6, height: 6)
                    Text("Using \(id.displayName)")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
        }
    }

    // MARK: Navigation bar

    private var navBar: some View {
        HStack(spacing: DS.Space.sm) {
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step == currentStep ? DS.Gradients.listen : LinearGradient(colors: [Color.white.opacity(0.12)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: step == currentStep ? 22 : 8, height: 6)
                        .animation(DS.Motion.snappy, value: currentStep)
                }
            }

            Spacer()

            if currentStep > 0 {
                Button("Back") {
                    withAnimation(DS.Motion.snappy) { currentStep -= 1 }
                }
                .buttonStyle(GhostButtonStyle(size: .regular))
            }

            if currentStep < totalSteps - 1 {
                Button {
                    withAnimation(DS.Motion.snappy) { currentStep += 1 }
                } label: {
                    Label("Next", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(GradientButtonStyle(gradient: DS.Gradients.listen, size: .regular))
                .disabled(!canAdvance)
                .opacity(canAdvance ? 1 : 0.5)
            } else {
                Button {
                    appState.completeOnboarding()
                } label: {
                    Label("Start dictating", systemImage: "sparkles")
                }
                .buttonStyle(GradientButtonStyle(gradient: DS.Gradients.good, size: .regular))
                .disabled(!canFinish)
                .opacity(canFinish ? 1 : 0.5)
            }
        }
        .padding(DS.Space.lg)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.15))
                .overlay(
                    Rectangle()
                        .fill(DS.Palette.strokeSubtle)
                        .frame(height: 1),
                    alignment: .top
                )
        )
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
}
