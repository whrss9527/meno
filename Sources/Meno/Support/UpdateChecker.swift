import AppKit
import MenoCore

/// Looks for a newer release on GitHub and installs it when asked. Meno only
/// connects when asked, or once a day when the person turned that on.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case downloading
        case installing
    }

    @Published private(set) var phase: Phase = .idle
    /// A release newer than this copy, once a check found one.
    @Published private(set) var available: UpdateRelease?

    unowned let model: AppModel

    static let repository = "whrss9527/meno"
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    /// The newest version announced by the daily check, so it is announced once.
    private static let announcedKey = "AnnouncedUpdateVersion"
    /// When GitHub was last asked. Time asleep counts, unlike a timer's.
    private static let lastCheckKey = "LastUpdateCheck"

    private var loop: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    /// Whether Meno can put the available release in place of itself.
    var canInstall: Bool {
        guard let available else { return false }
        return UpdateInstaller.blocker == nil && available.appArchive(repository: Self.repository) != nil
    }

    /// Starts or stops the daily check to match the settings.
    func settingsChanged() {
        guard model.settings.general.checksForUpdates else {
            loop?.cancel()
            loop = nil
            return
        }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            while !Task.isCancelled {
                let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
                if Date().timeIntervalSince(last) >= 24 * 60 * 60 {
                    await self?.check(userInitiated: false)
                }
                try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000)
            }
        }
    }

    /// Checks now. Only a newer version is reported unless the person asked.
    func check(userInitiated: Bool) async {
        guard phase == .idle else { return }
        phase = .checking
        defer {
            if phase == .checking { phase = .idle }
        }
        do {
            let release = try await Self.latestRelease()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            guard let latest = release.version, let current = AppVersion(AppInfo.version) else {
                throw URLError(.cannotParseResponse)
            }
            guard current < latest else {
                available = nil
                if userInitiated {
                    model.toasts.show(String(localized: "Meno is up to date."), symbol: "checkmark.circle.fill")
                }
                return
            }
            available = release
            let defaults = UserDefaults.standard
            if !userInitiated, defaults.string(forKey: Self.announcedKey) == latest.description { return }
            defaults.set(latest.description, forKey: Self.announcedKey)
            announce(release, version: latest)
        } catch {
            Log.app.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            if userInitiated {
                model.toasts.show(String(localized: "Could not check for updates."), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func announce(_ release: UpdateRelease, version: AppVersion) {
        var actions: [ToastCenter.Action] = []
        if canInstall {
            actions.append(ToastCenter.Action(title: String(localized: "Install and Relaunch")) { [weak self] in
                Task { await self?.install() }
            })
            actions.append(ToastCenter.Action(title: String(localized: "Release Notes")) {
                NSWorkspace.shared.open(release.htmlURL)
            })
        } else {
            actions.append(ToastCenter.Action(title: String(localized: "Download")) {
                NSWorkspace.shared.open(release.htmlURL)
            })
        }
        model.toasts.show(
            String(localized: "Meno \(version.description) is available."),
            symbol: "arrow.down.circle.fill",
            actions: actions,
            duration: 12
        )
    }

    /// Downloads the latest release, puts it in place of this copy and
    /// opens it. On failure the release page is offered instead.
    func install() async {
        guard phase == .idle, var release = available, var version = release.version else { return }
        phase = .downloading
        model.toasts.show(
            String(localized: "Downloading Meno \(version.description)…"),
            symbol: "arrow.down.circle",
            duration: 60
        )
        var prepared: UpdateInstaller.Prepared?
        do {
            // What the check found may be a day old: files of a release can
            // be replaced, and a newer one may be out.
            let latest = try await Self.latestRelease()
            guard let latestVersion = latest.version, let current = AppVersion(AppInfo.version), current < latestVersion else {
                // The release was withdrawn or is no longer the latest.
                available = nil
                phase = .idle
                model.toasts.show(String(localized: "Meno is up to date."), symbol: "checkmark.circle.fill")
                return
            }
            release = latest
            version = latestVersion
            available = latest
            let ready = try await UpdateInstaller.prepare(release, repository: Self.repository)
            prepared = ready
            phase = .installing
            let previous = try UpdateInstaller.replace(with: ready)
            Log.app.info("Installed Meno \(version.description, privacy: .public), relaunching")
            if !Relauncher.relaunch(previous: previous) {
                phase = .idle
                available = nil
                model.toasts.show(
                    String(localized: "Meno \(version.description) is installed. Quit Meno and open it again to use it."),
                    symbol: "checkmark.circle.fill",
                    duration: 12
                )
            }
        } catch {
            if let prepared {
                UpdateInstaller.discard(prepared)
            }
            phase = .idle
            Log.app.error("Installing the update failed: \(error.localizedDescription, privacy: .public)")
            model.toasts.show(
                String(localized: "Could not install the update. \(error.localizedDescription)"),
                symbol: "exclamationmark.triangle.fill",
                actions: [ToastCenter.Action(title: String(localized: "Download")) { [release] in
                    NSWorkspace.shared.open(release.htmlURL)
                }],
                duration: 12
            )
        }
    }

    private static func latestRelease() async throws -> UpdateRelease {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Meno/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(UpdateRelease.self, from: data)
    }
}
