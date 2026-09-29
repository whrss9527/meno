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
    }

    // MARK: - Lifecycle

    func start() {
        AX.configureGlobalTimeout(0.6)
        toasts.screenProvider = { [weak self] in
            self?.statusBar.screen
        }
        permissions.onAccessibilityGranted = { [weak self] in
            self?.accessibilityGranted()
        }
        permissions.startMonitoring()
        statusBar.install()
        markers.sync()
        hotkeys.install()
        registerHotkeys()
        reveal.start()
        automation.start()
        changes.settingsChanged()
        updates.settingsChanged()
        tint.update()
        observeSystem()
        updateUsageMonitor()
        startPeriodicRefresh()
        Task {
            await inventory.refresh()
        }
        if !settings.onboardingCompleted {
            onboarding.show()
        } else if !permissions.accessibility {
            // Most often right after an update, when macOS no longer counts
            // the entry of the previous build.
            openSettings(.permissions)
        }
        usage.prune(keepingDays: 90)
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
        tint.update()
        inventory.scheduleRefresh(after: 0.8)
        automation.evaluate()
    }

    private func startPeriodicRefresh() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self else { return }
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
        if old.rules != new.rules || old.scenes != new.scenes {
            automation.rulesChanged()
        }
        if old.general.usageTracking != new.general.usageTracking {
            updateUsageMonitor()
        }
        if old.itemNames != new.itemNames {
            inventory.scheduleRefresh(after: 0)
        }
        if old.revealOnChange != new.revealOnChange {
            changes.settingsChanged()
        }
        if old.general.checksForUpdates != new.general.checksForUpdates {
            updates.settingsChanged()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if let error = LaunchAtLogin.set(enabled) {
            toasts.show(String(localized: "Could not change the login item: \(error)"), symbol: "exclamationmark.triangle.fill")
        }
        launchAtLogin = LaunchAtLogin.isEnabled
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
            var imported = try MenoSettings.decode(from: Data(contentsOf: url))
            imported.onboardingCompleted = true
            settings = imported
            toasts.show(String(localized: "Settings imported."), symbol: "square.and.arrow.down")
        } catch {
            toasts.show(String(localized: "That file does not contain Meno settings."), symbol: "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Hotkeys

    func registerHotkeys() {
        hotkeys.unregisterAll()
        for action in HotkeyAction.allCases {
            guard let combo = settings.hotkeys[action] else { continue }
            hotkeys.register(combo) { [weak self] in
                self?.perform(action)
            }
        }
        for binding in settings.itemHotkeys {
            let key = binding.itemKey
            let click = binding.click
            hotkeys.register(binding.combo) { [weak self] in
                self?.openItem(withKey: key, click: click, source: .hotkey)
            }
        }
    }

    func perform(_ action: HotkeyAction) {
        switch action {
        case .toggleHidden: reveal.toggle(trigger: .hotkey)
        case .toggleStash: reveal.toggleAll(trigger: .hotkey)
        case .quickOpen: quickOpen.toggle()
        case .toggleShelf: shelf.toggle(trigger: .hotkey)
        case .toggleZen: setZen(!isZenActive)
        case .openSettings: openSettings()
        }
    }

    // MARK: - Links

    /// Runs a `meno://` link, for example from Shortcuts or a launcher.
    func handle(_ url: URL) {
        guard let command = LinkCommand(url: url) else {
            toasts.show(String(localized: "Meno does not know the link \(url.absoluteString)."), symbol: "link")
            return
        }
        switch command {
        case .show(let all):
            reveal.requestReveal(all: all, trigger: .link)
        case .hide:
            shelf.hide()
            reveal.collapse(trigger: .link)
        case .toggle(let all):
            if all {
                reveal.toggleAll(trigger: .link)
            } else {
                reveal.toggle(trigger: .link)
            }
        case .zen(let enabled):
            setZen(enabled ?? !isZenActive)
        case .scene(let name):
            guard let scene = settings.scenes.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
                toasts.show(String(localized: "There is no scene named “\(name)”."), symbol: "questionmark.circle")
                return
            }
            Task { await applyScene(scene) }
        case .open(let name, let secondary):
            Task {
                if item(matching: name) == nil {
                    await inventory.refresh()
                }
                guard let item = item(matching: name) else {
                    toasts.show(String(localized: "“\(name)” is not in the menu bar right now."), symbol: "questionmark.circle")
                    return
                }
                await activator.open(item, click: secondary ? .secondary : .primary, source: .rule)
            }
        case .quickOpen:
            quickOpen.show()
        case .shelf:
            shelf.toggle(trigger: .link)
        case .settings(let pane):
            openSettings(pane.flatMap(SettingsPane.init(rawValue:)))
        }
    }

    /// An item by its key, its exact name, or the best fuzzy match.
    private func item(matching query: String) -> MenuBarItem? {
        if let key = MenuItemKey(rawValue: query), let item = inventory.item(for: key) {
            return item
        }
        let items = inventory.items.filter { $0.kind != .marker }
        if let exact = items.first(where: { $0.displayName.localizedCaseInsensitiveCompare(query) == .orderedSame }) {
            return exact
        }
        return items
            .compactMap { item in FuzzyMatcher.bestScore(query, fields: item.searchFields).map { (item, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Puts the link for a command on the clipboard.
    func copyLink(_ command: LinkCommand) {
        guard let link = command.url?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        toasts.show(String(localized: "Copied \(link)"), symbol: "link")
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

    /// Gives an item a name in Meno, or goes back to the name macOS reports
    /// when `name` is empty or `nil`.
    func rename(_ key: MenuItemKey, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        settings.itemNames[key.rawValue] = trimmed.isEmpty ? nil : trimmed
    }

    /// Shows or hides the Meno icon. Without it, clicking an empty part of
    /// the menu bar reveals items unless another way is set up.
    func setShowsMenoIcon(_ shows: Bool) {
        settings.appearance.showsMenoIcon = shows
        guard !shows, !settings.canRevealWithoutIcon else { return }
        settings.reveal.onEmptyAreaClick = true
        toasts.show(String(localized: "Click an empty part of the menu bar to show hidden items."), symbol: "cursorarrow.click")
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

    func deleteScene(id: UUID) {
        settings.scenes.removeAll { $0.id == id }
        if activeSceneID == id { activeSceneID = nil }
    }

    @discardableResult
    func applyScene(_ scene: LayoutScene, announce: Bool = true, automatic: Bool = false) async -> Bool {
        do {
            try await mover.apply(scene.layout, automatic: automatic)
            activeSceneID = scene.id
            if announce {
                toasts.show(String(localized: "Scene “\(scene.name)” applied."), symbol: scene.symbol)
            }
            return true
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

    private func updateUsageMonitor() {
        if settings.general.usageTracking {
            usageClickMonitor.start()
        } else {
            usageClickMonitor.stop()
        }
    }

    /// Counts clicks on items directly in the menu bar.
    private func recordDirectClick() {
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

    func makeStatusMenu() -> NSMenu {
        StatusMenuBuilder(model: self).build()
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
