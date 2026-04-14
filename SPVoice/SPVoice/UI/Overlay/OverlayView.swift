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
            MagicOrb(gradient: state.accent)
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
        case .transcribing, .processing, .inserting:
            // Compact — just the orb. No text label.
            EmptyView()
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

// MARK: - Magic Orb (pulsing sphere with inner orbiting sparkles)

private struct MagicOrb: View {
    let gradient: LinearGradient

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breath = 1.0 + 0.1 * sin(t * 2.4)

            ZStack {
                // Outer soft halo
                Circle()
                    .fill(gradient)
                    .frame(width: 26, height: 26)
                    .opacity(0.4)
                    .blur(radius: 6)
                    .scaleEffect(breath * 1.15)

                // Core orb
                Circle()
                    .fill(gradient)
                    .frame(width: 18, height: 18)
                    .shadow(color: .white.opacity(0.5), radius: 4)
                    .scaleEffect(breath)

                // Orbiting inner sparkles — 3 points, 120° apart, gentle radius pulse
                ForEach(0..<3, id: \.self) { i in
                    let a = t * 1.9 + Double(i) * 2.094
                    let radius = 4.5 + 1.2 * sin(t * 1.6 + Double(i))
                    Circle()
                        .fill(Color.white)
                        .frame(width: 2.2, height: 2.2)
                        .offset(
                            x: CGFloat(cos(a) * radius),
                            y: CGFloat(sin(a) * radius)
                        )
                        .opacity(0.9)
                        .shadow(color: .white.opacity(0.8), radius: 1.5)
                }
            }
            .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Transcribing Glyph (audio waves dissolving into text)

private struct TranscribingGlyph: View {
    let gradient: LinearGradient

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                // Ripple ring — audio turning into text
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.9 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
                    Circle()
                        .stroke(gradient, lineWidth: 1.4)
                        .frame(width: 10 + CGFloat(phase) * 22, height: 10 + CGFloat(phase) * 22)
                        .opacity(1 - phase)
                }

                // Core text glyph
                Image(systemName: "text.alignleft")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(gradient)
                            .shadow(color: .black.opacity(0.25), radius: 4)
                    )
            }
            .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Processing Glyph (orbital sparkles — "thinking")

private struct ProcessingGlyph: View {
    let gradient: LinearGradient

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = t * 180  // degrees/sec

            ZStack {
                // Halo
                Circle()
                    .stroke(gradient, lineWidth: 1.2)
                    .frame(width: 26, height: 26)
                    .opacity(0.45)

                // Orbiting sparkles
                ForEach(0..<3, id: \.self) { i in
                    let a = Angle.degrees(angle + Double(i) * 120)
                    Circle()
                        .fill(gradient)
                        .frame(width: 4, height: 4)
                        .offset(
                            x: cos(a.radians) * 12,
                            y: sin(a.radians) * 12
                        )
                        .shadow(color: .white.opacity(0.6), radius: 2)
                }

                // Center spark
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(1 + 0.1 * sin(t * 4))
            }
            .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Writing Glyph (pen drawing a line — "placing text")

private struct WritingGlyph: View {
    let gradient: LinearGradient

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // 0 → 1 → 0 smooth cycle — nib sweeps right, then resets
            let cycle = (t.truncatingRemainder(dividingBy: 1.1)) / 1.1
            let nibX = CGFloat(cycle) * 12 - 6

            ZStack {
                // Underline being written
                Capsule()
                    .fill(gradient)
                    .frame(width: max(2, CGFloat(cycle) * 16), height: 2)
                    .offset(x: -8 + CGFloat(cycle) * 8, y: 8)
                    .opacity(0.9)

                // Pencil glyph
                Image(systemName: "pencil.tip")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: nibX, y: 0)

                // Halo under nib
                Circle()
                    .fill(gradient)
                    .frame(width: 4, height: 4)
                    .offset(x: nibX, y: 6)
                    .blur(radius: 1.5)
                    .opacity(0.8)
            }
            .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Typing Dots (inline bouncing dots)

private struct TypingDots: View {
    let gradient: LinearGradient

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = sin(t * 4.5 + Double(i) * 0.7)
                    let scale = 0.7 + 0.35 * max(0, phase)
                    Circle()
                        .fill(gradient)
                        .frame(width: 6, height: 6)
                        .scaleEffect(scale)
                        .opacity(0.6 + 0.4 * max(0, phase))
                }
            }
        }
    }
}

// MARK: - Thinking Orbits (inline twin orbit dots)

private struct ThinkingOrbits: View {
    let gradient: LinearGradient

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let a = t * 2.4 + Double(i) * .pi
                    Circle()
                        .fill(gradient)
                        .frame(width: 5, height: 5)
                        .offset(x: CGFloat(cos(a)) * 10, y: CGFloat(sin(a)) * 5)
                        .shadow(color: .white.opacity(0.5), radius: 1)
                }
            }
        }
    }
}

// MARK: - Typewriter Line (animated underline — text being laid down)

private struct TypewriterLine: View {
    let gradient: LinearGradient

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let cycle = (t.truncatingRemainder(dividingBy: 1.1)) / 1.1
            let width: CGFloat = 56
            let fill = CGFloat(cycle) * width

            ZStack(alignment: .leading) {
                // Faint track
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: width, height: 3)
                // Growing fill
                Capsule()
                    .fill(gradient)
                    .frame(width: fill, height: 3)
                // Moving cursor
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 10)
                    .offset(x: fill - 1)
                    .shadow(color: .white.opacity(0.8), radius: 2)
            }
            .frame(width: width, height: 14, alignment: .leading)
        }
    }
}

// MARK: - Success Glyph (checkmark with expanding ring)

private struct SuccessGlyph: View {
    @State private var ringScale: CGFloat = 0.6
    @State private var ringOpacity: Double = 0.9

    var body: some View {
        ZStack {
            Circle()
                .stroke(DS.Gradients.good, lineWidth: 2)
                .frame(width: 24, height: 24)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            Circle()
                .fill(DS.Gradients.good)
                .frame(width: 24, height: 24)
                .shadow(color: DS.Palette.goodFrom.opacity(0.7), radius: 8)

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                ringScale = 1.6
                ringOpacity = 0
            }
        }
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
