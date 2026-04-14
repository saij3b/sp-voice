import SwiftUI

/// Custom sidebar-based settings window with glass aesthetic.
struct SettingsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var selection: SettingsSection = .general

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general, providers, shortcut, history, diagnostics
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:     return "General"
            case .providers:   return "Providers"
            case .shortcut:    return "Shortcut"
            case .history:     return "History"
            case .diagnostics: return "Diagnostics"
            }
        }

        var icon: String {
            switch self {
            case .general:     return "slider.horizontal.3"
            case .providers:   return "sparkles"
            case .shortcut:    return "command.circle"
            case .history:     return "text.alignleft"
            case .diagnostics: return "waveform.path.ecg.rectangle"
            }
        }

        var subtitle: String {
            switch self {
            case .general:     return "Startup, dictation, permissions"
            case .providers:   return "AI models and API keys"
            case .shortcut:    return "Global hotkey"
            case .history:     return "Recent transcriptions"
            case .diagnostics: return "Debug info and recovery"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(DS.Palette.strokeSubtle)
            content
        }
        .frame(width: 820, height: 560)
        .glassWindowBackground()
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // Brand header
            HStack(spacing: DS.Space.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Gradients.listen)
                        .frame(width: 32, height: 32)
                        .shadow(color: DS.Palette.listenFrom.opacity(0.5), radius: 8)
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("SP Voice")
                        .font(DS.Font.titleSmall)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("Dictation · v0.1")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.top, DS.Space.lg)
            .padding(.bottom, DS.Space.sm)

            // Navigation
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    SidebarButton(
                        section: section,
                        isSelected: selection == section
                    ) {
                        withAnimation(DS.Motion.snappy) { selection = section }
                    }
                }
            }
            .padding(.horizontal, DS.Space.xs)

            Spacer()

            // Footer status
            sidebarFooter
                .padding(DS.Space.md)
        }
        .frame(width: 240)
        .background(
            Color.white.opacity(0.02)
        )
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.shortcutManager.isRegistered ? DS.Gradients.good : DS.Gradients.warn)
                    .frame(width: 8, height: 8)
                Text(appState.shortcutManager.isRegistered ? "Ready" : "Hotkey inactive")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }

            if let id = appState.providerManager.resolvedPrimaryID {
                Text("Using \(id.displayName)")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    // MARK: Content pane

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                // Section header
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.title)
                        .font(DS.Font.title)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(selection.subtitle)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                .padding(.top, DS.Space.xl)
                .padding(.bottom, DS.Space.xs)

                Group {
                    switch selection {
                    case .general:     GeneralSettingsView()
                    case .providers:   ProvidersSettingsView()
                    case .shortcut:    ShortcutSettingsView()
                    case .history:     HistoryView()
                    case .diagnostics: DiagnosticsView()
                    }
                }
                .environmentObject(appState)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.bottom, DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Sidebar Button

private struct SidebarButton: View {
    let section: SettingsView.SettingsSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DS.Gradients.listen.opacity(0.25))
                            .frame(width: 28, height: 28)
                    }
                    Image(systemName: section.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                        .frame(width: 28, height: 28)
                }

                Text(section.title)
                    .font(DS.Font.bodyMedium)
                    .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textSecondary)

                Spacer()
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : (isHovered ? 0.05 : 0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? DS.Palette.strokeSoft : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Reusable Section Card

/// A titled glass card container used across all settings panes.
struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Palette.textPrimary)

                    if let subtitle {
                        Text(subtitle)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                content()
            }
        }
        .padding(DS.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Settings Row

struct SettingsRow<Leading: View, Trailing: View>: View {
    let label: String
    var description: String? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.sm) {
            leading()

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.bodyMedium)
                    .foregroundStyle(DS.Palette.textPrimary)
                if let description {
                    Text(description)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            trailing()
        }
        .padding(.vertical, 4)
    }
}
