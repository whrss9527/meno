import AppKit
import Combine

/// Test-only entry point, compiled with the app's production updater and UI.
/// It never starts menu-bar controllers, permissions or settings writers.
@main
struct UpdateDriver {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = UpdateDriverDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

@MainActor
private final class UpdateDriverDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var subscription: AnyCancellable?
    private var directory: URL {
        URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "MenoUpdateTestDirectory") as! String)
    }

    private func record(_ name: String, _ text: String) {
        try! Data((text + "\n").utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        freopen(directory.appendingPathComponent("driver.log").path, "a", stderr)
        let endpoint = Bundle.main.object(forInfoDictionaryKey: "MenoUpdateTestEndpoint") as! String
        setenv("MENO_UPDATE_URL", endpoint, 1)
        setenv("MENO_DIAG", "1", 1)
        record("launched-\(AppInfo.version)", String(AppInfo.ownPID))
        if let leftovers = UserDefaults.standard.string(forKey: "UpdateLeftovers") {
            record("leftovers-path", leftovers)
            record("bundle-path", Bundle.main.bundlePath)
        }
        if Bundle.main.object(forInfoDictionaryKey: "MenoUpdateTestBroken") as? Bool == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(42) }
            return
        }
        let model = AppModel()
        self.model = model
        subscription = model.toasts.$current.sink { [weak self] toast in
            guard let toast, toast.message.contains("was put back") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard NSApp.windows.contains(where: { $0.isVisible }) else {
                    self?.record("failed", "Rollback notice was not displayed")
                    return
                }
                self?.record("put-back", toast.message)
            }
        }
        model.updates.finishInstallation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [self] in
            record("cleanup-state", "defaults=\(UserDefaults.standard.string(forKey: "UpdateLeftovers") ?? "nil") bundle=\(Bundle.main.bundlePath)")
        }
        guard AppInfo.version == "0.0.1",
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("installing").path) else { return }
        Task {
            await model.updates.check(userInitiated: true)
            guard model.updates.available?.version?.description == "0.0.2", model.updates.canInstall else {
                record("failed", "Local release was not offered for installation")
                return
            }
            record("installing", "0.0.1 -> 0.0.2")
            await model.updates.install()
            record("failed", "Installer returned without terminating the old copy")
        }
    }
}
