import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
// Only the queue label needs AppInfo; macOS compiles the production type.
enum AppInfo { static let bundleIdentifier = "meno-command-checks-fixture" }
#endif

private struct CheckFailure: Error { let message: String }
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(message: message) }
}

/// Shared with the production worker and its delivery closure.
private final class Observations: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Set<String>] = []
    private var deliveries: [@Sendable () -> Void] = []
    func record(_ value: Set<String>) { lock.lock(); results.append(value); lock.unlock() }
    func enqueue(_ work: @escaping @Sendable () -> Void) { lock.lock(); deliveries.append(work); lock.unlock() }
    var values: [Set<String>] { lock.lock(); defer { lock.unlock() }; return results }
    var pending: Int { lock.lock(); defer { lock.unlock() }; return deliveries.count }
    func flush() {
        lock.lock(); let work = deliveries; deliveries = []; lock.unlock()
        work.forEach { $0() }
    }
}

@main
private enum CommandChecksDriver {
    private static func wait(_ message: String, timeout: TimeInterval = 3,
                             until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !predicate() {
            if ContinuousClock.now >= deadline { throw CheckFailure(message: message) }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    private static func pid(_ url: URL) throws -> pid_t {
        let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = pid_t(text) else { throw CheckFailure(message: "Missing process identity") }
        return result
    }
    private static func heartbeat(_ url: URL) -> Int { (try? Data(contentsOf: url).count) ?? 0 }
    private static func slowCommand(_ root: URL, _ index: Int) -> String {
        let file: (String) -> String = { quote(root.appendingPathComponent($0).path) }
        // The child has a finite lifetime even if a broken test exits early.
        return "printf '\(index)'; echo $$ > \(file("parent-\(index)")); " +
            "(n=0; while [ $n -lt 500 ]; do printf x >> \(file("beat-\(index)")); n=$((n+1)); /bin/sleep 0.02; done) & " +
            "echo $! > \(file("child-\(index)")); : > \(file("started-\(index)")); wait"
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meno-command-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await pauseStopsTheCurrentGroupAndRemainingNine(root)
        try await replacementStartsWithoutWaitingForTheOldRound(root)
        try await queuedResultsCheckTheirRevisionAtDelivery()
        try await ordinaryStatusAndFiveSecondTimeoutRemain()
        print("Command checks: 4 production lifecycle checks passed")
    }

    private static func pauseStopsTheCurrentGroupAndRemainingNine(_ root: URL) async throws {
        let observed = Observations()
        let checks = CommandChecks { observed.record($0) }
        defer { checks.watch([]) }
        let commands = Set((0..<10).map { slowCommand(root, $0) })
        checks.watch(commands)
        try await wait("The first command did not start") {
            heartbeat(root.appendingPathComponent("beat-0")) > 0 &&
                FileManager.default.fileExists(atPath: root.appendingPathComponent("child-0").path)
        }
        let parent = try pid(root.appendingPathComponent("parent-0"))
        let child = try pid(root.appendingPathComponent("child-0"))
        try require(getpgid(parent) == parent && getpgid(child) == parent, "The fixture did not own a separate group")
        for _ in 0..<50 { checks.watch(commands) }
        let start = ContinuousClock.now
        checks.watch([])
        try await wait("Pause did not stop and reap the current command", timeout: 1) { kill(parent, 0) == -1 && errno == ESRCH }
        try require(start.duration(to: .now) < .seconds(1), "Pause waited for the old round")
        var status: Int32 = 0
        try require(waitpid(parent, &status, WNOHANG) == -1 && errno == ECHILD, "The worker did not reap its child")
        let before = heartbeat(root.appendingPathComponent("beat-0"))
        try await Task.sleep(nanoseconds: 120_000_000)
        try require(heartbeat(root.appendingPathComponent("beat-0")) == before, "An owned descendant kept running")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try require(files.filter { $0.hasPrefix("started-") }.count == 1, "Pause started remaining old commands")
        try require(observed.values.allSatisfy(\.isEmpty), "Pause published an obsolete success")
    }

    private static func replacementStartsWithoutWaitingForTheOldRound(_ root: URL) async throws {
        let observed = Observations()
        let checks = CommandChecks { observed.record($0) }
        defer { checks.watch([]) }
        checks.watch([slowCommand(root, 10)])
        try await wait("Replacement fixture did not start") { heartbeat(root.appendingPathComponent("beat-10")) > 0 }
        let fresh = "printf ready > " + quote(root.appendingPathComponent("replacement").path)
        checks.watch([fresh])
        try await wait("A new request waited behind the old command", timeout: 1) { observed.values.contains([fresh]) }
        try require(FileManager.default.fileExists(atPath: root.appendingPathComponent("replacement").path), "New command was not executed")
        try require(!observed.values.contains([slowCommand(root, 10)]), "Old command succeeded after replacement")
    }

    private static func queuedResultsCheckTheirRevisionAtDelivery() async throws {
        let observed = Observations()
        let checks = CommandChecks(deliver: { observed.enqueue($0) }, onChange: { observed.record($0) })
        defer { checks.watch([]) }
        checks.watch(["true"])
        try await wait("Success was not queued") { observed.pending >= 2 }
        checks.watch([])
        try await wait("Pause was not queued") { observed.pending >= 3 }
        observed.flush()
        try require(observed.values.allSatisfy(\.isEmpty), "An already queued success escaped pause")
        checks.watch(["true"])
        try await wait("Re-enabled request did not complete") { observed.pending >= 2 }
        observed.flush()
        try require(observed.values.last == ["true"], "A → off → A lost its new result to old deduplication")
    }

    private static func ordinaryStatusAndFiveSecondTimeoutRemain() async throws {
        try require(CommandChecks.succeeds("printf ignored; true"), "Ordinary success changed")
        try require(!CommandChecks.succeeds("exit 7"), "A nonzero status succeeded")
        try require(!CommandChecks.succeeds("   "), "An empty command succeeded")
        let start = ContinuousClock.now
        let result = await Task.detached { CommandChecks.succeeds("exec /bin/sleep 30") }.value
        try require(!result, "A timeout succeeded")
        let elapsed = start.duration(to: .now)
        try require(elapsed >= .seconds(5) && elapsed < .seconds(7), "The five-second command budget changed")
    }
}
