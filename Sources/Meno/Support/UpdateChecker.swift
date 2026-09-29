import AppKit
import MenoCore

/// Looks for a newer release on GitHub. Meno only connects when asked, or
/// once a day when the person turned that on.
@MainActor
final class UpdateChecker {
    unowned let model: AppModel

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/whrss9527/meno/releases/latest")!
    /// The newest version announced by the daily check, so it is announced once.
    private static let announcedKey = "AnnouncedUpdateVersion"
    /// When GitHub was last asked. Time asleep counts, unlike a timer's.
    private static let lastCheckKey = "LastUpdateCheck"

    private var loop: Task<Void, Never>?
    private var isChecking = false

    init(model: AppModel) {
        self.model = model
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
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let release = try await Self.latestRelease()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            guard let latest = AppVersion(release.tagName), let current = AppVersion(AppInfo.version) else {
                throw URLError(.cannotParseResponse)
            }
            guard current < latest else {
                if userInitiated {
                    model.toasts.show(String(localized: "Meno is up to date."), symbol: "checkmark.circle.fill")
                }
                return
            }
            let defaults = UserDefaults.standard
            if !userInitiated, defaults.string(forKey: Self.announcedKey) == latest.description { return }
            defaults.set(latest.description, forKey: Self.announcedKey)
            model.toasts.show(
                String(localized: "Meno \(latest.description) is available."),
                symbol: "arrow.down.circle.fill",
                actions: [ToastCenter.Action(title: String(localized: "Download")) { NSWorkspace.shared.open(release.htmlURL) }],
                duration: 12
            )
        } catch {
            Log.app.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            if userInitiated {
                model.toasts.show(String(localized: "Could not check for updates."), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private static func latestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Meno/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}
