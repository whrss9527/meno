import AppKit
import Combine
import MenoCore
import SwiftUI
import UniformTypeIdentifiers

/// Owns Meno's state and its controllers.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: MenoSettings {
        didSet { settingsDidChange(from: oldValue) }
    }
    @Published private(set) var usage: UsageLog
    @Published private(set) var isZenActive = false
    @Published private(set) var activeSceneID: UUID?
    @Published private(set) var launchAtLogin: Bool
    /// Meno is registered to launch at login but waits for approval in
    /// System Settings.
    @Published private(set) var launchAtLoginNeedsApproval = false
    /// An item picked elsewhere (for example in the layout editor) to get a
    /// shortcut in the Hotkeys pane.
    @Published var hotkeyDraftItem: MenuItemKey?
    /// Shortcuts macOS did not accept, for example because another app
    /// already uses them.
    @Published private(set) var refusedHotkeys: Set<KeyCombo> = []
    /// The shortcut recorder that is recording, if any.
    @Published var activeShortcutRecorder: UUID?
    /// A `.meno` file whose scenes and rules wait for the person to choose
    /// what to import.
    @Published var pendingShare: PendingShare?
    /// A settings file that waits for the person to confirm that it replaces
    /// the current settings.
    @Published var pendingImport: PendingSettingsImport?
    /// Whether nobody can see the menu bar: the displays sleep or another
    /// user's session is in front. Background scans pause meanwhile.
    private(set) var isAway = false
    /// When Meno started.
    let startedAt = Date()

    let storage: Storage
    let permissions: PermissionCenter
    let images: ItemImageCache
    let hotkeys: HotkeyCenter
    let toasts: ToastCenter

    lazy var statusBar = StatusBarController(model: self)
    lazy var inventory = ItemInventory(model: self)
    lazy var reveal = RevealCoordinator(model: self)
    lazy var activator = ItemActivator(model: self)
    lazy var mover = ItemMover(model: self)
    lazy var shelf = ShelfController(model: self)
    lazy var quickOpen = QuickOpenController(model: self)
    lazy var automation = AutomationController(model: self)
    lazy var changes = ChangeWatcher(model: self)
    lazy var updates = UpdateChecker(model: self)
    lazy var markers = MarkerController(model: self)
    lazy var spacing = SpacingController(model: self)
    lazy var temporary = TemporaryPlacements(model: self)
    lazy var keeper = LayoutKeeper(model: self)
    lazy var tint = TintOverlayController(model: self)
    lazy var settingsWindow = SettingsWindowController(model: self)
    lazy var onboarding = OnboardingController(model: self)

    private var observers: [NSObjectProtocol] = []
    private var periodicTask: Task<Void, Never>?
    private lazy var usageClickMonitor = GlobalEventMonitor(mask: [.leftMouseDown]) { [weak self] _ in
        self?.recordDirectClick()
    }

    init() {
        let storage = Storage()
        self.storage = storage
        settings = storage.loadSettings()
        usage = storage.loadUsage()
        permissions = PermissionCenter()
        images = ItemImageCache()
        hotkeys = HotkeyCenter()
        toasts = ToastCenter()
        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
    }

    // MARK: - Lifecycle

    func start() {
        AX.configureGlobalTimeout(0.6)
        TextEditingShortcuts.install()
        toasts.screenProvider = { [weak self] in
            self?.statusBar.screen
        }
        permissions.onAccessibilityGranted = { [weak self] in
            self?.accessibilityGranted()
        }
        permissions.startMonitoring()
        images.setCustomSymbols(settings.itemSymbols)
        statusBar.install()
        statusBar.syncGroups()
        markers.sync()
        hotkeys.install()
        registerHotkeys()
        reveal.start()
        changes.settingsChanged()
        updates.settingsChanged()
        tint.update()
        observeSystem()
        updateUsageMonitor()
        startPeriodicRefresh()
        Task {
            await inventory.refresh()
            // Rules start once the menu bar is known, so that what they
            // change can be undone.
            automation.start()
            temporary.schedule()
            Diagnostics.event("ready\n" + Diagnostics.report(for: self))
            Diagnostics.printReportsOnSignal(for: self)
        }
        let updated = recordLaunchedVersion()
        // The previous copy stays until this one has run for a few seconds,
        // so that it can be put back if this one quits right away.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let rejected = UpdateInstaller.removeLeftovers() else { return }
            self?.toasts.show(
                String(localized: "Meno \(rejected) did not start on this Mac, so this version was put back."),
                symbol: "exclamationmark.triangle.fill",
                duration: 12
            )
        }
        if !settings.onboardingCompleted {
            onboarding.show()
        } else if !permissions.accessibility {
            // Most often right after an update, when macOS no longer counts
            // the entry of the previous build.
            openSettings(.permissions)
            // A build signed differently than the previous one (every ad hoc
            // signed build, or the first one with a certificate) gets an
            // entry of its own, so the old one is replaced right away and
            // macOS asks again.
            if updated, permissions.needsAccessibilityAgain {
                resetAccessibility()
            }
        }
        usage.prune(keepingDays: 90)
        if updated {
            announceUpdate()
        }
    }

    /// Remembers this version and returns whether it is newer than the one
    /// that ran before.
    private func recordLaunchedVersion() -> Bool {
        let key = "LastLaunchedVersion"
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: key)
        defaults.set(AppInfo.version, forKey: key)
        guard let previous, let old = AppVersion(previous), let new = AppVersion(AppInfo.version) else { return false }
        return old < new
    }

    /// After an update, offers the release notes once.
    private func announceUpdate() {
        let current = AppInfo.version
        let notes = AppInfo.repositoryURL.appendingPathComponent("releases/tag/v\(current)")
        toasts.show(
            String(localized: "Meno was updated to \(current)."),
            symbol: "sparkles",
            actions: [ToastCenter.Action(title: String(localized: "What's New")) { NSWorkspace.shared.open(notes) }],
            duration: 10
        )
    }

    func prepareForTermination() {
        storage.flush(settings: settings, usage: usage)
    }

    private func accessibilityGranted() {
        Task {
            await inventory.refresh()
        }
        reveal.refreshAppMenuFrame(for: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.inventory.scheduleRefresh(after: 1.2)
                }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemLayoutChanged()
            }
        })
        let away = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        let back = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for (names, goesAway) in [(away, true), (back, false)] {
            for name in names {
                observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.setAway(goesAway)
                    }
                })
            }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemLayoutChanged()
            }
        })
    }

    private func systemLayoutChanged() {
        statusBar.reapply()
        tint.screensChanged()
        inventory.scheduleRefresh(after: 0.8)
        automation.evaluate()
    }

    private func setAway(_ away: Bool) {
        guard away != isAway else { return }
        isAway = away
        if !away {
            // Catch up on what changed meanwhile.
            inventory.scheduleRefresh(after: 1)
        }
    }

    private func startPeriodicRefresh() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                // Changes are mostly noticed as they happen; this only catches
                // what slipped through, so Low Power Mode can wait longer.
                let seconds: UInt64 = ProcessInfo.processInfo.isLowPowerModeEnabled ? 60 : 20
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard let self else { return }
                guard !self.isAway else { continue }
                await self.inventory.refresh()
            }
        }
    }

    // MARK: - Settings

    private func settingsDidChange(from old: MenoSettings) {
        storage.saveSettings(settings)
        let new = settings
        if old.general.stashEnabled != new.general.stashEnabled {
            statusBar.syncStashDivider()
            if !new.general.stashEnabled, reveal.visibility == .revealedAll {
                reveal.collapse(trigger: .menu)
            }
            inventory.scheduleRefresh()
        }
        if old.general.hidingEngine != new.general.hidingEngine || old.appearance != new.appearance
            || old.general.showsHiddenCount != new.general.showsHiddenCount || old.zen != new.zen {
            reveal.apply()
        }
        if old.reveal != new.reveal {
            reveal.settingsChanged()
        }
        if old.hotkeys != new.hotkeys || old.itemHotkeys != new.itemHotkeys {
            registerHotkeys()
        }
        if old.markers != new.markers {
            markers.sync()
            inventory.scheduleRefresh()
        }
        if old.tint != new.tint {
            tint.update()
        }
        if old.rules != new.rules || old.scenes != new.scenes || old.rulesPaused != new.rulesPaused {
            automation.rulesChanged()
        }
        if old.general.usageTracking != new.general.usageTracking {
            updateUsageMonitor()
        }
        if old.itemNames != new.itemNames {
            inventory.scheduleRefresh(after: 0)
        }
        if old.itemSymbols != new.itemSymbols {
            images.setCustomSymbols(new.itemSymbols)
        }
        if old.groups != new.groups {
            statusBar.syncGroups()
            if old.groups.map(\.hotkey) != new.groups.map(\.hotkey) {
                registerHotkeys()
            }
        }
        if old.scenes.map(\.hotkey) != new.scenes.map(\.hotkey) {
            registerHotkeys()
        }
        if old.revealOnChange != new.revealOnChange || old.reveal.comparesIcons != new.reveal.comparesIcons {
            changes.settingsChanged()
        }
        if old.general.checksForUpdates != new.general.checksForUpdates {
            updates.settingsChanged()
        }
    }

    /// Reads the login item state again, which can also change in System
    /// Settings.
    func refreshLaunchAtLogin() {
        let enabled = LaunchAtLogin.isEnabled
        let needsApproval = LaunchAtLogin.requiresApproval
        if enabled != launchAtLogin { launchAtLogin = enabled }
        if needsApproval != launchAtLoginNeedsApproval { launchAtLoginNeedsApproval = needsApproval }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if let error = LaunchAtLogin.set(enabled) {
            toasts.show(String(localized: "Could not change the login item: \(error)"), symbol: "exclamationmark.triangle.fill")
        }
        refreshLaunchAtLogin()
        if enabled, LaunchAtLogin.requiresApproval {
            toasts.show(String(localized: "Approve Meno in System Settings › General › Login Items."), symbol: "person.badge.key.fill")
            LaunchAtLogin.openSystemSettings()
        }
    }

    func resetSettings() {
        let onboarding = settings.onboardingCompleted
        var fresh = MenoSettings()
        fresh.onboardingCompleted = onboarding
        settings = fresh
        toasts.show(String(localized: "Settings were reset."), symbol: "arrow.counterclockwise")
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Meno Settings.json"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.encoded().write(to: url, options: .atomic)
            toasts.show(String(localized: "Settings exported."), symbol: "square.and.arrow.up")
        } catch {
            toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Nothing changes until the person has seen what the file holds.
            let file = try SettingsImport(data: Data(contentsOf: url))
            pendingImport = PendingSettingsImport(fileName: url.lastPathComponent, file: file)
        } catch MenoSettings.ImportError.shareFile {
            // Scenes and rules to share: shown before anything is imported.
            openShareFile(url)
        } catch {
            toasts.show(String(localized: "That file does not contain Meno settings."), symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Replaces the settings with the file the person confirmed, after
    /// keeping a copy of the current ones that Undo puts back.
    func confirmImport() {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        let backup: URL
        do {
            backup = try storage.backUp(settings, as: SettingsImport.backupName(at: Date()))
        } catch {
            toasts.show(
                String(localized: "Your current settings could not be kept aside, so nothing was imported."),
                symbol: "exclamationmark.triangle.fill"
            )
            return
        }
        settings = pending.file.settings
        var actions = [ToastCenter.Action(title: String(localized: "Undo")) { [weak self] in self?.undoImport(from: backup) }]
        if pending.file.turnedOffCommands {
            // Commands in a settings file only run once the person has
            // looked at them and turned their rules back on.
            actions.append(ToastCenter.Action(title: String(localized: "Show Rules")) { [weak self] in self?.openSettings(.rules) })
            toasts.show(
                String(localized: "Settings imported. Rules that run commands were turned off; check them before turning them on."),
                symbol: "square.and.arrow.down",
                actions: actions,
                duration: 12
            )
        } else {
            toasts.show(String(localized: "Settings imported."), symbol: "square.and.arrow.down", actions: actions, duration: 10)
        }
    }

    /// Puts back the settings kept before an import.
    func undoImport(from backup: URL) {
        do {
            settings = try MenoSettings.decode(from: Data(contentsOf: backup))
            toasts.show(String(localized: "Your previous settings are back."), symbol: "arrow.uturn.backward")
        } catch {
            toasts.show(
                String(localized: "The copy of your previous settings could not be read. It is in ~/Library/Application Support/Meno."),
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }

    // MARK: - Hotkeys

    func registerHotkeys() {
        hotkeys.unregisterAll()
        var refused: Set<KeyCombo> = []
        func register(_ combo: KeyCombo, _ action: @escaping () -> Void) {
            if !hotkeys.register(combo, action: action) {
                refused.insert(combo)
            }
        }
        for action in HotkeyAction.allCases {
            guard let combo = settings.hotkeys[action] else { continue }
            register(combo) { [weak self] in
                self?.perform(action)
            }
        }
        for binding in settings.itemHotkeys {
            let key = binding.itemKey
            let click = binding.click
            register(binding.combo) { [weak self] in
                self?.openItem(withKey: key, click: click, source: .hotkey)
            }
        }
        for group in settings.groups {
            guard let combo = group.hotkey else { continue }
            let id = group.id
            register(combo) { [weak self] in
                self?.shelf.toggle(group: id, trigger: .hotkey, takesKeyboard: true)
            }
        }
        for scene in settings.scenes {
            guard let combo = scene.hotkey else { continue }
            let id = scene.id
            register(combo) { [weak self] in
                guard let self, let scene = self.settings.scenes.first(where: { $0.id == id }) else { return }
                Task { await self.applyScene(scene) }
            }
        }
        // A shortcut used twice fails the second time; that is reported as
        // a conflict instead.
        refused.subtract(settings.hotkeyConflicts)
        if refused != refusedHotkeys {
            refusedHotkeys = refused
        }
    }

    func perform(_ action: HotkeyAction) {
        switch action {
        case .toggleHidden: reveal.toggle(trigger: .hotkey)
        case .toggleStash: reveal.toggleAll(trigger: .hotkey)
        case .quickOpen: quickOpen.toggle()
        case .toggleShelf: shelf.toggle(trigger: .hotkey)
        case .toggleZen: setZen(!isZenActive)
        case .pauseRules:
            settings.rulesPaused.toggle()
            // Nothing else shows that the shortcut did something.
            toasts.show(
                settings.rulesPaused ? String(localized: "Rules are paused.") : String(localized: "Rules apply again."),
                symbol: settings.rulesPaused ? "pause.circle.fill" : "play.circle.fill"
            )
        case .arrangeMenuBar: openSettings(.layout)
        case .openSettings: openSettings()
        }
    }

    // MARK: - Zen

    func setZen(_ enabled: Bool, announce: Bool = true) {
        guard enabled != isZenActive else { return }
        isZenActive = enabled
        if enabled {
            shelf.hide()
            reveal.collapse(trigger: .zen)
        } else {
            reveal.apply()
        }
        if announce {
            toasts.show(
                enabled ? String(localized: "Zen is on. Only system items remain.") : String(localized: "Zen is off."),
                symbol: enabled ? "leaf.fill" : "leaf"
            )
        }
    }

    // MARK: - Items

    func openItem(withKey key: MenuItemKey, click: ClickKind, source: UsageSource) {
        Task {
            if inventory.item(for: key) == nil {
                await inventory.refresh()
            }
            guard let item = inventory.item(for: key) else {
                toasts.show(String(localized: "That item is not in the menu bar right now."), symbol: "questionmark.circle")
                return
            }
            await activator.open(item, click: click, source: source)
        }
    }

    /// Moves an item into a section, reporting problems as a toast.
    /// Automatic moves wait until the mouse and keyboard are idle.
    func move(_ key: MenuItemKey, to section: ItemSection, automatic: Bool = false) {
        Task {
            do {
                try await mover.move(key, to: section, automatic: automatic)
            } catch {
                toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Undoes the last change made through Meno, reporting problems as a toast.
    func undoLayoutChange() {
        Task {
            do {
                try await mover.undo()
            } catch {
                toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Moves an item next to another one, reporting problems as a toast.
    func move(_ key: MenuItemKey, placement: Placement) {
        Task {
            do {
                try await mover.move(key, placement: placement)
            } catch {
                toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Quits the app that shows an item, and offers to force it when it is
    /// still running a few seconds later.
    func quitApp(of item: MenuBarItem) {
        guard item.kind == .app, let app = item.runningApplication, !app.isTerminated else { return }
        let name = item.appName
        app.terminate()
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !app.isTerminated else { return }
            toasts.show(
                String(localized: "\(name) did not quit."),
                symbol: "exclamationmark.triangle.fill",
                actions: [ToastCenter.Action(title: String(localized: "Force Quit")) { app.forceTerminate() }]
            )
        }
    }

    /// Gives an item a name in Meno, or goes back to the name macOS reports
    /// when `name` is empty or `nil`.
    func rename(_ key: MenuItemKey, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        settings.itemNames[key.rawValue] = trimmed.isEmpty ? nil : trimmed
    }

    /// Picks a symbol to stand for an item in Meno, or goes back to its own
    /// artwork with `nil`.
    func setSymbol(_ symbol: String?, for key: MenuItemKey) {
        settings.itemSymbols[key.rawValue] = symbol
    }

    /// Whether a hidden item is shown for a moment when it changes.
    func showsOnChange(_ key: MenuItemKey) -> Bool {
        settings.revealOnChange.contains(key.rawValue)
    }

    func setShowsOnChange(_ key: MenuItemKey, _ enabled: Bool) {
        var keys = Set(settings.revealOnChange)
        if enabled {
            keys.insert(key.rawValue)
        } else {
            keys.remove(key.rawValue)
        }
        settings.revealOnChange = keys.sorted()
    }

    func handleNewArrival(_ item: MenuBarItem) {
        switch settings.general.newItemPolicy {
        case .ignore:
            return
        case .notify:
            var actions = [ToastCenter.Action(title: String(localized: "Hide")) { [weak self] in
                self?.move(item.key, to: .hidden)
            }]
            if settings.general.stashEnabled {
                actions.append(ToastCenter.Action(title: String(localized: "Stash")) { [weak self] in
                    self?.move(item.key, to: .stash)
                })
            }
            toasts.show(String(localized: "New in the menu bar: \(item.displayName)"), symbol: "sparkles", actions: actions)
        case .hide:
            if item.section == .visible {
                move(item.key, to: .hidden, automatic: true)
            }
        case .stash:
            if item.section != .stash, settings.general.stashEnabled {
                move(item.key, to: .stash, automatic: true)
            }
        }
    }

    /// Shows or hides the Meno icon. Without it, clicking an empty part of
    /// the menu bar reveals items unless another way is set up.
    func setShowsMenoIcon(_ shows: Bool) {
        settings.appearance.showsMenoIcon = shows
        guard !shows, !settings.canRevealWithoutIcon else { return }
        settings.reveal.onEmptyAreaClick = true
        toasts.show(String(localized: "Click an empty part of the menu bar to show hidden items."), symbol: "cursorarrow.click")
    }

    // MARK: - Scenes

    @discardableResult
    func saveScene(named name: String, symbol: String) -> LayoutScene {
        let scene = LayoutScene(name: name, symbol: symbol, layout: inventory.currentLayout())
        settings.scenes.append(scene)
        activeSceneID = scene.id
        toasts.show(String(localized: "Saved scene “\(name)”."), symbol: symbol)
        return scene
    }

    func updateScene(id: UUID) {
        guard let index = settings.scenes.firstIndex(where: { $0.id == id }) else { return }
        settings.scenes[index].layout = inventory.currentLayout()
        settings.scenes[index].updatedAt = Date()
        toasts.show(String(localized: "Updated “\(settings.scenes[index].name)”."), symbol: "arrow.triangle.2.circlepath")
    }

    /// The menu bar no longer looks like the scene applied last, after
    /// items were moved some other way.
    func forgetActiveScene() {
        activeSceneID = nil
    }

    func deleteScene(id: UUID) {
        settings.scenes.removeAll { $0.id == id }
        if activeSceneID == id { activeSceneID = nil }
    }

    /// Applies `scene` whenever the menu bar of `display` has the items, or
    /// stops doing so with `nil`. It is kept as a rule.
    func setDisplayScene(_ scene: UUID?, for display: String) {
        let sceneName = scene.flatMap { id in settings.scenes.first { $0.id == id }?.name } ?? ""
        settings.rules = settings.rules.settingDisplayScene(
            scene,
            for: display,
            name: String(localized: "“\(sceneName)” on \(display)")
        )
    }

    @discardableResult
    func applyScene(
        _ scene: LayoutScene,
        announce: Bool = true,
        automatic: Bool = false,
        proceeds: (() -> Bool)? = nil
    ) async -> Bool {
        do {
            try await mover.apply(scene.layout, automatic: automatic, proceeds: proceeds)
            activeSceneID = scene.id
            if announce {
                toasts.show(String(localized: "Scene “\(scene.name)” applied."), symbol: scene.symbol)
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            return false
        }
    }

    // MARK: - Usage

    func recordItemUse(_ item: MenuBarItem, source: UsageSource) {
        guard settings.general.usageTracking else { return }
        usage.recordItemUse(item.key, section: item.section, source: source, at: Date())
        storage.saveUsage(usage)
    }

    func recordReveal(trigger: RevealTrigger) {
        guard settings.general.usageTracking else { return }
        usage.recordReveal(trigger: trigger.rawValue, at: Date())
        storage.saveUsage(usage)
    }

    func resetUsage() {
        usage = UsageLog()
        storage.saveUsage(usage, immediately: true)
    }

    /// Turns a suggestion in Insights down for a while.
    func dismissSuggestion(_ suggestion: UsageSuggestion) {
        usage.dismiss(suggestion)
        storage.saveUsage(usage)
    }

    private func updateUsageMonitor() {
        if settings.general.usageTracking {
            usageClickMonitor.start()
        } else {
            usageClickMonitor.stop()
        }
    }

    /// Counts clicks on items directly in the menu bar.
    private func recordDirectClick() {
        // Meno's own drags and clicks are not uses of the items.
        guard !mover.isMoving, !activator.clickedRecently else { return }
        let location = NSEvent.mouseLocation
        guard ScreenGeometry.isInMenuBar(cocoa: location) else { return }
        let point = ScreenGeometry.quartzPoint(fromCocoa: location)
        guard let item = inventory.items.first(where: { $0.kind != .marker && $0.frame.contains(point) }) else { return }
        recordItemUse(item, source: .menuBar)
    }

    // MARK: - Windows and menus

    func openSettings(_ pane: SettingsPane? = nil) {
        settingsWindow.show(pane: pane)
    }

    var hasVisibleWindows: Bool {
        settingsWindow.isVisible || onboarding.isVisible
    }

    /// Whether a window that shows the artwork of items is open.
    var showsItemArtwork: Bool {
        shelf.isVisible || quickOpen.isVisible || settingsWindow.isVisible
    }

    func makeStatusMenu() -> NSMenu {
        // Permissions are checked only every few seconds once granted.
        permissions.refresh()
        return StatusMenuBuilder(model: self).build()
    }

    /// Replaces Meno's Accessibility entry with one for this build.
    func resetAccessibility() {
        Task {
            if !(await permissions.resetAccessibility()) {
                toasts.show(
                    String(localized: "Could not reset the entry. Remove Meno from the Accessibility list in System Settings, then add it again."),
                    symbol: "exclamationmark.triangle.fill"
                )
            }
        }
    }

    func completeOnboarding() {
        settings.onboardingCompleted = true
    }
}
