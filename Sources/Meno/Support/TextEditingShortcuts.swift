import AppKit

/// Meno has no Edit menu (an agent app's menus are never shown), and text
/// fields get ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z from that menu. This sends them to the
/// field being edited, before shortcuts of the window, such as the layout
/// editor's Undo, can take them.
@MainActor
enum TextEditingShortcuts {
    private static var monitor: LocalEventMonitor?
    /// Set while a shortcut is being recorded, which needs every key.
    static var isSuspended = false

    static func install() {
        guard monitor == nil else { return }
        let monitor = LocalEventMonitor(mask: [.keyDown]) { event in
            MainActor.assumeIsolated { handle(event) }
        }
        monitor.start()
        self.monitor = monitor
    }

    private static func handle(_ event: NSEvent) -> Bool {
        guard !isSuspended else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), flags.isDisjoint(with: [.control, .option]),
              NSApp.keyWindow?.firstResponder is NSTextView,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let action: Selector
        switch key {
        case "x": action = #selector(NSText.cut(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "a": action = #selector(NSText.selectAll(_:))
        case "z": action = flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        default: return false
        }
        return NSApp.sendAction(action, to: nil, from: nil)
    }
}
