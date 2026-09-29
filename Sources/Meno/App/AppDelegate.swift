import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    /// Links that arrived before Meno finished launching, for example the
    /// one that launched it.
    private var waitingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An empty main menu keeps the menu bar clear whenever Meno is active.
        NSApp.mainMenu = NSMenu()
        let model = AppModel()
        self.model = model
        model.start()
        let urls = waitingURLs
        waitingURLs = []
        for url in urls {
            model.handle(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareForTermination()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model else {
            waitingURLs += urls
            return
        }
        for url in urls {
            model.handle(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching Meno again (for example from Finder) opens Settings.
        model?.openSettings()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
