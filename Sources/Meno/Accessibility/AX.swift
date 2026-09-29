import ApplicationServices
import AppKit

/// Thin helpers around the C Accessibility API.
enum AX {
    enum Attribute {
        static let children = "AXChildren"
        static let extrasMenuBar = "AXExtrasMenuBar"
        static let menuBar = "AXMenuBar"
        static let position = "AXPosition"
        static let size = "AXSize"
        static let title = "AXTitle"
        static let description = "AXDescription"
        static let identifier = "AXIdentifier"
        static let help = "AXHelp"
        static let role = "AXRole"
        static let enabled = "AXEnabled"
        static let selected = "AXSelected"
    }

    enum Action {
        static let press = "AXPress"
        static let showMenu = "AXShowMenu"
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let value = value(element, attribute), CFGetTypeID(value) == CFArrayGetTypeID() else {
            return []
        }
        let array = unsafeBitCast(value, to: CFArray.self)
        var result: [AXUIElement] = []
        let count = CFArrayGetCount(array)
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(array, index) else { continue }
            let object = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
            if CFGetTypeID(object) == AXUIElementGetTypeID() {
                result.append(unsafeBitCast(object, to: AXUIElement.self))
            }
        }
        return result
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = value(element, attribute), CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        let string = unsafeBitCast(value, to: CFString.self) as String
        return string.isEmpty ? nil : string
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = value(element, attribute), CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
    }

    static func point(_ element: AXUIElement, _ attribute: String = Attribute.position) -> CGPoint? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String = Attribute.size) -> CGSize? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size) else { return nil }
        return size
    }

    /// The element's frame in Quartz global coordinates.
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(element), let size = size(element) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let names else { return [] }
        return (names as? [String]) ?? []
    }

    static func setTimeout(_ element: AXUIElement, seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    /// Performs an action off the main thread.
    ///
    /// Opening a menu keeps the target app busy until the menu closes, so the
    /// call usually ends with `.cannotComplete` after the timeout even though
    /// it worked. Both results count as success.
    static func perform(_ action: String, on element: AXUIElement, timeout: Float = 0.6) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                AXUIElementSetMessagingTimeout(element, timeout)
                let result = AXUIElementPerformAction(element, action as CFString)
                continuation.resume(returning: result == .success || result == .cannotComplete)
            }
        }
    }

    /// Lowers the default timeout for every Accessibility call from Meno,
    /// so an unresponsive app cannot stall a scan.
    static func configureGlobalTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }
}
