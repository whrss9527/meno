import Foundation
import MenoCore

/// Reads and writes Meno's JSON files in Application Support.
@MainActor
final class Storage {
    let directory: URL

    private var pendingWrites: [String: Task<Void, Never>] = [:]
    /// What the pending writes would write, so they can be done at once.
    private var pendingEncoders: [String: () throws -> Data] = [:]

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
        // Only a file that is not there means a fresh start; one that cannot
        // be read is kept aside, so the next save does not overwrite it.
        guard FileManager.default.fileExists(atPath: url.path) else { return MenoSettings() }
        do {
            return try MenoSettings.decode(from: Data(contentsOf: url))
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

    /// Writes a copy of `settings` next to `settings.json` under `name`, and
    /// returns where it is.
    func backUp(_ settings: MenoSettings, as name: String) throws -> URL {
        let url = url(for: name)
        try settings.encoded().write(to: url, options: .atomic)
        return url
    }

    // MARK: Usage

    func loadUsage() -> UsageLog {
        load("usage.json", empty: UsageLog()) { data in
            try TolerantJSON.decode(UsageLog.self, from: data, defaults: UsageLog())
        }
    }

    func saveUsage(_ usage: UsageLog, immediately: Bool = false) {
        write(name: "usage.json", delay: immediately ? 0 : 3) {
            try TolerantJSON.makeEncoder().encode(usage)
        }
    }

    // MARK: Known items

    /// The items seen so far, or `nil` before the first scan.
    func loadKnownItems() -> KnownItems? {
        guard let data = try? Data(contentsOf: url(for: "known-items.json")) else { return nil }
        return try? KnownItems.decode(from: data)
    }

    /// Writes the items seen so far; `nil` forgets them, so that the next
    /// scan counts everything as known again.
    func saveKnownItems(_ known: KnownItems?) {
        guard let known else {
            pendingWrites["known-items.json"]?.cancel()
            pendingWrites["known-items.json"] = nil
            pendingEncoders["known-items.json"] = nil
            try? FileManager.default.removeItem(at: url(for: "known-items.json"))
            return
        }
        write(name: "known-items.json", delay: 1) {
            try TolerantJSON.makeEncoder().encode(known)
        }
    }

    // MARK: Sections

    func loadSectionMemory() -> [String: SectionKeeper.Remembered] {
        load("sections.json", empty: [:]) { data in
            try TolerantJSON.makeDecoder().decode([String: SectionKeeper.Remembered].self, from: data)
        }
    }

    func saveSectionMemory(_ memory: [String: SectionKeeper.Remembered]) {
        write(name: "sections.json", delay: 2) {
            try TolerantJSON.makeEncoder().encode(memory)
        }
    }

    // MARK: Helpers

    /// Writes all pending files right away (used on quit).
    func flush(settings: MenoSettings, usage: UsageLog) {
        for task in pendingWrites.values { task.cancel() }
        pendingWrites.removeAll()
        let others = pendingEncoders.filter { $0.key != "settings.json" && $0.key != "usage.json" }
        pendingEncoders.removeAll()
        for (name, encode) in others {
            writeNow(name: name, encode: encode)
        }
        writeNow(name: "settings.json") { try settings.encoded() }
        writeNow(name: "usage.json") { try TolerantJSON.makeEncoder().encode(usage) }
    }

    private func write(name: String, delay: TimeInterval, encode: @escaping () throws -> Data) {
        pendingWrites[name]?.cancel()
        pendingEncoders[name] = encode
        pendingWrites[name] = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            self.pendingWrites[name] = nil
            if let encode = self.pendingEncoders.removeValue(forKey: name) {
                self.writeNow(name: name, encode: encode)
            }
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

    /// Reads a file, or `empty` when there is none. A file that cannot be
    /// read is kept aside rather than overwritten by the next save.
    private func load<Value>(_ name: String, empty: Value, decode: (Data) throws -> Value) -> Value {
        let url = url(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return empty }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            Log.storage.error("\(name, privacy: .public) could not be read: \(error.localizedDescription, privacy: .public)")
            backUpUnreadableFile(at: url)
            return empty
        }
    }

    private func backUpUnreadableFile(at url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}
