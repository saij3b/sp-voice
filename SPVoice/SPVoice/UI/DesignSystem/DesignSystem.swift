import SwiftUI

// MARK: - Design Tokens
// Wispr Flow × Superwhisper × visionOS glass.
// Centralised so every surface reads from the same palette, radii, and motion.

enum DS {

    // MARK: Palette

    enum Palette {
        static let bgBase       = Color(red: 0.04, green: 0.04, blue: 0.06)
        static let bgElevated   = Color(red: 0.07, green: 0.07, blue: 0.10)
        static let bgDeep       = Color(red: 0.02, green: 0.02, blue: 0.03)

        static let strokeSubtle = Color.white.opacity(0.06)
        static let strokeSoft   = Color.white.opacity(0.10)
        static let strokeEdge   = Color.white.opacity(0.18)
        static let strokeBright = Color.white.opacity(0.28)

        static let textPrimary   = Color.white.opacity(0.96)
        static let textSecondary = Color.white.opacity(0.68)
        static let textTertiary  = Color.white.opacity(0.44)
        static let textMuted     = Color.white.opacity(0.32)

        // Accent gradients – one per state.
        static let listenFrom  = Color(red: 0.55, green: 0.40, blue: 1.00) // violet
        static let listenTo    = Color(red: 0.87, green: 0.35, blue: 0.95) // magenta
        static let workFrom    = Color(red: 0.00, green: 0.76, blue: 0.96) // cyan
        static let workTo      = Color(red: 0.31, green: 0.51, blue: 1.00) // blue
        static let goodFrom    = Color(red: 0.13, green: 0.85, blue: 0.65) // mint
        static let goodTo      = Color(red: 0.00, green: 0.71, blue: 0.53) // emerald
        static let warnFrom    = Color(red: 1.00, green: 0.72, blue: 0.30) // amber
        static let warnTo      = Color(red: 0.96, green: 0.43, blue: 0.32) // coral
        static let errorFrom   = Color(red: 1.00, green: 0.42, blue: 0.54) // rose
        static let errorTo     = Color(red: 0.91, green: 0.23, blue: 0.38) // red

        static let iconIdle = Color.white.opacity(0.82)
    }

    // MARK: Gradients

    enum Gradients {
        static let listen = LinearGradient(
            colors: [Palette.listenFrom, Palette.listenTo],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        static let work = LinearGradient(
            colors: [Palette.workFrom, Palette.workTo],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        static let good = LinearGradient(
            colors: [Palette.goodFrom, Palette.goodTo],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        static let warn = LinearGradient(
            colors: [Palette.warnFrom, Palette.warnTo],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        static let error = LinearGradient(
            colors: [Palette.errorFrom, Palette.errorTo],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// Subtle sheen over glass surfaces – the visionOS "edge light" look.
        static let glassSheen = LinearGradient(
            colors: [
                Color.white.opacity(0.22),
                Color.white.opacity(0.03),
                Color.white.opacity(0.12)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// Deep tint that sits under .ultraThinMaterial to warm up the glass.
        static let surfaceTint = LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.10, blue: 0.18).opacity(0.55),
                Color(red: 0.03, green: 0.03, blue: 0.06).opacity(0.80)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Radii

    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let pill: CGFloat = 999
    }

    // MARK: Spacing

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: Typography

    enum Font {
        static let display     = SwiftUI.Font.system(size: 34, weight: .semibold, design: .rounded)
        static let title       = SwiftUI.Font.system(size: 22, weight: .semibold, design: .rounded)
        static let titleSmall  = SwiftUI.Font.system(size: 17, weight: .semibold, design: .rounded)
        static let headline    = SwiftUI.Font.system(size: 14, weight: .semibold, design: .rounded)
        static let body        = SwiftUI.Font.system(size: 13, weight: .regular)
        static let bodyMedium  = SwiftUI.Font.system(size: 13, weight: .medium)
        static let caption     = SwiftUI.Font.system(size: 11, weight: .medium, design: .rounded)
        static let captionMono = SwiftUI.Font.system(size: 11, weight: .medium, design: .monospaced)
        static let keycap      = SwiftUI.Font.system(size: 12, weight: .semibold, design: .rounded)
    }

    // MARK: Motion

    enum Motion {
        static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.85)
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.78)
        static let bouncy = Animation.spring(response: 0.55, dampingFraction: 0.68)
        static let gentle = Animation.easeInOut(duration: 0.25)
        static let slow   = Animation.easeInOut(duration: 0.45)
    }
}

// MARK: - Accent Gradient Per State

extension DictationState {
    var accent: LinearGradient {
        switch self {
        case .idle:         return DS.Gradients.work
        case .listening:    return DS.Gradients.listen
        case .transcribing: return DS.Gradients.work
        case .processing:   return DS.Gradients.work
        case .inserting:    return DS.Gradients.good
        case .success:      return DS.Gradients.good
        case .error:        return DS.Gradients.error
        }
    }

    var accentSolid: Color {
        switch self {
        case .idle:         return DS.Palette.iconIdle
        case .listening:    return DS.Palette.listenFrom
        case .transcribing: return DS.Palette.workFrom
        case .processing:   return DS.Palette.workFrom
        case .inserting:    return DS.Palette.goodFrom
        case .success:      return DS.Palette.goodFrom
        case .error:        return DS.Palette.errorFrom
        }
    }

    var heroIcon: String {
        switch self {
        case .idle:         return "waveform"
        case .listening:    return "waveform.and.mic"
        case .transcribing: return "waveform.path.ecg"
        case .processing:   return "sparkles"
        case .inserting:    return "text.cursor"
        case .success:      return "checkmark"
        case .error:        return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Glass Surface

/// A reusable glass panel: ultra-thin material + subtle gradient tint + edge stroke.
/// This is THE primary background for all surfaces (overlay, menu bar, settings, onboarding).
struct GlassSurface: View {
    var cornerRadius: CGFloat = DS.Radius.xl
    var strength: Strength = .regular

    enum Strength { case thin, regular, thick }

    private var material: Material {
        switch strength {
        case .thin:    return .ultraThinMaterial
        case .regular: return .regularMaterial
        case .thick:   return .thickMaterial
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(material)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.Gradients.surfaceTint)
                    .blendMode(.softLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.Gradients.glassSheen, lineWidth: 1)
                    .blendMode(.plusLighter)
                    .opacity(0.8)
            )
    }
}

// MARK: - Glass Card (interior sub-panels)

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = DS.Radius.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(DS.Space.md)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1)
            )
    }
}

// MARK: - Gradient Pill Button

struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = DS.Gradients.work
    var cornerRadius: CGFloat = DS.Radius.sm
    var size: Size = .regular

    enum Size { case small, regular, large }

    private var vPad: CGFloat {
        switch size { case .small: 6; case .regular: 10; case .large: 14 }
    }
    private var hPad: CGFloat {
        switch size { case .small: 12; case .regular: 18; case .large: 24 }
    }
    private var font: Font {
        switch size { case .small: DS.Font.caption; case .regular: DS.Font.headline; case .large: DS.Font.titleSmall }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(.white)
            .padding(.vertical, vPad)
            .padding(.horizontal, hPad)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(DS.Motion.snappy, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = DS.Radius.sm
    var size: GradientButtonStyle.Size = .regular

    private var vPad: CGFloat {
        switch size { case .small: 6; case .regular: 10; case .large: 14 }
    }
    private var hPad: CGFloat {
        switch size { case .small: 12; case .regular: 18; case .large: 24 }
    }
    private var font: Font {
        switch size { case .small: DS.Font.caption; case .regular: DS.Font.headline; case .large: DS.Font.titleSmall }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.vertical, vPad)
            .padding(.horizontal, hPad)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.Palette.strokeSoft, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Keycap

/// Small rounded keycap badge – used to display hotkeys.
struct Keycap: View {
    let text: String
    var size: CGFloat = 14

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(DS.Palette.textPrimary)
            .frame(minWidth: size * 1.7, minHeight: size * 1.7)
            .padding(.horizontal, size * 0.35)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.clear],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                    .blendMode(.plusLighter)
            )
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

/// Renders a combo display string like "⌃⌥⇧⌘K" as individual keycaps.
struct KeycapGroup: View {
    let display: String
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(splitGroups(display).enumerated()), id: \.offset) { _, group in
                Keycap(text: group, size: size)
            }
        }
    }

    private func splitGroups(_ s: String) -> [String] {
        // Group modifier glyphs as single keycaps, split multi-char tokens by whitespace.
        // Heuristic: each "symbol" becomes its own cap, whole words become one.
        let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "←", "→", "↑", "↓"]
        var caps: [String] = []
        var buffer = ""
        for ch in s {
            if modifierGlyphs.contains(ch) {
                if !buffer.isEmpty { caps.append(buffer); buffer = "" }
                caps.append(String(ch))
            } else {
                buffer.append(ch)
            }
        }
        if !buffer.isEmpty { caps.append(buffer) }
        return caps.isEmpty ? [s] : caps
    }
}

// MARK: - Status Dot

/// Animated colored dot used throughout for state indication.
struct StatusDot: View {
    let state: DictationState
    var size: CGFloat = 10

    @State private var pulse = false

    var body: some View {
        ZStack {
            if state.isActive {
                Circle()
                    .fill(state.accent)
                    .frame(width: size * 2.4, height: size * 2.4)
                    .opacity(pulse ? 0 : 0.4)
                    .scaleEffect(pulse ? 1.6 : 0.8)
            }
            Circle()
                .fill(state.accent)
                .frame(width: size, height: size)
                .shadow(color: state.accentSolid.opacity(0.7), radius: size * 0.8)
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - View Helpers

extension View {
    /// Applies the full dark glass backdrop (for windows like Settings / Onboarding).
    func glassWindowBackground() -> some View {
        self.background(
            ZStack {
                DS.Palette.bgBase
                LinearGradient(
                    colors: [
                        DS.Palette.listenFrom.opacity(0.12),
                        Color.clear,
                        DS.Palette.workFrom.opacity(0.08)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                    .blur(radius: 80)
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
    }

    /// Tint a text with the state gradient.
    func gradientFill(_ gradient: LinearGradient) -> some View {
        self.foregroundStyle(gradient)
    }
}
