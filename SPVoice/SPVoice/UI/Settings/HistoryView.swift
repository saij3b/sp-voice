import SwiftUI

struct HistoryView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if appState.historyStore.entries.isEmpty {
                emptyCard
            } else {
                headerBar
                entriesList
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.Gradients.work.opacity(0.2))
                    .frame(width: 64, height: 64)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DS.Gradients.work)
            }
            Text("No dictations yet")
                .font(DS.Font.titleSmall)
                .foregroundStyle(DS.Palette.textPrimary)
            Text("Your recent transcriptions will appear here.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(DS.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1)
        )
    }

    private var headerBar: some View {
        HStack {
            Text("\(appState.historyStore.entries.count) entries")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.textTertiary)
            Spacer()
            Button {
                appState.historyStore.clear()
            } label: {
                Label("Clear all", systemImage: "trash")
            }
            .buttonStyle(GhostButtonStyle(size: .small))
        }
    }

    private var entriesList: some View {
        LazyVStack(spacing: DS.Space.xs) {
            ForEach(appState.historyStore.entries) { entry in
                entryCard(entry)
            }
        }
    }

    @ViewBuilder
    private func entryCard(_ entry: HistoryStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Provider chip
                HStack(spacing: 6) {
                    Circle()
                        .fill(DS.Gradients.work)
                        .frame(width: 6, height: 6)
                    Text(entry.provider.rawValue.capitalized)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.05)))
                .overlay(Capsule().strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1))

                Text("\(entry.latencyMs) ms")
                    .font(DS.Font.captionMono)
                    .foregroundStyle(DS.Palette.textTertiary)

                Spacer()

                Text(entry.timestamp, style: .relative)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            Text(entry.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(GhostButtonStyle(size: .small))

                Spacer()
            }
        }
        .padding(DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .strokeBorder(DS.Palette.strokeSubtle, lineWidth: 1)
        )
    }
}
