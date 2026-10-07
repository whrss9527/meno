import AppKit
import ApplicationServices
import Carbon

/// Measures the two production drag paths with real Secure Keyboard Entry.
@main
struct SecureInputProbe {
    static func windows(for pids: Set<pid_t>) -> [WindowCapture.WindowInfo] {
        // macOS can host an item's window in another process. Meno matches
        // its AX frame to the window rather than filtering by owner PID.
        let frames = pids.sorted().flatMap { pid in
            MenuBarScanner.items(of: ScanTarget(pid: pid, bundleID: nil, name: "Secure input probe"))
                .map(\.frame)
        }
        return WindowCapture.itemWindows(at: frames).compactMap { $0 }
            .sorted { $0.bounds.minX < $1.bounds.minX }
    }

    static func describe(_ windows: [WindowCapture.WindowInfo]) -> String {
        windows.map { "pid=\($0.pid) id=\($0.id) bounds=\($0.bounds) on_screen=\($0.isOnScreen)" }.joined(separator: "; ")
    }

    static func swap(pids: Set<pid_t>, byWindow: Bool) async throws -> Bool {
        // Wait for three matching snapshots, rather than the helper's early
        // AppKit window frame (which can still be x=0 on macOS 26).
        var before: [WindowCapture.WindowInfo] = []
        var stable = 0
        for _ in 0..<50 {
            let current = windows(for: pids)
            let unchanged = current.count == 2 && zip(current, before).allSatisfy {
                $0.id == $1.id && $0.bounds == $1.bounds
            } && before.count == 2
            stable = unchanged ? stable + 1 : 0
            before = current
            if stable >= 3 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        print("PROBE_WINDOW ready=\(stable >= 3) \(describe(before))")
        fflush(stdout)
        precondition(stable >= 3 && before.count == 2, "Both helper items must be visible and stable")
        precondition(Set(before.map(\.id)).count == 2, "Helpers must resolve to distinct windows")
        let sourceID = before[1].id, referenceID = before[0].id
        // Match ItemMover: two window attempts, or three pointer attempts,
        // progressively slower. Keep moving the same item and reference.
        for attempt in 0..<(byWindow ? 2 : 3) {
            let current = windows(for: pids)
            guard let right = current.first(where: { $0.id == sourceID }),
                  let left = current.first(where: { $0.id == referenceID }) else {
                preconditionFailure("A helper window vanished before the probe")
            }
            let inset = min(left.bounds.width * 0.3, 7)
            let x = byWindow ? left.bounds.minX : left.bounds.minX + inset - CGFloat(attempt) * 3
            let end = CGPoint(x: x, y: left.bounds.midY)
            let pace = 1 + Double(attempt) * 0.75
            if byWindow {
                await EventSynthesizer.commandDrag(window: right, to: end, target: left, pace: pace)
            } else {
                await EventSynthesizer.commandDrag(
                    from: CGPoint(x: right.bounds.midX, y: right.bounds.midY), to: end, pace: pace
                )
            }
            try await Task.sleep(nanoseconds: 700_000_000)
            let after = windows(for: pids)
            print("PROBE_WINDOW path=\(byWindow ? "window" : "pointer") attempt=\(attempt) before=\(describe(current)) after=\(describe(after))")
            fflush(stdout)
            guard let moved = after.first(where: { $0.id == sourceID }),
                  let reference = after.first(where: { $0.id == referenceID }) else {
                preconditionFailure("A helper window vanished during the probe")
            }
            if moved.bounds.minX < reference.bounds.minX { return true }
        }
        return false
    }

    static func main() async throws {
        precondition(AXIsProcessTrusted(), "Accessibility is required for real drag measurements")
        precondition(!IsSecureEventInputEnabled(), "Another process is already holding secure input")
        precondition(CommandLine.arguments.count == 4)
        let pids = Set(CommandLine.arguments[1...2].compactMap(Int32.init))
        precondition(pids.count == 2)
        // Both paths must work first; a broken baseline cannot show whether
        // secure input changed anything.
        for byWindow in [true, false] {
            let baseline = try await swap(pids: pids, byWindow: byWindow)
            precondition(baseline, "The baseline drag did not move an item")
            let holder = Process()
            holder.executableURL = URL(fileURLWithPath: CommandLine.arguments[3])
            try holder.run()
            let secureResult: Bool
            do {
                defer {
                    kill(holder.processIdentifier, SIGUSR1)
                    holder.waitUntilExit()
                }
                for _ in 0..<30 where !IsSecureEventInputEnabled() {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                precondition(holder.isRunning, "The holder failed to start")
                precondition(IsSecureEventInputEnabled())
                secureResult = try await swap(pids: pids, byWindow: byWindow)
                precondition(IsSecureEventInputEnabled(), "The probe lost secure input")
            }
            precondition(!IsSecureEventInputEnabled(), "Secure input was not released")
            print("SECURE_INPUT_PROBE path=\(byWindow ? "window" : "pointer") baseline_moved=\(baseline) secure_moved=\(secureResult)")
        }
    }
}
