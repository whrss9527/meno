import AppIntents
import Foundation

// A standalone executable: no Meno settings, UI, accessibility or user files.
struct MetadataProbeIntent: AppIntent {
    static let title: LocalizedStringResource = "Metadata Probe"
    func perform() async throws -> some IntentResult { .result() }
}

struct MetadataProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MetadataProbeIntent(), phrases: ["Run \(.applicationName) probe"],
                    shortTitle: "Probe", systemImageName: "circle")
    }
}

@main
enum ProbeMain {
    static func main() { print("Isolated metadata probe") }
}
