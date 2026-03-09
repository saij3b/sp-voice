import SwiftUI

/// Compact visual indicator showing the current dictation state.
struct OverlayView: View {

    let state: DictationState
    let audioLevel: Float

    var body: some View {
        HStack(spacing: 8) {
            if state == .listening {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.18))
                        .frame(width: 24, height: 24)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .shadow(color: .red.opacity(0.7), radius: 8)
                }

                ListeningWaveform(audioLevel: audioLevel)
                    .frame(width: 72, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Listening...")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Speak naturally")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
            } else {
                Image(systemName: state.menuBarIcon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .symbolEffect(.pulse, isActive: isActive)

                Text(state.statusText)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.14, blue: 0.20),
                            Color(red: 0.06, green: 0.09, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }

    private var iconColor: Color {
        switch state {
        case .idle: return .white
        case .listening: return .red
        case .transcribing: return .blue
        case .processing: return .purple
        case .inserting: return .green
        case .success: return .green
        case .error: return .orange
        }
    }

    private var isActive: Bool {
        switch state {
        case .listening, .transcribing, .processing: return true
        default: return false
        }
    }
}

private struct ListeningWaveform: View {
    let audioLevel: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let clampedLevel = CGFloat(min(max(audioLevel, 0), 1))
            let liftedLevel = pow(clampedLevel, 0.55)
            let base = max(0.34, min(liftedLevel + 0.22, 1))

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<9, id: \.self) { index in
                    let wave = (sin(time * 8 + (Double(index) * 0.65)) + 1) * 0.5
                    let sway = 7 + (CGFloat(wave) * 18)
                    let height = 5 + (sway * base)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.18, green: 0.57, blue: 1.0),
                                    Color(red: 0.07, green: 0.36, blue: 0.92)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: max(4, height))
                }
            }
            .frame(height: 32)
        }
    }
}
