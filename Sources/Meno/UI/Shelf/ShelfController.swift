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
    @Published var hoveredKey: MenuItemKey?

    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<ShelfView>?
    private var subscriptions: Set<AnyCancellable> = []
    private lazy var outsideClickMonitor = GlobalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        self?.clickedOutside()
    }
    private lazy var keyMonitor = LocalEventMonitor(mask: [.keyDown]) { [weak self] event in
        guard let self, self.isVisible, event.keyCode == 0x35 else { return false }
        self.hide()
        return true
    }

    init(model: AppModel) {
        self.model = model
    }

    var items: [MenuBarItem] {
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
        includesStash = includeStash || model.settings.shelf.includesStash
        let panel = self.panel ?? makePanel()
        isVisible = true
        layout()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            self?.layout()
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
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

    func hide() {
        guard isVisible else { return }
        isVisible = false
        hoveredKey = nil
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
