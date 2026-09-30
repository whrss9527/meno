// A menu bar item for scripts/check-hiding.sh: it shows "E2E" in the menu
// bar and prints where it is when it starts and on SIGUSR1.
import AppKit

final class Helper: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var signalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "E2E"
        self.item = item
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.report() }
        source.resume()
        signalSource = source
        report()
    }

    private func report() {
        let frame = item?.button?.window?.frame ?? .zero
        let onScreen = frame.width > 0 && NSScreen.screens.contains { $0.frame.intersects(frame) }
        print("E2E_ITEM x=\(Int(frame.minX)) width=\(Int(frame.width)) on_screen=\(onScreen ? 1 : 0)")
        fflush(stdout)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let helper = Helper()
app.delegate = helper
app.run()
