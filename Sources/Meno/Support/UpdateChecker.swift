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
    /// What changed in every version from this copy's up to `available`.
    var notes: UpdateNotes? {
        guard let loadedNotes, loadedNotes.tagName == available?.tagName else { return nil }
        return loadedNotes
    }

    @Published private var loadedNotes: UpdateNotes?
    /// The release whose notes are read or being read, so the list of
    /// releases is read once for each new version.
    private var notesTag: String?

    unowned let model: AppModel

    static let repository = "whrss9527/meno"
    static let source = UpdateSource(override: ProcessInfo.processInfo.environment["MENO_UPDATE_URL"])
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    private static let releasesURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=\(UpdateNotes.pageSize)")!
    /// The newest version announced by the daily check, so it is announced once.
    private static let announcedKey = "AnnouncedUpdateVersion"
    /// When GitHub was last asked. Time asleep counts, unlike a timer's.
    private static let lastCheckKey = "LastUpdateCheck"

    private var loop: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    /// Cleans an installed update after its startup grace period and reports rollback.
    func finishInstallation() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let rejected = UpdateInstaller.removeLeftovers() else { return }
            self?.model.toasts.show(
                String(localized: "Meno \(rejected) did not start on this Mac, so this version was put back."),
                symbol: "exclamationmark.triangle.fill",
                duration: 12
            )
        }
    }

    /// Whether Meno can put the available release in place of itself.
    var canInstall: Bool {
        guard let available else { return false }
        return UpdateInstaller.blocker == nil && available.appArchive(repository: Self.repository, source: Self.source) != nil
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
            loadNotes(for: release, current: current)
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
            // Settings › About lists what changed in every version since this one.
            actions.append(ToastCenter.Action(title: String(localized: "Release Notes")) { [weak self] in
                self?.model.openSettings(.about)
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
        // A check that runs meanwhile, for example the daily one, ends first.
        var waited = 0
        while phase == .checking, waited < 80 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            waited += 1
        }
        guard phase == .idle else { return }
        guard var release = available, var version = release.version else {
            // The check that ran meanwhile found nothing newer.
            model.toasts.show(String(localized: "Meno is up to date."), symbol: "checkmark.circle.fill")
            return
        }
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
            loadNotes(for: latest, current: current)
            let ready = try await UpdateInstaller.prepare(release, repository: Self.repository, source: Self.source)
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

    /// Reads the notes of the versions up to `release` from the list of
    /// releases. Without the list, the notes of `release` alone are shown,
    /// and the list is asked for again at the next check.
    private func loadNotes(for release: UpdateRelease, current: AppVersion) {
        guard notesTag != release.tagName else { return }
        notesTag = release.tagName
        // The notes are in English and Chinese; Traditional Chinese reads the Chinese ones.
        let chinese = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true
        Task { [weak self] in
            var releases: [UpdateRelease]?
            do {
                releases = try await Self.recentReleases()
            } catch {
                Log.app.error("Reading the release notes failed: \(error.localizedDescription, privacy: .public)")
            }
            guard let self, self.notesTag == release.tagName else { return }
            if releases == nil {
                self.notesTag = nil
            }
            self.loadedNotes = UpdateNotes(current: current, latest: release, releases: releases, chinese: chinese)
        }
    }

    private static func latestRelease() async throws -> UpdateRelease {
        let data = try await get(source?.latestURL ?? latestReleaseURL)
        return try JSONDecoder().decode(UpdateRelease.self, from: data)
    }

    /// The newest releases, newest first, for their notes.
    private static func recentReleases() async throws -> [UpdateRelease] {
        if source != nil { return [] }
        let data = try await get(releasesURL)
        return try JSONDecoder().decode([UpdateRelease].self, from: data)
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Meno/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        // Otherwise the Mac's preferred languages would be sent along.
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
