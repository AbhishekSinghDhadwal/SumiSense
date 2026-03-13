import Foundation

struct LocalAppStateSnapshot: Codable {
    let entries: [JournalEntry]
    let metrics: [WellnessMetricPoint]
    let savedAt: Date
}

enum LocalAppStateStoreError: Error {
    case saveFailed(String)
    case loadFailed(String)
}

final class LocalAppStateStore {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init(filename: String = "sumisense_state.json") {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("SumiSense", isDirectory: true)
        self.fileURL = directory.appendingPathComponent(filename)
    }

    func load() throws -> LocalAppStateSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(LocalAppStateSnapshot.self, from: data)
        } catch {
            throw LocalAppStateStoreError.loadFailed(error.localizedDescription)
        }
    }

    func save(entries: [JournalEntry], metrics: [WellnessMetricPoint]) throws {
        do {
            try ensureDirectoryExists()
            let snapshot = LocalAppStateSnapshot(entries: entries, metrics: metrics, savedAt: Date())
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw LocalAppStateStoreError.saveFailed(error.localizedDescription)
        }
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func ensureDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
