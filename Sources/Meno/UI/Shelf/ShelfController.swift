import AppKit
import Combine
import MenoCore
import SwiftUI

/// The Shelf: a glass bar below the menu bar that shows hidden items.
/// Useful when items do not fit next to the camera housing, or when the
/// menu bar should never expand.
@MainActor
final class ShelfController: ObservableObject {
    unowned let model: AppModel

    @Published private(set) var isVisible = false
    @Published private(set) var includesStash = false
    /// The group whose items the Shelf shows, or `nil` for hidden items.
    @Published private(set) var groupID: UUID?
    @Published var hoveredKey: MenuItemKey?
    /// The item picked with the arrow keys, when the Shelf was opened with
    /// a hotkey.
    @Published private(set) var keyboardSelection: MenuItemKey?

    private var panel: FloatingPanel?
    private var hideTask: Task<Void, Never>?
    private var hostingView: NSHostingView<ShelfView>?
    private var subscriptions: Set<AnyCancellable> = []
    private lazy var outsideClickMonitor = GlobalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        self?.clickedOutside()
    }
    private lazy var keyMonitor = LocalEventMonitor(mask: [.keyDown]) { [weak self] event in
        self?.handleKey(event) ?? false
    }

    init(model: AppModel) {
        self.model = model
    }

    /// The items in the order the Shelf shows them.
    var shownItems: [MenuBarItem] {
        if let groupID {
            let group = model.settings.groups.first { $0.id == groupID }
            return (group?.items ?? []).compactMap { model.inventory.item(for: $0) }
        }
        let hidden = crowdedItems + model.inventory.items(in: .hidden)
        guard includesStash, model.settings.general.stashEnabled else { return hidden }
        return hidden + model.inventory.items(in: .stash)
    }

    /// Visible items that macOS could not fit into the menu bar. They sit
    /// behind the camera housing or off the screen, where they cannot be
    /// clicked, so the Shelf offers them first.
    var crowdedItems: [MenuBarItem] {
        guard model.inventory.framesAreReliable, !model.isZenActive else { return [] }
        let housings = NSScreen.screens
            .compactMap { ScreenGeometry.notchRect(on: $0) }
            .map { ScreenGeometry.quartzRect(fromCocoa: $0) }
        return model.inventory.items(in: .visible).filter { item in
            guard item.kind != .marker, item.frame.width > 0 else { return false }
            if !item.isOnScreen { return true }
            return housings.contains { housing in
                housing.minY <= item.frame.midY && item.frame.midY <= housing.maxY && item.frame.midX < housing.maxX
            }
        }
    }

    func toggle(trigger: RevealTrigger) {
        if isVisible {
            hide()
        } else {
            show(includeStash: false, trigger: trigger)
        }
    }

    func show(includeStash: Bool, trigger: RevealTrigger) {
        groupID = nil
        present(includeStash: includeStash || model.settings.shelf.includesStash, trigger: trigger)
    }

    /// Shows a group's items below its icon, or hides them again.
    func toggle(group id: UUID) {
        if isVisible, groupID == id {
            hide()
        } else {
            groupID = id
            present(includeStash: false, trigger: .click)
        }
    }

    private func present(includeStash: Bool, trigger: RevealTrigger) {
        hideTask?.cancel()
        hideTask = nil
        includesStash = includeStash
        let panel = self.panel ?? makePanel()
        // Opened from the keyboard, the Shelf takes the arrow keys.
        let usesKeyboard = trigger == .hotkey
        panel.allowsKey = usesKeyboard
        keyboardSelection = usesKeyboard ? shownItems.first?.key : nil
        isVisible = true
        layout()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            self?.layout()
        }
        panel.alphaValue = 0
        if usesKeyboard {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        outsideClickMonitor.start()
        keyMonitor.start()
        model.recordReveal(trigger: trigger)
        Task { [weak self] in
            await self?.model.inventory.refresh()
            self?.model.images.refresh(for: self?.model.inventory.items ?? [], captureAllowed: self?.model.permissions.screenRecording ?? false, force: true)
        }
    }

    /// Hides the Shelf after a while, unless the pointer is on it then.
    func hide(after seconds: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            while let self, self.isVisible, !Task.isCancelled {
                if let panel = self.panel, panel.frame.contains(NSEvent.mouseLocation) {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    continue
                }
                self.hide()
                return
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        guard isVisible else { return }
        isVisible = false
        hoveredKey = nil
        keyboardSelection = nil
        outsideClickMonitor.stop()
        keyMonitor.stop()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if !self.isVisible {
                    panel.orderOut(nil)
                }
            }
        })
    }

    func open(_ item: MenuBarItem, secondary: Bool) {
        if model.settings.shelf.closesAfterAction {
            hide()
        }
        Task {
            await model.activator.open(item, click: secondary ? .secondary : .primary, source: .shelf)
        }
    }

    /// Escape closes the Shelf; while it has the keyboard, the arrow keys
    /// pick an item and Return opens it (⌘Return for its secondary menu).
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        switch event.keyCode {
        case 0x35: // escape
            hide()
        case 0x7B, 0x7C: // left, right
            guard keyboardSelection != nil else { return false }
            moveSelection(by: event.keyCode == 0x7B ? -1 : 1)
        case 0x24, 0x4C: // return, enter
            guard let key = keyboardSelection, let item = model.inventory.item(for: key) else { return false }
            open(item, secondary: event.modifierFlags.contains(.command))
        default:
            return false
        }
        return true
    }

    private func moveSelection(by delta: Int) {
        let items = shownItems
        guard !items.isEmpty else { return }
        let index = keyboardSelection.flatMap { key in items.firstIndex { $0.key == key } } ?? 0
        keyboardSelection = items[(index + delta + items.count) % items.count].key
    }

    private func clickedOutside() {
        guard let panel, isVisible else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) {
            hide()
        }
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(level: .statusBar)
        let view = FirstMouseHostingView(rootView: ShelfView(model: model, shelf: self, inventory: model.inventory, images: model.images))
        panel.contentView = view
        self.panel = panel
        hostingView = view

        model.inventory.$items
            .combineLatest(model.images.$revision)
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.layout()
                }
            }
            .store(in: &subscriptions)
        model.$settings
            .map(\.shelf)
            .removeDuplicates()
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.layout()
                }
            }
            .store(in: &subscriptions)
        return panel
    }

    /// Sizes the panel to its content and places it below the menu bar.
    func layout() {
        guard isVisible, let panel, let hostingView else { return }
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        guard let screen = model.statusBar.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let menuBarBottom = screen.frame.maxY - ScreenGeometry.menuBarHeight(on: screen)
        var x: CGFloat
        if let groupID, let icon = model.statusBar.groupIconFrame(groupID) {
            x = icon.midX - size.width / 2
            x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
            panel.setFrame(NSRect(x: x, y: menuBarBottom - size.height - 6, width: size.width, height: size.height), display: true)
            return
        }
        switch model.settings.shelf.placement {
        case .underIcon:
            if let iconFrame = model.statusBar.toggle?.button?.window?.frame, iconFrame.width < 200 {
                x = iconFrame.maxX - size.width + 10
            } else {
                x = screen.frame.maxX - size.width - 12
            }
        case .center:
            x = screen.frame.midX - size.width / 2
        case .pointer:
            x = NSEvent.mouseLocation.x - size.width / 2
        }
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let frame = NSRect(x: x, y: menuBarBottom - size.height - 6, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }
}
