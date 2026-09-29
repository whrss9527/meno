import AppKit
import MenoCore

/// Changes the system-wide spacing between menu bar icons.
///
/// macOS reads `NSStatusItemSpacing` and `NSStatusItemSelectionPadding`
/// from the current-host global domain when an app starts, so apps that
/// own menu bar items have to be relaunched to pick up new values.
@MainActor
final class SpacingController: ObservableObject {
    unowned let model: AppModel

    @Published private(set) var isApplying = false

    static let spacingKey = "NSStatusItemSpacing"
    static let paddingKey = "NSStatusItemSelectionPadding"
    /// Parts of macOS that launchd starts again right away when they quit.
    /// Others may be busy, for example recording the screen, so they are
    /// left alone and pick up the spacing when they restart.
    private static let restartingAgents: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.TextInputMenuAgent",
        "com.apple.Spotlight",
    ]

    init(model: AppModel) {
        self.model = model
    }

    /// Values currently stored in the system preferences.
    static func storedSpacing() -> IconSpacing {
        var spacing = IconSpacing()
        spacing.spacing = read(spacingKey)
        spacing.padding = read(paddingKey)
        return spacing
    }

    private static func read(_ key: String) -> Int? {
        let value = CFPreferencesCopyValue(
            key as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return (value as? NSNumber)?.intValue
    }

    private static func write(_ value: Int?, for key: String) {
        CFPreferencesSetValue(
            key as CFString,
            value.map { NSNumber(value: $0) },
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    /// Apps (other than Meno) that show menu bar items and can be
    /// relaunched to pick up the spacing.
    var affectedApps: [NSRunningApplication] {
        let pids = Set(model.inventory.items.filter { $0.kind != .marker }.map(\.pid))
        return pids.compactMap { NSRunningApplication(processIdentifier: $0) }
            .filter { $0.processIdentifier != AppInfo.ownPID && Self.canRelaunch($0) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private static func isRestartingAgent(_ app: NSRunningApplication) -> Bool {
        restartingAgents.contains(app.bundleIdentifier ?? "")
    }

    private static func canRelaunch(_ app: NSRunningApplication) -> Bool {
        if isRestartingAgent(app) { return true }
        if app.bundleIdentifier?.hasPrefix("com.apple.") == true, app.activationPolicy != .regular { return false }
        return app.bundleURL != nil
    }

    func apply(_ spacing: IconSpacing, relaunchApps: Bool) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        Self.write(spacing.spacing, for: Self.spacingKey)
        Self.write(spacing.padding, for: Self.paddingKey)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        model.settings.spacing = spacing
        guard relaunchApps else {
            model.toasts.show(String(localized: "Saved. The new spacing appears as apps restart."), symbol: "arrow.left.and.right")
            return
        }
        for app in affectedApps {
            await relaunch(app)
        }
        model.toasts.show(
            String(localized: "Spacing applied. Relaunch Meno to update its own icons."),
            symbol: "arrow.left.and.right",
            actions: [ToastCenter.Action(title: String(localized: "Relaunch Meno")) { Relauncher.relaunch() }]
        )
    }

    private func relaunch(_ app: NSRunningApplication) async {
        if Self.isRestartingAgent(app) {
            // launchd starts these again.
            _ = kill(app.processIdentifier, SIGTERM)
            return
        }
        guard let url = app.bundleURL else { return }
        guard app.terminate() else { return }
        for _ in 0..<30 where !app.isTerminated {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
