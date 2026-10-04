import AppKit
import ApplicationServices
import Carbon

// The event synthesizer only needs this window value, not image capture.
// Compile the production EventSynthesizer.swift alongside this probe.
enum WindowCapture {
    struct WindowInfo {
        let id: CGWindowID
        let pid: pid_t
        let layer: Int
        let bounds: CGRect
        let isOnScreen: Bool
    }
}

/// Measures the two production drag paths with real Secure Keyboard Entry.
@main
struct SecureInputProbe {
    static func windows(for pids: Set<pid_t>) -> [WindowCapture.WindowInfo] {
        let layer = Int(CGWindowLevelForKey(.statusWindow))
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let level = info[kCGWindowLayer as String] as? Int, level == layer,
                  let value = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: value as CFDictionary), bounds.width > 1 else { return nil }
            return WindowCapture.WindowInfo(id: number, pid: pid, layer: level, bounds: bounds, isOnScreen: true)
        }.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    static func swap(pids: Set<pid_t>, byWindow: Bool) async throws -> Bool {
        let before = windows(for: pids)
        precondition(before.count == 2, "Both helper items must be visible")
        let left = before[0], right = before[1]
        let end = CGPoint(x: left.bounds.minX, y: left.bounds.midY)
        if byWindow {
            await EventSynthesizer.commandDrag(window: right, to: end, target: left)
        } else {
            await EventSynthesizer.commandDrag(
                from: CGPoint(x: right.bounds.midX, y: right.bounds.midY), to: end
            )
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        let after = windows(for: pids)
        guard let moved = after.first(where: { $0.id == right.id }),
              let reference = after.first(where: { $0.id == left.id }) else {
            preconditionFailure("A helper window vanished during the probe")
        }
        return moved.bounds.minX < reference.bounds.minX
    }

    static func main() async throws {
        precondition(AXIsProcessTrusted(), "Accessibility is required for real drag measurements")
        precondition(!IsSecureEventInputEnabled(), "Another process is already holding secure input")
        let pids = Set(CommandLine.arguments.dropFirst().compactMap(Int32.init))
        precondition(pids.count == 2)
        // Both paths must work first; a broken baseline cannot show whether
        // secure input changed anything.
        for byWindow in [true, false] {
            let baseline = try await swap(pids: pids, byWindow: byWindow)
            precondition(baseline, "The baseline drag did not move an item")
            precondition(EnableSecureEventInput() == noErr)
            let secureResult: Bool
            do {
                defer { DisableSecureEventInput() }
                precondition(IsSecureEventInputEnabled())
                secureResult = try await swap(pids: pids, byWindow: byWindow)
                precondition(IsSecureEventInputEnabled(), "The probe lost secure input")
            }
            print("SECURE_INPUT_PROBE path=\(byWindow ? "window" : "pointer") baseline_moved=\(baseline) secure_moved=\(secureResult)")
        }
    }
}
