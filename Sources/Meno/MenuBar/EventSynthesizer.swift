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
