import SwiftUI

struct HistoryView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.historyStore.entries.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No dictation history")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Your recent dictations will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(appState.historyStore.entries) { entry in
                    historyRow(entry)
                }
            }
            .listStyle(.inset)

            HStack {
                Text("\(appState.historyStore.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") {
                    appState.historyStore.clear()
                }
                .controlSize(.small)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: HistoryStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.provider.rawValue) · \(entry.latencyMs)ms")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.text)
                .font(.system(.caption, design: .default))
                .lineLimit(3)

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
