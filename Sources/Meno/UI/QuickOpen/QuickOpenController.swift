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
        didSet { recompute() }
    }
    @Published private(set) var results: [QuickOpenResult] = []
    @Published var selection = 0
    @Published private(set) var isVisible = false
    /// Bumped whenever the palette opens, so the view can focus its field.
    @Published private(set) var presentation = 0

    private var panel: FloatingPanel?
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
        query = ""
        selection = 0
        recompute()
        let panel = self.panel ?? makePanel()
        isVisible = true
        presentation += 1
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
            await self?.model.inventory.refresh()
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        keyMonitor.stop()
        outsideClickMonitor.stop()
        panel?.orderOut(nil)
    }

    // MARK: - Results

    func recompute() {
        let items = model.inventory.items.filter { $0.kind != .marker }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let usage = model.usage
        if trimmed.isEmpty {
            let order: [ItemSection: Int] = [.hidden: 0, .stash: 1, .visible: 2]
            results = items.sorted { lhs, rhs in
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
        selection = results.isEmpty ? 0 : min(selection, results.count - 1)
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
            QuickCommand(id: "updates", title: String(localized: "Check for Updates"), symbol: "arrow.down.circle") {
                Task { await model.updates.check(userInitiated: true) }
            },
        ]
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

    /// Shows the item's section in the menu bar without opening it.
    func revealSelection() {
        guard results.indices.contains(selection) else { return }
        guard case .item(let item) = results[selection] else {
            activateSelection(secondary: false)
            return
        }
        hide()
        if item.section != .visible {
            model.reveal.reveal(all: item.section == .stash, trigger: .menu)
        }
    }

    /// Handles navigation keys. Returns `true` when the key was used.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isVisible, let panel, panel.isKeyWindow else { return false }
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
            guard flags.contains(.command), let characters = event.charactersIgnoringModifiers,
                  let digit = Int(characters), (1...9).contains(digit), results.count >= digit else {
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
        let view = FirstMouseHostingView(rootView: QuickOpenView(controller: self, model: model, images: model.images))
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

    private func layout() {
        guard isVisible, let panel, let hostingView else { return }
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        guard let screen = ScreenGeometry.screen(containingCocoa: NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let top = screen.frame.maxY - screen.frame.height * 0.2
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }
}
