import AppKit
import Carbon
import IOKit

/// Secure Keyboard Entry can prevent synthetic input from reaching apps.
enum SecureInput {
    static var isEnabled: Bool { IsSecureEventInputEnabled() }

    static func waitUntilDisabled() async throws {
        try Task.checkCancellation()
        while isEnabled {
            try await Task.sleep(nanoseconds: 500_000_000)
            try Task.checkCancellation()
        }
    }

    /// The registry sometimes names the holder, but that is not a public
    /// guarantee. A missing name must never mean that input is unblocked.
    static var ownerName: String? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let sessions = IORegistryEntryCreateCFProperty(
            root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [[String: Any]] else { return nil }
        for session in sessions {
            if let uid = session["kCGSSessionUserIDKey"] as? NSNumber, uid.uint32Value != getuid() { continue }
            guard let number = session["kCGSSessionSecureInputPID"] as? NSNumber, number.int32Value > 0,
                  let app = NSRunningApplication(processIdentifier: number.int32Value) else { continue }
            if let name = app.localizedName, !name.isEmpty { return name }
        }
        return nil
    }
}
