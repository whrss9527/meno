import AppKit

@MainActor
final class SingleInstanceDriver: NSObject, NSApplicationDelegate {
    private var timer: Timer?
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MENO_INSTANCE_TEST_DIR"]!)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ready = directory.appendingPathComponent("ready-\(AppInfo.ownPID)")
        try! Data().write(to: ready)
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("go").path) else { return }
                self.timer?.invalidate()
                self.timer = nil
                if !SingleInstance.claim(forwarding: []) { NSApplication.shared.terminate(nil) }
            }
        }
    }
}

@main
struct SingleInstanceTestMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = SingleInstanceDriver()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
