import Foundation
import os

/// Local store of recent dictation entries.
/// Phase 2: skeleton. Full implementation in Phase 6.
@MainActor
final class HistoryStore: ObservableObject {

    struct Entry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let text: String
        let provider: ProviderID
        let model: String
        let latencyMs: Int
    }

    @Published private(set) var entries: [Entry] = []

    private let maxEntries: Int
    private let fileURL: URL

    init(maxEntries: Int = SPVoiceConstants.Defaults.maxHistoryEntries) {
        self.maxEntries = maxEntries
        self.fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.spvoice")
            .appendingPathComponent("history.json")

        loadFromDisk()
    }

    func add(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        saveToDisk()
    }

    func clear() {
        entries.removeAll()
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }
        entries = decoded
    }

    private func saveToDisk() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
