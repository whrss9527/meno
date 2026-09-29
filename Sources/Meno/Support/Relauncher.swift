import AppKit

enum Relauncher {
    /// Quits Meno and opens it again once this copy has quit. `leftovers`,
    /// for example the previous copy after an update, is deleted in between.
    /// Returns `false` when Meno keeps running because that failed.
    @MainActor
    @discardableResult
    static func relaunch(removing leftovers: URL? = nil) -> Bool {
        // Waits up to ten seconds, so that the new copy does not find this
        // one still running.
        let script = """
        i=0
        while /bin/kill -0 "$1" 2>/dev/null && [ "$i" -lt 100 ]; do /bin/sleep 0.1; i=$((i + 1)); done
        if [ -n "$2" ]; then /bin/rm -rf "$2"; fi
        /usr/bin/open "$0"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundlePath, String(AppInfo.ownPID), leftovers?.path ?? ""]
        do {
            try process.run()
        } catch {
            Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
