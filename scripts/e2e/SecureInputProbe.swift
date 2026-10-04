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

    static func swap(pids: Set<pid_t>, byWindow: Bool) async throws -> Bool {
        var before = windows(for: pids)
        for _ in 0..<30 where before.count != 2 {
            try await Task.sleep(nanoseconds: 100_000_000)
            before = windows(for: pids)
        }
        if before.count != 2 {
            for info in WindowCapture.windowList(onScreenOnly: false) where pids.contains(info.pid) {
                print("PROBE_WINDOW pid=\(info.pid) id=\(info.id) layer=\(info.layer) bounds=\(info.bounds)")
            }
            print("PROBE_WINDOW expected=2 found=\(before.count)")
            fflush(stdout)
        }
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
