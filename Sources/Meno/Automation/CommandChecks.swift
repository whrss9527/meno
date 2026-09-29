import Darwin
import Foundation

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

    // Only used on `queue`.
    private var commands: Set<String> = []
    private var succeeded: Set<String> = []
    private var timer: DispatchSourceTimer?

    /// `onChange` runs on the main queue with the commands that succeed.
    init(onChange: @escaping @Sendable (Set<String>) -> Void) {
        self.onChange = onChange
    }

    /// Starts running these commands, or stops when there are none.
    func watch(_ commands: Set<String>) {
        queue.async { [self] in
            guard commands != self.commands || commands.isEmpty else { return }
            self.commands = commands
            if commands.isEmpty {
                timer?.cancel()
                timer = nil
                report(succeeded.intersection(commands))
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
        var result: Set<String> = []
        for command in commands.sorted() where Self.succeeds(command) {
            result.insert(command)
        }
        report(result)
    }

    private func report(_ result: Set<String>) {
        guard result != succeeded else { return }
        succeeded = result
        DispatchQueue.main.async { [onChange] in onChange(result) }
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
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let pid = spawn(["/bin/zsh", "-c", command]) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        while true {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                return status == 0
            }
            if result == -1, errno != EINTR {
                return false
            }
            if Date() >= deadline {
                // The command runs in a process group of its own, so this
                // also stops whatever it started.
                kill(-pid, SIGKILL)
                while waitpid(pid, &status, 0) == -1, errno == EINTR {}
                return false
            }
            usleep(20_000)
        }
    }

    /// Starts a process in a new process group, with no input and output
    /// and none of Meno's open files.
    private static func spawn(_ arguments: [String]) -> pid_t? {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, arguments[0], &actions, &attributes, argv, envp)
        return status == 0 ? pid : nil
    }
}
