import AppKit
import MenoCore

/// Opens menu bar items on behalf of the Shelf, Quick Open and hotkeys.
@MainActor
final class ItemActivator {
    unowned let model: AppModel

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
        if click == .secondary {
            if await AX.perform(AX.Action.showMenu, on: element) { return true }
            if item.isOnScreen {
                return EventSynthesizer.click(at: CGPoint(x: item.frame.midX, y: item.frame.midY), secondary: true)
            }
            return false
        }
        if await AX.perform(AX.Action.press, on: element) { return true }
        if item.isOnScreen {
            return EventSynthesizer.click(at: CGPoint(x: item.frame.midX, y: item.frame.midY), secondary: false)
        }
        return false
    }
}
