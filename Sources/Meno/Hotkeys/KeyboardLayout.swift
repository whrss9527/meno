import AppKit
import Carbon.HIToolbox
import MenoCore

enum KeyboardLayout {
    /// The character a key produces on the current keyboard layout, used
    /// to display shortcuts the way the keyboard is labelled.
    static func name(for keyCode: UInt32) -> String? {
        if KeyCodeNames.isLayoutIndependent(keyCode) {
            return KeyCodeNames.name(for: keyCode)
        }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return KeyCodeNames.name(for: keyCode)
        }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return KeyCodeNames.name(for: keyCode) }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == OSStatus(noErr), length > 0 else { return KeyCodeNames.name(for: keyCode) }
        let string = String(utf16CodeUnits: characters, count: length).uppercased()
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? KeyCodeNames.name(for: keyCode) : trimmed
    }

    static func displayString(for combo: KeyCombo) -> String {
        combo.displayString(keyName: name(for: combo.keyCode))
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
