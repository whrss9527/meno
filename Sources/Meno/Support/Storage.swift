import Foundation
import MenoCore

/// Reads and writes Meno's JSON files in Application Support.
@MainActor
final class Storage {
    let directory: URL

    private var pendingWrites: [String: Task<Void, Never>] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directory = base.appendingPathComponent("Meno", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    // MARK: Settings

    func loadSettings() -> MenoSettings {
        let url = url(for: "settings.json")
        guard let data = try? Data(contentsOf: url) else { return MenoSettings() }
        do {
            return try MenoSettings.decode(from: data)
        } catch {
            Log.storage.error("Settings could not be read: \(error.localizedDescription, privacy: .public)")
            backUpUnreadableFile(at: url)
            return MenoSettings()
        }
    }

    func saveSettings(_ settings: MenoSettings, immediately: Bool = false) {
        write(name: "settings.json", delay: immediately ? 0 : 0.4) {
            try settings.encoded()
        }
    }

    // MARK: Usage

    func loadUsage() -> UsageLog {
        let url = url(for: "usage.json")
        guard let data = try? Data(contentsOf: url) else { return UsageLog() }
        return (try? TolerantJSON.decode(UsageLog.self, from: data, defaults: UsageLog())) ?? UsageLog()
    }

    func saveUsage(_ usage: UsageLog, immediately: Bool = false) {
        write(name: "usage.json", delay: immediately ? 0 : 3) {
            try TolerantJSON.makeEncoder().encode(usage)
        }
    }

    // MARK: Known items

    func loadKnownItems() -> Set<String>? {
        guard let data = try? Data(contentsOf: url(for: "known-items.json")),
              let keys = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return Set(keys)
    }

    func saveKnownItems(_ keys: Set<String>) {
        write(name: "known-items.json", delay: 1) {
            try TolerantJSON.makeEncoder().encode(keys.sorted())
        }
    }

    // MARK: Helpers

    /// Writes all pending files right away (used on quit).
    func flush(settings: MenoSettings, usage: UsageLog) {
        for task in pendingWrites.values { task.cancel() }
        pendingWrites.removeAll()
        writeNow(name: "settings.json") { try settings.encoded() }
        writeNow(name: "usage.json") { try TolerantJSON.makeEncoder().encode(usage) }
    }

    private func write(name: String, delay: TimeInterval, encode: @escaping () throws -> Data) {
        pendingWrites[name]?.cancel()
        pendingWrites[name] = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            self.writeNow(name: name, encode: encode)
            self.pendingWrites[name] = nil
        }
    }

    private func writeNow(name: String, encode: () throws -> Data) {
        do {
            let data = try encode()
            try data.write(to: url(for: name), options: .atomic)
        } catch {
            Log.storage.error("Writing \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func backUpUnreadableFile(at url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}
