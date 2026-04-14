import SwiftUI

/// Floating dictation pill. Displays the current state as an animated glass capsule
/// with a live audio waveform. Inspired by Wispr Flow × Superwhisper × visionOS.
struct OverlayView: View {
    let state: DictationState
    let audioLevel: Float

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            stateIcon
            content
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, 10)
        .frame(height: 52)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(DS.Gradients.surfaceTint)
                        .blendMode(.softLight)
                )
        )
        .overlay(
            // outer subtle gradient ring tied to state
            Capsule(style: .continuous)
                .strokeBorder(state.accent, lineWidth: 1)
                .opacity(state.isActive ? 0.8 : 0.35)
        )
        .overlay(
            // inner edge light (visionOS sheen)
            Capsule(style: .continuous)
                .strokeBorder(DS.Gradients.glassSheen, lineWidth: 1)
                .blendMode(.plusLighter)
                .opacity(0.7)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .shadow(color: state.accentSolid.opacity(state.isActive ? 0.35 : 0), radius: 24, y: 0)
        .animation(DS.Motion.smooth, value: state)
    }

    // MARK: Leading icon / pulse

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .listening:
            RecordingGlyph(audioLevel: audioLevel)
        case .transcribing, .processing, .inserting:
            ShimmerGlyph(gradient: state.accent)
        case .success:
            SuccessGlyph()
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.Gradients.error)
                .frame(width: 28, height: 28)
        case .idle:
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.Palette.iconIdle)
                .frame(width: 28, height: 28)
        }
    }

    // MARK: Trailing content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .listening:
            HStack(spacing: DS.Space.sm) {
                Waveform(audioLevel: audioLevel, gradient: state.accent)
                    .frame(width: 90, height: 28)
                Text("Listening")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Palette.textPrimary)
            }
        case .transcribing:
            Text("Transcribing")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Palette.textPrimary)
        case .processing:
            Text("Processing")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Palette.textPrimary)
        case .inserting:
            Text("Inserting")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Palette.textPrimary)
        case .success(let preview):
            Text(preview)
                .font(DS.Font.bodyMedium)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .leading)
        case .error(let message):
            Text(message)
                .font(DS.Font.bodyMedium)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 280, alignment: .leading)
        case .idle:
            Text("Ready")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }
}

// MARK: - Recording Glyph (live mic with pulsing ring)

private struct RecordingGlyph: View {
    let audioLevel: Float
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Soft outer pulse tied to audio level
            Circle()
                .fill(DS.Gradients.listen)
                .frame(width: 28, height: 28)
                .scaleEffect(1 + CGFloat(min(max(audioLevel, 0), 1)) * 0.35)
                .opacity(0.45)
                .blur(radius: 6)

            Circle()
                .fill(DS.Gradients.listen)
                .frame(width: 22, height: 22)
                .shadow(color: DS.Palette.listenFrom.opacity(0.8), radius: 8)

            Image(systemName: "mic.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
    }
}

// MARK: - Shimmer Glyph (transcribing / processing / inserting)

private struct ShimmerGlyph: View {
    let gradient: LinearGradient
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(gradient, lineWidth: 2.4)
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(phase))
                .mask(
                    AngularGradient(
                        colors: [.clear, .white, .white, .clear],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    )
                )

            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 360
            }
        }
    }
}

// MARK: - Success Glyph

private struct SuccessGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DS.Gradients.good)
                .frame(width: 24, height: 24)
                .shadow(color: DS.Palette.goodFrom.opacity(0.7), radius: 8)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Waveform (live audio bars)

private struct Waveform: View {
    let audioLevel: Float
    let gradient: LinearGradient
    private let barCount = 11

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let level = CGFloat(min(max(audioLevel, 0), 1))
            // perceptual boost — quieter sounds should still be visible
            let lifted = pow(level, 0.55)
            let baseAmp = max(0.22, min(lifted + 0.15, 1))

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = Double(i) * 0.42
                    // combine two sines for organic motion
                    let wave = (sin(t * 7.5 + phase) + sin(t * 11 + phase * 1.3)) * 0.25 + 0.5
                    // center bars are taller than edges (smile-shape)
                    let centerBias = 1.0 - abs(Double(i) - Double(barCount - 1) / 2.0) / Double(barCount)
                    let envelope = 0.5 + centerBias * 0.5
                    let height = max(4, CGFloat(wave) * 22 * baseAmp * CGFloat(envelope))

                    Capsule(style: .continuous)
                        .fill(gradient)
                        .frame(width: 3, height: height)
                        .shadow(color: .white.opacity(0.3), radius: 0.5)
                }
            }
            .frame(height: 28)
        }
    }
}
