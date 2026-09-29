import AppKit

enum Relauncher {
    /// Quits Meno and opens it again once this copy has quit. Returns
    /// `false` when Meno keeps running because that failed.
    ///
    /// After an update, `previous` is the copy that was replaced. The new
    /// copy deletes it once it has run for a few seconds. When the new copy
    /// cannot be opened, or quits before then, the previous one is put back
    /// and opened instead.
    @MainActor
    @discardableResult
    static func relaunch(previous: URL? = nil) -> Bool {
        // $0 is the app, $1 this process and $2 the previous copy, if any.
        // A copy that does not quit within a minute is left alone rather
        // than joined by a second one. The new copy counts as running when
        // a process was started from its executable.
        let script = """
        i=0
        while /bin/kill -0 "$1" 2>/dev/null; do
          if [ "$i" -ge 600 ]; then exit 1; fi
          /bin/sleep 0.1
          i=$((i + 1))
        done
        running() {
          /bin/ps -A -o command= | P="$0/Contents/MacOS/" /usr/bin/awk 'index($0, ENVIRON["P"]) == 1 { found = 1 } END { exit !found }'
        }
        if /usr/bin/open "$0" || { /bin/sleep 1; /usr/bin/open "$0"; }; then
          [ -n "$2" ] || exit 0
          i=0
          while [ -e "$2" ] && [ "$i" -lt 45 ]; do /bin/sleep 1; i=$((i + 1)); done
          if [ ! -e "$2" ] || running; then exit 0; fi
        fi
        [ -n "$2" ] && [ -d "$2" ] || exit 1
        /bin/mv "$0" "$2.rejected" || exit 1
        /bin/mv "$2" "$0" || { /bin/mv "$2.rejected" "$0"; exit 1; }
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
