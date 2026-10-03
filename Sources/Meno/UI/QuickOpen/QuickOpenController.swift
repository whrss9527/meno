import AppKit
import Combine
import MenoCore
import SwiftUI

/// A Meno action offered in Quick Open, such as applying a scene.
struct QuickCommand {
    let id: String
    let title: String
    let symbol: String
    let searchFields: [String]
    let run: () -> Void

    init(id: String, title: String, symbol: String, keywords: [String] = [], run: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        var fields = [title] + keywords
        for text in [title] + keywords {
            if let latin = ItemInventory.romanized(text) {
                fields += [latin, FuzzyMatcher.initials(of: latin)]
            }
        }
        self.searchFields = fields
        self.run = run
    }
}

/// One row in Quick Open.
enum QuickOpenResult: Identifiable {
    case item(MenuBarItem)
    case command(QuickCommand)

    var id: String {
        switch self {
        case .item(let item): return "item:" + item.key.rawValue
        case .command(let command): return "command:" + command.id
        }
    }
}

/// A Spotlight-style palette to find and open any menu bar item, and to run
/// Meno's own actions.
@MainActor
final class QuickOpenController: ObservableObject {
    unowned let model: AppModel

    @Published var query = "" {
        // A new search starts at its best match.
        didSet { recompute(keepingSelection: false) }
    }
    @Published private(set) var results: [QuickOpenResult] = []
    @Published var selection = 0
    @Published private(set) var isVisible = false
    /// Bumped whenever the palette opens, so the view can focus its field.
    @Published private(set) var presentation = 0

    /// Where the selected row is in the palette, in SwiftUI's coordinates.
    var selectedRowFrame: CGRect?

    private var panel: FloatingPanel?
    private var shownAt = Date.distantPast
    /// Menus open over the palette, such as a result's actions or its
    /// context menu. They take the keys, and the palette stays meanwhile.
    private var openMenus = 0
    /// The actions menu is up, whether or not macOS reports its tracking.
    private var isPoppingUpActions = false
    private var isShowingActions: Bool { openMenus > 0 || isPoppingUpActions }
    private var hostingView: NSHostingView<QuickOpenView>?
    private var subscriptions: Set<AnyCancellable> = []
    private lazy var keyMonitor = LocalEventMonitor(mask: [.keyDown]) { [weak self] event in
        self?.handleKey(event) ?? false
    }
    private lazy var outsideClickMonitor = GlobalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        self?.hide()
    }

    static let rowHeight: CGFloat = 46
    static let maximumVisibleRows = 8

    init(model: AppModel) {
        self.model = model
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        model.shelf.hide()
        openMenus = 0
        query = ""
        selection = 0
        recompute(keepingSelection: false)
        let panel = self.panel ?? makePanel()
        isVisible = true
        shownAt = Date()
        presentation += 1
        // It stays on the screen it opened on while results change.
        screen = ScreenGeometry.screen(containingCocoa: NSEvent.mouseLocation)
        layoutSoon()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        keyMonitor.start()
        outsideClickMonitor.start()
        Task { [weak self] in
            guard let model = self?.model else { return }
            await model.inventory.refresh()
            model.images.refresh(for: model.inventory.items, captureAllowed: model.permissions.canCapture, renew: true)
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        openMenus = 0
        keyMonitor.stop()
        outsideClickMonitor.stop()
        panel?.orderOut(nil)
    }

    // MARK: - Results

    /// Finds the results again. With `keepingSelection`, the selected row
    /// stays selected where it moved to, for example when the menu bar
    /// changes while the palette is open.
    func recompute(keepingSelection: Bool = true) {
        let selectedID = keepingSelection && results.indices.contains(selection) ? results[selection].id : nil
        let items = model.inventory.items.filter { $0.kind != .marker }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let usage = model.usage
        if trimmed.isEmpty {
            let order: [ItemSection: Int] = [.hidden: 0, .stash: 1, .visible: 2]
            let changed = model.changes.changedItems
            results = items.sorted { lhs, rhs in
                // Items that changed unseen come first.
                let leftChanged = changed.contains(lhs.key)
                if leftChanged != changed.contains(rhs.key) { return leftChanged }
                let left = usage.usage(of: lhs.key)?.total ?? 0
                let right = usage.usage(of: rhs.key)?.total ?? 0
                if left != right { return left > right }
                if lhs.section != rhs.section { return order[lhs.section, default: 3] < order[rhs.section, default: 3] }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }.map(QuickOpenResult.item)
        } else {
            var scored: [(result: QuickOpenResult, score: Int)] = items.compactMap { item in
                guard let score = FuzzyMatcher.bestScore(trimmed, fields: item.searchFields) else { return nil }
                let bonus = min(usage.usage(of: item.key)?.total ?? 0, 20)
                return (QuickOpenResult.item(item), score + bonus)
            }
            // Items come first when they match as well as an action.
            for command in commands() {
                guard let score = FuzzyMatcher.bestScore(trimmed, fields: command.searchFields) else { continue }
                scored.append((QuickOpenResult.command(command), score - 1))
            }
            results = scored.sorted { $0.score > $1.score }.map(\.result)
        }
        if let selectedID, let index = results.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = keepingSelection && !results.isEmpty ? min(selection, results.count - 1) : 0
        }
        layoutSoon()
    }

    /// Meno's actions that can be found by name.
    private func commands() -> [QuickCommand] {
        let model = self.model
        var commands = model.settings.scenes.map { scene in
            QuickCommand(
                id: "scene:" + scene.id.uuidString,
                title: String(localized: "Apply Scene “\(scene.name)”"),
                symbol: scene.symbol,
                keywords: [scene.name]
            ) {
                Task { await model.applyScene(scene) }
            }
        }
        commands += model.settings.groups.map { group in
            QuickCommand(
                id: "group:" + group.id.uuidString,
                title: String(localized: "Show Group “\(group.name)”"),
                symbol: group.symbol,
                keywords: [group.name]
            ) {
                model.shelf.toggle(group: group.id, trigger: .menu, takesKeyboard: true)
            }
        }
        if !model.settings.rules.isEmpty {
            let paused = model.settings.rulesPaused
            commands.append(QuickCommand(
                id: "pause-rules",
                title: paused ? String(localized: "Resume Rules") : String(localized: "Pause Rules"),
                symbol: paused ? "play.circle" : "pause.circle",
                keywords: [String(localized: "Rules")]
            ) {
                model.settings.rulesPaused.toggle()
            })
        }
        commands += [
            QuickCommand(id: "zen", title: model.isZenActive ? String(localized: "Turn Zen Off") : String(localized: "Turn Zen On"), symbol: "leaf", keywords: ["Zen"]) {
                model.setZen(!model.isZenActive)
            },
            QuickCommand(id: "show", title: String(localized: "Show Hidden Items"), symbol: "eye") {
                model.reveal.requestReveal(all: false, trigger: .menu)
            },
            QuickCommand(id: "show-all", title: String(localized: "Show Everything"), symbol: "eye.circle") {
                model.reveal.requestReveal(all: true, trigger: .menu)
            },
            QuickCommand(id: "hide", title: String(localized: "Hide Items"), symbol: "eye.slash") {
                model.shelf.hide()
                model.reveal.collapse(trigger: .menu)
            },
            QuickCommand(id: "shelf", title: String(localized: "Open Shelf"), symbol: "rectangle.topthird.inset.filled") {
                model.shelf.show(includeStash: false, trigger: .menu)
            },
            QuickCommand(id: "layout", title: String(localized: "Arrange Menu Bar…"), symbol: "rectangle.3.group") {
                model.openSettings(.layout)
            },
            QuickCommand(id: "settings", title: String(localized: "Settings…"), symbol: "gearshape") {
                model.openSettings()
            },
        ]
        let updates = model.updates
        if let version = updates.available?.version?.description, updates.canInstall, updates.phase == .idle {
            commands.append(QuickCommand(
                id: "install-update",
                title: String(localized: "Install Meno \(version) and Relaunch"),
                symbol: "arrow.down.circle.fill",
                keywords: [String(localized: "Check for Updates")]
            ) {
                Task { await updates.install() }
            })
        } else {
            commands.append(QuickCommand(id: "updates", title: String(localized: "Check for Updates"), symbol: "arrow.down.circle") {
                Task { await model.updates.check(userInitiated: true) }
            })
        }
        return commands
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func activateSelection(secondary: Bool) {
        guard results.indices.contains(selection) else { return }
        let result = results[selection]
        hide()
        switch result {
        case .item(let item):
            Task {
                await model.activator.open(item, click: secondary ? .secondary : .primary, source: .quickOpen)
            }
        case .command(let command):
            command.run()
        }
    }

    /// What can be done with an item, as its actions menu offers it.
    func actions(for item: MenuBarItem) -> [MoveCommand] {
        let model = self.model
        var commands = [
            MoveCommand(title: String(localized: "Open"), symbol: "cursorarrow.click") { [weak self] in
                self?.hide()
                Task { await model.activator.open(item, click: .primary, source: .quickOpen) }
            },
            MoveCommand(title: String(localized: "Open Secondary Menu"), symbol: "contextualmenu.and.cursorarrow") { [weak self] in
                self?.hide()
                Task { await model.activator.open(item, click: .secondary, source: .quickOpen) }
            },
            MoveCommand(title: String(localized: "Show in Menu Bar"), symbol: "menubar.arrow.down.rectangle") { [weak self] in
                self?.reveal(item)
            },
        ]
        if item.isMovable {
            let sections = ItemSection.allCases.filter { section in
                section != item.section && (section != .stash || model.settings.general.stashEnabled)
            }
            for (index, section) in sections.enumerated() {
                commands.append(MoveCommand(title: section.moveTitle, symbol: section.symbol, startsGroup: index == 0) { [weak self] in
                    self?.hide()
                    model.move(item.key, to: section)
                })
            }
            if item.section != .visible {
                commands.append(MoveCommand(
                    title: String(localized: "Show for a While"),
                    symbol: "timer",
                    children: TemporaryPlacement.durations.map { duration in
                        MoveCommand(title: Formatters.duration(duration), symbol: "clock") { [weak self] in
                            self?.hide()
                            model.temporary.show(item.key, for: duration)
                        }
                    }
                ))
            } else if model.temporary.returnDate(of: item.key) != nil {
                commands.append(MoveCommand(title: String(localized: "Put Back Now"), symbol: "arrow.uturn.backward") { [weak self] in
                    self?.hide()
                    model.temporary.putBack(item.key)
                })
            }
        }
        if item.section != .visible {
            let shows = model.showsOnChange(item.key)
            commands.append(MoveCommand(title: String(localized: "Show When It Changes"), symbol: "bell", isChecked: shows, startsGroup: true) {
                model.setShowsOnChange(item.key, !shows)
            })
        }
        commands.append(MoveCommand(title: String(localized: "Copy Link"), symbol: "link", startsGroup: true) { [weak self] in
            self?.hide()
            model.copyLink(.open(name: item.key.rawValue, secondary: false))
        })
        // Many menu bar apps have no Dock icon to quit them from.
        if item.kind == .app, let app = item.runningApplication {
            if let url = app.bundleURL {
                commands.append(MoveCommand(title: String(localized: "Show in Finder"), symbol: "folder", startsGroup: true) { [weak self] in
                    self?.hide()
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                })
            }
            commands.append(MoveCommand(
                title: String(localized: "Quit \(item.appName)"),
                symbol: "xmark.circle",
                startsGroup: app.bundleURL == nil
            ) { [weak self] in
                self?.hide()
                model.quitApp(of: item)
            })
        }
        return commands
    }

    /// Opens the actions menu of the selected item below its row.
    func showActions() {
        guard !isShowingActions else { return }
        guard results.indices.contains(selection), case .item(let item) = results[selection], let hostingView else {
            // Meno's own actions have nothing more to offer.
            NSSound.beep()
            return
        }
        let menu = MoveCommand.menu(from: actions(for: item))
        let bounds = hostingView.bounds
        let row = selectedRowFrame ?? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        // SwiftUI measures from the top. A row scrolled out of sight still
        // gets its menu on the palette.
        let y = hostingView.isFlipped ? row.maxY : bounds.height - row.maxY
        let glass = bounds.insetBy(dx: 24, dy: 24)
        let point = NSPoint(
            x: min(max(row.minX + row.width * 0.55, glass.minX), glass.maxX),
            y: min(max(y, glass.minY), glass.maxY)
        )
        isPoppingUpActions = true
        menu.popUp(positioning: nil, at: point, in: hostingView)
        isPoppingUpActions = false
        // Another app may have taken the keyboard while the menu was open.
        if isVisible, openMenus == 0, panel?.isKeyWindow != true {
            hide()
        }
    }

    /// Counts the menus open over the palette. Once the last one closes,
    /// the palette goes away if another app took the keyboard meanwhile.
    private func menuTracking(began: Bool) {
        guard isVisible else {
            openMenus = 0
            return
        }
        openMenus = began ? openMenus + 1 : max(openMenus - 1, 0)
        guard !began, openMenus == 0 else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isVisible, !self.isShowingActions, self.panel?.isKeyWindow != true else { return }
            self.hide()
        }
    }

    /// Shows the item's section in the menu bar without opening it.
    func revealSelection() {
        guard results.indices.contains(selection) else { return }
        guard case .item(let item) = results[selection] else {
            activateSelection(secondary: false)
            return
        }
        reveal(item)
    }

    private func reveal(_ item: MenuBarItem) {
        hide()
        if item.section != .visible || model.isZenActive {
            // Zen keeps every section folded.
            if model.isZenActive {
                model.setZen(false)
            }
            model.reveal.reveal(all: item.section == .stash, trigger: .menu)
        }
    }

    /// Handles navigation keys. Returns `true` when the key was used.
    private func handleKey(_ event: NSEvent) -> Bool {
        // The actions menu handles its own keys.
        guard isVisible, !isShowingActions, let panel, panel.isKeyWindow else { return false }
        // While an input method composes text, its keys are its own.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 0x35: // escape
            hide()
        case 0x7D: // down
            moveSelection(by: 1)
        case 0x7E: // up
            moveSelection(by: -1)
        case 0x30: // tab
            moveSelection(by: flags.contains(.shift) ? -1 : 1)
        case 0x24, 0x4C: // return, enter
            if flags.contains(.option) {
                revealSelection()
            } else {
                activateSelection(secondary: flags.contains(.command))
            }
        default:
            guard flags.contains(.command), let characters = event.charactersIgnoringModifiers else { return false }
            // ⌘K, also where the layout types other letters than Latin
            // ones: there, by the key where K is on a US keyboard.
            if characters.lowercased() == "k" || (event.keyCode == 0x28 && !characters.allSatisfy(\.isASCII)) {
                showActions()
                return true
            }
            guard let digit = Int(characters), (1...9).contains(digit), results.count >= digit else {
                return false
            }
            selection = digit - 1
            activateSelection(secondary: false)
        }
        return true
    }

    // MARK: - Panel

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(level: .modalPanel)
        panel.allowsKey = true
        panel.becomesKeyOnlyIfNeeded = false
        let view = FirstMouseHostingView(rootView: QuickOpenView(controller: self, model: model, images: model.images, changes: model.changes))
        panel.contentView = view
        self.panel = panel
        hostingView = view
        model.inventory.$items
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isVisible else { return }
                    self.recompute()
                }
            }
            .store(in: &subscriptions)
        for (name, began) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.menuTracking(began: began)
                    }
                }
                .store(in: &subscriptions)
        }
        // The palette goes away when another app or window takes the
        // keyboard, for example after ⌘-Tab.
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isVisible, !self.isShowingActions,
                          Date().timeIntervalSince(self.shownAt) > 0.3 else { return }
                    self.hide()
                }
            }
            .store(in: &subscriptions)
        return panel
    }

    /// Sizes the panel now and again once SwiftUI has applied pending
    /// changes, since `fittingSize` reflects the last rendered state.
    private func layoutSoon() {
        layout()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            self?.layout()
        }
    }

    /// The screen Quick Open opened on.
    private var screen: NSScreen?

    private func layout() {
        guard isVisible, let panel, let hostingView else { return }
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        guard let screen = self.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let top = screen.frame.maxY - screen.frame.height * 0.2
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }
}
