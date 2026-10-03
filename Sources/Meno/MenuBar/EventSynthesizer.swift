import AppKit
import CoreGraphics

/// Posts synthetic mouse and keyboard events. Requires Accessibility access.
enum EventSynthesizer {
    private static let commandKey: CGKeyCode = 0x37

    /// Clicks at a point (Quartz coordinates) and puts the pointer back.
    @discardableResult
    static func click(at point: CGPoint, secondary: Bool) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let button: CGMouseButton = secondary ? .right : .left
        let downType: CGEventType = secondary ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = secondary ? .rightMouseUp : .leftMouseUp
        guard let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button) else {
            return false
        }
        let original = CGEvent(source: nil)?.location
        // Keys still held from a shortcut would turn this into a ⌘-drag
        // or an ⌥-click.
        down.flags = []
        up.flags = []
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        if let original {
            _ = CGWarpMouseCursorPosition(original)
        }
        return true
    }

    /// Performs a ⌘-drag from `start` to `end`, the gesture macOS uses to
    /// rearrange menu bar items. The pointer is detached from the physical
    /// mouse during the drag and restored afterwards.
    /// - Parameter pace: Stretches the pauses; retries go slower, since some
    ///   setups need longer holds before an item follows the pointer.
    static func commandDrag(from start: CGPoint, to end: CGPoint, pace: Double = 1) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let original = CGEvent(source: nil)?.location
        _ = CGAssociateMouseAndMouseCursorPosition(0)

        func scaled(_ milliseconds: UInt64) -> UInt64 {
            UInt64((Double(milliseconds) * max(pace, 1)).rounded())
        }

        postKey(commandKey, down: true, source: source)
        postMouse(.mouseMoved, at: start, source: source, flags: .maskCommand)
        await pause(milliseconds: scaled(40))
        postMouse(.leftMouseDown, at: start, source: source, flags: .maskCommand)
        await pause(milliseconds: scaled(150))

        let distance = abs(end.x - start.x)
        let steps = max(10, Int(distance / 10))
        for step in 1...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            postMouse(.leftMouseDragged, at: point, source: source, flags: .maskCommand)
            await pause(milliseconds: scaled(12))
        }
        await pause(milliseconds: scaled(150))
        postMouse(.leftMouseUp, at: end, source: source, flags: .maskCommand)
        await pause(milliseconds: scaled(60))
        postKey(commandKey, down: false, source: source)

        _ = CGAssociateMouseAndMouseCursorPosition(1)
        if let original {
            _ = CGWarpMouseCursorPosition(original)
        }
    }

    /// Performs a ⌘-drag of a menu bar item through its window, for items
    /// the pointer cannot reach: behind the camera housing or off the
    /// screen. The events name the item's window and go to the process
    /// that owns it, so they do not depend on what is under the pointer.
    /// Only up to macOS 26, where every item has a window of its own.
    /// - Parameters:
    ///   - window: The item's window.
    ///   - end: Where to drop the item, next to `target`.
    ///   - target: The window of the item or divider to drop it next to.
    static func commandDrag(window: WindowCapture.WindowInfo, to end: CGPoint, target: WindowCapture.WindowInfo, pace: Double = 1) async {
        let source = CGEventSource(stateID: .hidSystemState)
        let original = CGEvent(source: nil)?.location
        _ = CGAssociateMouseAndMouseCursorPosition(0)

        func scaled(_ milliseconds: UInt64) -> UInt64 {
            UInt64((Double(milliseconds) * max(pace, 1)).rounded())
        }

        // Pressed far from every screen: the item follows the press there,
        // out of sight, and nothing under the pointer is pressed instead.
        let start = CGPoint(x: 20_000, y: 20_000)
        if let down = windowEvent(.leftMouseDown, at: start, window: window.id, pid: window.pid, source: source) {
            await post(down, to: window.pid)
        }
        await pause(milliseconds: scaled(120))
        // The release names the window it lands next to, but goes to the
        // process that holds the item.
        if let up = windowEvent(.leftMouseUp, at: end, window: target.id, pid: window.pid, source: source) {
            await post(up, to: window.pid)
        }
        await pause(milliseconds: scaled(120))

        _ = CGAssociateMouseAndMouseCursorPosition(1)
        if let original {
            _ = CGWarpMouseCursorPosition(original)
        }
    }

    /// A ⌘-mouse event for a menu bar item's window, wherever the pointer is.
    private static func windowEvent(_ type: CGEventType, at point: CGPoint, window: CGWindowID, pid: pid_t, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = .maskCommand
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        if let windowField = CGEventField(rawValue: 0x33) {
            // The window the event belongs to, which the app dispatches by.
            event.setIntegerValueField(windowField, value: Int64(window))
        }
        return event
    }

    /// Lets the window server see the event, then hands it to the process
    /// that owns the window.
    private static func post(_ event: CGEvent, to pid: pid_t) async {
        event.post(tap: .cgSessionEventTap)
        await pause(milliseconds: 15)
        event.postToPid(pid)
    }

    private static func postMouse(_ type: CGEventType, at point: CGPoint, source: CGEventSource?, flags: CGEventFlags) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private static func postKey(_ key: CGKeyCode, down: Bool, source: CGEventSource?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        event.flags = down ? .maskCommand : []
        event.post(tap: .cghidEventTap)
    }

    private static func pause(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}
