import AppKit
import MenoCore

/// Runs the real controllers without touching Meno's settings or defaults domain.
@main
struct HidingLifecycleDriver {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = LifecycleDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

@MainActor
private final class LifecycleDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var probe: NSStatusItem?
    private let keys = (0..<8).map { MenuItemKey(owner: "test.lifecycle.\($0)", token: "solo") }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let args = CommandLine.arguments
                guard args.count == 3 else { throw Failure("Expected storage directory and phase") }
                let storage = Storage(directory: URL(fileURLWithPath: args[1], isDirectory: true))
                if args[2] == "restart" {
                    try checkMemory(storage)
                    print("Restart: saved Hidden, Stash and Visible sections survived a separate process")
                } else {
                    try await exercise(storage)
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("::error::Hiding lifecycle: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    private func checkMemory(_ storage: Storage) throws {
        let memory = storage.loadSectionMemory()
        for (index, key) in keys.enumerated() {
            let section: ItemSection = index % 3 == 0 ? .stash : (index % 3 == 1 ? .hidden : .visible)
            guard memory[key.rawValue]?.section == section else { throw Failure("Lost saved section for \(key)") }
        }
    }

    private func wait(_ description: String, for condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(6)
        while !condition() {
            guard Date() < deadline else { throw Failure("Timed out: \(description)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func exercise(_ storage: Storage) async throws {
        let memory = Dictionary(uniqueKeysWithValues: keys.enumerated().map { index, key in
            (key.rawValue, SectionKeeper.Remembered(section: index % 3 == 0 ? .stash : (index % 3 == 1 ? .hidden : .visible), seen: Date()))
        })
        storage.saveSectionMemory(memory)
        var settings = MenoSettings()
        settings.onboardingCompleted = true
        settings.general.revealStyle = .menuBar
        settings.general.appMenuHiding = .never
        settings.general.newItemPolicy = .ignore
        settings.reveal.autoRehide = false
        settings.reveal.rehideOnFocusChange = false
        settings.reveal.rehideOnMouseExit = false
        storage.flush(settings: settings, usage: UsageLog())
        let model = AppModel(storage: storage)
        self.model = model
        model.statusBar.install()
        model.reveal.start()
        let probe = NSStatusBar.system.statusItem(withLength: 24)
        self.probe = probe
        probe.button?.title = "T"

        for engine in [HidingEngine.wide, .stepped] {
            model.settings.general.hidingEngine = engine
            model.setZen(true, announce: false)
            try await wait("Zen state applied") { model.statusBar.state.zen }
            model.statusBar.toggle?.button?.performClick(nil)
            guard !model.isZenActive, model.reveal.visibility == .revealed else {
                throw Failure("One click must exit Zen and reveal Hidden with \(engine)")
            }
            model.reveal.requestReveal(all: true, trigger: .link)
            try await wait("all divider lengths shrink") {
                (model.statusBar.hiddenDivider?.length ?? 999) < 100
                    && (model.statusBar.stashDivider?.length ?? 999) < 100
            }
            try await wait("real probe is visible") {
                guard let frame = probe.button?.window?.frame, !frame.isEmpty else { return false }
                return NSScreen.screens.contains { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }
            }

            // Simulate a physical divider being rebuilt while logical state remains revealed.
            model.statusBar.hiddenDivider?.length = 3000
            model.reveal.requestReveal(all: true, trigger: .menu)
            try await wait("repeated reveal repairs physical divider") {
                (model.statusBar.hiddenDivider?.length ?? 999) < 100
            }

            model.reveal.collapse(trigger: .menu)
            model.reveal.beginLayoutSession()
            model.reveal.requestReveal(all: true, trigger: .menu)
            model.reveal.endLayoutSession()
            guard model.reveal.visibility == .revealedAll, !model.statusBar.state.hiddenCollapsed else {
                throw Failure("Finishing a restore undid the user's reveal with \(engine)")
            }
            print("\(engine): one-click Zen exit, real expansion, repeated reveal and layout overlap passed")
        }
        model.settings.appearance.showsDividers = false
        model.reveal.requestReveal(all: true, trigger: .link)
        try await wait("invisible dividers shrink") {
            model.statusBar.hiddenDivider?.length == 0 && model.statusBar.stashDivider?.length == 0
        }
        model.prepareForTermination()
        try checkMemory(storage)
        NSStatusBar.system.removeStatusItem(probe)
        print("Hiding lifecycle passed without changing Meno's user files")
    }
}
