import AppKit
import Combine
import MenoCore
import SwiftUI

/// A Spotlight-style palette to find and open any menu bar item.
@MainActor
final class QuickOpenController: ObservableObject {
    unowned let model: AppModel

    @Published var query = "" {
        didSet { recompute() }
    }
    @Published private(set) var results: [MenuBarItem] = []
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
            }
        } else {
            let scored: [(item: MenuBarItem, score: Int)] = items.compactMap { item in
                guard let score = FuzzyMatcher.bestScore(trimmed, fields: item.searchFields) else { return nil }
                let bonus = min(usage.usage(of: item.key)?.total ?? 0, 20)
                return (item, score + bonus)
            }
            results = scored.sorted { $0.score > $1.score }.map(\.item)
        }
        selection = results.isEmpty ? 0 : min(selection, results.count - 1)
        layoutSoon()
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func activateSelection(secondary: Bool) {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
        hide()
        Task {
            await model.activator.open(item, click: secondary ? .secondary : .primary, source: .quickOpen)
        }
    }

    /// Shows the item's section in the menu bar without opening it.
    func revealSelection() {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
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
        let view = NSHostingView(rootView: QuickOpenView(controller: self, model: model, images: model.images))
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
        let screen = ScreenGeometry.screen(containingCocoa: NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
        let top = screen.frame.maxY - screen.frame.height * 0.2
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }
}
