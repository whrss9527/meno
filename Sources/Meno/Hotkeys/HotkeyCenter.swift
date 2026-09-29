import AppKit
import Carbon.HIToolbox
import MenoCore

/// Registers system-wide keyboard shortcuts with the Carbon hot key API,
/// which needs no extra permission.
@MainActor
final class HotkeyCenter {
    private var handlerRef: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var suspendCount = 0

    private static let signature: OSType = 0x4D45_4E4F // "MENO"

    func install() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != OSStatus(noErr) {
            Log.hotkeys.error("Installing the hot key handler failed: \(status)")
        }
    }

    /// Removes every registered shortcut.
    func unregisterAll() {
        for ref in registrations.values {
            _ = UnregisterEventHotKey(ref)
        }
        registrations.removeAll()
        actions.removeAll()
    }

    /// Registers a shortcut. Returns `false` if macOS refused it, which
    /// usually means another app already uses it.
    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping () -> Void) -> Bool {
        install()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers.carbonFlags, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == OSStatus(noErr), let ref else {
            Log.hotkeys.error("Registering \(combo.displayString(), privacy: .public) failed: \(status)")
            return false
        }
        registrations[id] = ref
        actions[id] = action
        return true
    }

    /// Ignores shortcuts while one is being recorded.
    func suspend() {
        suspendCount += 1
    }

    func resume() {
        suspendCount = max(suspendCount - 1, 0)
    }

    fileprivate func handle(id: UInt32) {
        guard suspendCount == 0, let action = actions[id] else { return }
        action()
    }
}

private let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == OSStatus(noErr) else { return status }
    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        center.handle(id: id)
    }
    return OSStatus(noErr)
}
