import AppKit
import MenoCore

/// Opens menu bar items on behalf of the Shelf, Quick Open and hotkeys.
@MainActor
final class ItemActivator {
    unowned let model: AppModel
    /// When Meno last clicked an item itself, which is not a click of the
    /// person's to count.
    private var lastClick: Date?

    /// Whether Meno clicked an item a moment ago.
    var clickedRecently: Bool {
        lastClick.map { Date().timeIntervalSince($0) < 1 } ?? false
    }

    init(model: AppModel) {
        self.model = model
    }

    /// Opens an item's menu, revealing its section first if necessary.
    func open(_ item: MenuBarItem, click: ClickKind = .primary, source: UsageSource) async {
        guard model.permissions.accessibility else {
            model.toasts.show(String(localized: "Meno needs Accessibility access to open items."), symbol: "hand.raised.fill")
            return
        }
        guard let element = item.element else { return }
        model.recordItemUse(item, source: source)
        model.changes.markSeen([item.key])

        model.reveal.revealForActivation(of: item.section)
        var target = item
        if item.section != .visible || model.isZenActive {
            // Wait until macOS has laid the item out on screen.
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 60_000_000)
                if let frame = await MenuBarScanner.frame(of: element) {
                    target.frame = frame
                    if target.isOnScreen { break }
                }
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        let opened = await press(target, element: element, click: click)
        if !opened {
            model.toasts.show(String(localized: "\(item.displayName) could not be opened."), symbol: "exclamationmark.triangle.fill")
        }
        model.reveal.endActivation(watching: item.pid)
    }

    private func press(_ item: MenuBarItem, element: AXUIElement, click: ClickKind) async -> Bool {
        let action = click == .secondary ? AX.Action.showMenu : AX.Action.press
        if await AX.perform(action, on: element) { return true }
        // A click needs where the item is now; items may have shifted since
        // the last scan.
        var target = item
        if let frame = await MenuBarScanner.frame(of: element) {
            target.frame = frame
        }
        // Behind the camera housing the click would land on the housing.
        let point = CGPoint(x: target.frame.midX, y: target.frame.midY)
        guard ScreenGeometry.isReachable(point) else { return false }
        lastClick = Date()
        return EventSynthesizer.click(at: point, secondary: click == .secondary)
    }
}
