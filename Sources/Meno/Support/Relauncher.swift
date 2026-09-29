import AppKit

enum Relauncher {
    /// Quits Meno and opens it again once this copy has quit. After an
    /// update, `previous` is the copy that was replaced: when the new copy
    /// cannot be opened, the previous one is put back and opened instead.
    /// Returns `false` when Meno keeps running because that failed.
    @MainActor
    @discardableResult
    static func relaunch(previous: URL? = nil) -> Bool {
        // Waits up to a minute for this copy to quit. One that does not quit
        // is left alone rather than joined by a second one.
        let script = """
        i=0
        while /bin/kill -0 "$1" 2>/dev/null; do
          if [ "$i" -ge 600 ]; then exit 1; fi
          /bin/sleep 0.1
          i=$((i + 1))
        done
        /usr/bin/open "$0" && exit 0
        if [ -n "$2" ] && [ -d "$2" ] && /bin/mv "$0" "$2.rejected"; then /bin/mv "$2" "$0"; fi
        /usr/bin/open "$0"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundlePath, String(AppInfo.ownPID), previous?.path ?? ""]
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
