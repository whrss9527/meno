import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An empty main menu keeps the menu bar clear whenever Meno is active.
        NSApp.mainMenu = NSMenu()
        let model = AppModel()
        self.model = model
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareForTermination()
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
