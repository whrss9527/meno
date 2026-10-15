#if os(macOS)
import Darwin
#else
import Glibc
#endif
import Foundation

/// Replacement is synchronous on the caller, even while the worker waits
/// for a child. No process operation or callback runs under this lock.
private final class CommandCheckRequest: @unchecked Sendable {
    struct Snapshot: Sendable {
        let revision: UInt64
        let commands: Set<String>
    }
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var commands: Set<String> = []

    func replace(_ commands: Set<String>) -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard commands != self.commands else { return nil }
        revision &+= 1
        self.commands = commands
        return Snapshot(revision: revision, commands: commands)
    }

    func isCurrent(_ revision: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.revision == revision
    }
}

/// Runs the shell commands of rule conditions every few seconds and tells
/// which of them succeed, that is exit with status 0.
///
/// Commands run one after the other on a queue of their own, with zsh and a
/// `PATH` that includes Homebrew. Their output is discarded. A command that
/// takes longer than ``timeout`` is stopped, together with anything it
/// started, and counts as failing. Nothing runs while no enabled rule has
/// such a condition.
final class CommandChecks: @unchecked Sendable {
    /// Seconds between two runs of the commands.
    static let interval: TimeInterval = 10
    /// Seconds a command may take.
    static let timeout: TimeInterval = 5

    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).commands", qos: .utility)
    private let onChange: @Sendable (Set<String>) -> Void
    private let deliver: @Sendable (@escaping @Sendable () -> Void) -> Void
    private let request = CommandCheckRequest()

    // Only used on `queue`.
    private var commands: Set<String> = []
    private var succeeded: Set<String> = []
    private var timer: DispatchSourceTimer?
    private var revision: UInt64 = 0
    private var reportedRevision: UInt64?

    /// `onChange` runs on the main queue with the commands that succeed.
    init(deliver: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = {
        DispatchQueue.main.async(execute: $0)
    }, onChange: @escaping @Sendable (Set<String>) -> Void) {
        self.deliver = deliver
        self.onChange = onChange
    }

    /// Starts running these commands, or stops when there are none.
    func watch(_ commands: Set<String>) {
        guard let snapshot = request.replace(commands) else { return }
        queue.async { [self] in
            guard request.isCurrent(snapshot.revision) else { return }
            self.commands = snapshot.commands
            revision = snapshot.revision
            // A changed request needs fresh results, including after A → off → A.
            report([], revision: snapshot.revision)
            if snapshot.commands.isEmpty {
                timer?.cancel()
                timer = nil
                return
            }
            if timer == nil {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .seconds(2))
                timer.setEventHandler { [weak self] in self?.runAll() }
                timer.resume()
                self.timer = timer
            }
            runAll()
        }
    }

    private func runAll() {
        let revision = self.revision
        guard request.isCurrent(revision) else { return }
        var result: Set<String> = []
        for command in commands.sorted() {
            guard request.isCurrent(revision) else { return }
            if Self.succeeds(command, isCurrent: { [request] in request.isCurrent(revision) }) {
                result.insert(command)
            }
        }
        guard request.isCurrent(revision) else { return }
        report(result, revision: revision)
    }

    private func report(_ result: Set<String>, revision: UInt64) {
        guard result != succeeded || reportedRevision != revision else { return }
        succeeded = result
        reportedRevision = revision
        deliver { [request, onChange] in
            guard request.isCurrent(revision) else { return }
            onChange(result)
        }
    }

    // MARK: - Running

    private static let environment: [String] = {
        var values = ProcessInfo.processInfo.environment
        let path = values["PATH"].map { ":" + $0 } ?? ""
        values["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" + path
        return values.map { "\($0.key)=\($0.value)" }
    }()

    /// Runs a command and tells whether it exited with status 0 in time.
    static func succeeds(_ command: String) -> Bool {
        succeeds(command, isCurrent: { true })
    }

    private static func succeeds(_ command: String, isCurrent: () -> Bool) -> Bool {
        guard isCurrent(), !command.utf8.contains(0),
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        #if os(macOS)
        let shell = "/bin/zsh"
        #else
        let shell = "/bin/sh"
        #endif
        guard let pid = spawn([shell, "-c", command]) else { return false }
        let started = DispatchTime.now().uptimeNanoseconds
        var status: Int32 = 0
        while true {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            if !isCurrent() || elapsed >= timeout {
                // Only this worker owns and reaps pid. It cannot have been
                // reused before signaling its independently spawned group.
                kill(-pid, SIGKILL)
                while waitpid(pid, &status, 0) == -1, errno == EINTR {}
                return false
            }
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                return status == 0
            }
            if result == -1, errno != EINTR {
                return false
            }
            usleep(20_000)
        }
    }

    /// Starts a process in a new process group, with no input and output
    /// and none of Meno's open files.
    private static func spawn(_ arguments: [String]) -> pid_t? {
        #if os(macOS)
        var attributes: posix_spawnattr_t?
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
        #else
        var attributes = posix_spawnattr_t()
        let flags = POSIX_SPAWN_SETPGROUP
        #endif
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(flags)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else { return nil }

        #if os(macOS)
        var actions: posix_spawn_file_actions_t?
        #else
        var actions = posix_spawn_file_actions_t()
        #endif
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0 else { return nil }

        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else { return nil }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, arguments[0], &actions, &attributes, argv, envp)
        return status == 0 ? pid : nil
    }
}
