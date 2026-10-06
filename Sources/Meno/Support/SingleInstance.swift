import AppKit
import MenoCore

/// Keeps one copy of Meno running at a time. Two would each add their own
/// dividers and move items against each other, for example when a second
/// copy such as "Meno 2" is opened while the first runs.
@MainActor
enum SingleInstance {
    /// Settles which copy runs, before Meno sets anything up: the newer one,
    /// or at the same version the one with the lower process ID. Returns `false` when this
    /// copy hands over to a newer one that runs, which then shows Settings
    /// and gets `urls`, and this copy should quit.
    static func claim(forwarding urls: [URL]) -> Bool {
        guard AppInfo.isBundled else { return true }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleIdentifier)
            .filter { $0.processIdentifier != AppInfo.ownPID && !$0.isTerminated }
        guard !others.isEmpty else { return true }
        let ours = AppVersion(AppInfo.version)
        if let newer = others.first(where: { other in
            guard let ours, let theirs = version(of: other) else { return false }
            return ours < theirs
        }), let url = newer.bundleURL {
            Log.app.info("A newer Meno runs at \(url.path, privacy: .public); handing over")
            // Opening a running app again shows its Settings, as it does
            // when it is opened from Finder.
            if urls.isEmpty {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(urls, withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return false
        }
        // Equal versions never ask each other to quit or wait on one another.
        // Every participant uses the same ordering, including simultaneous starts.
        let peers = others.filter { version(of: $0) == ours }
        if let winner = peers.filter({ $0.processIdentifier < AppInfo.ownPID })
            .min(by: { $0.processIdentifier < $1.processIdentifier }) {
            Log.app.info("An equal-version Meno with PID \(winner.processIdentifier) wins; this copy quits")
            if let url = winner.bundleURL {
                if urls.isEmpty {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.open(urls, withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            return false
        }
        let older = others.filter { version(of: $0) != ours }
        for other in older {
            Log.app.info("Asking the Meno at \(other.bundleURL?.path ?? "?", privacy: .public) to quit")
            other.terminate()
        }
        // It saves its settings on the way out, which this copy then loads.
        let deadline = Date().addingTimeInterval(5)
        while older.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        for other in older where !other.isTerminated {
            other.forceTerminate()
        }
        return true
    }

    /// Other copies of Meno on this Mac. Downloads on their way in, among
    /// them Meno's own updates, copies in the Trash or on disk images, and
    /// builds from the source are left out.
    static var otherCopies: [URL] {
        let own = Bundle.main.bundleURL.standardizedFileURL.path
        let fileManager = FileManager.default
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: AppInfo.bundleIdentifier)
            .map(\.standardizedFileURL)
            .filter { url in
                let path = url.path
                guard path != own, fileManager.fileExists(atPath: path) else { return false }
                let ignored = ["/.Trash/", "/.TemporaryItems/", "/DerivedData/", "/build/Meno.app"]
                if ignored.contains(where: { path.contains($0) }) || path.hasPrefix("/private/var/folders/") {
                    return false
                }
                return !path.hasPrefix("/Volumes/") || path.contains("/Applications/")
            }
    }

    private static func version(of app: NSRunningApplication) -> AppVersion? {
        guard let url = app.bundleURL,
              let text = Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        return AppVersion(text)
    }
}
