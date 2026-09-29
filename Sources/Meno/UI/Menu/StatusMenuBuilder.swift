import AppKit
import MenoCore

/// Builds the menu shown when the Meno icon is right-clicked.
@MainActor
struct StatusMenuBuilder {
    let model: AppModel

    func build() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let revealed = model.reveal.visibility != .collapsed
        menu.addItem(item(
            revealed ? String(localized: "Hide Items") : String(localized: "Show Hidden Items"),
            symbol: revealed ? "eye.slash" : "eye",
            hotkey: .toggleHidden
        ) {
            model.reveal.toggle(trigger: .menu)
        })
        if model.settings.general.stashEnabled {
            menu.addItem(item(String(localized: "Show Everything"), symbol: "eye.circle", hotkey: .toggleStash) {
                model.reveal.requestReveal(all: true, trigger: .menu)
            })
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quick Open…"), symbol: "magnifyingglass", hotkey: .quickOpen) {
            model.quickOpen.show()
        })
        menu.addItem(item(String(localized: "Open Shelf"), symbol: "rectangle.topthird.inset.filled", hotkey: .toggleShelf) {
            model.shelf.show(includeStash: false, trigger: .menu)
        })
        let zen = item(String(localized: "Zen"), symbol: model.isZenActive ? "leaf.fill" : "leaf", hotkey: .toggleZen) {
            model.setZen(!model.isZenActive)
        }
        zen.state = model.isZenActive ? .on : .off
        menu.addItem(zen)
        if !model.settings.rules.isEmpty {
            let pause = item(String(localized: "Pause Rules"), symbol: "pause.circle") {
                model.settings.rulesPaused.toggle()
            }
            pause.state = model.settings.rulesPaused ? .on : .off
            menu.addItem(pause)
        }
        menu.addItem(scenesItem())
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Arrange Menu Bar…"), symbol: "rectangle.3.group", hotkey: .arrangeMenuBar) {
            model.openSettings(.layout)
        })
        menu.addItem(item(String(localized: "Settings…"), symbol: "gearshape", keyEquivalent: ",") {
            model.openSettings()
        })
        if !model.permissions.accessibility {
            menu.addItem(item(String(localized: "Grant Accessibility Access…"), symbol: "exclamationmark.triangle") {
                model.openSettings(.permissions)
            })
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "About Meno"), symbol: "info.circle") {
            model.openSettings(.about)
        })
        menu.addItem(item(String(localized: "Check for Updates…"), symbol: "arrow.down.circle") {
            Task { await model.updates.check(userInitiated: true) }
        })
        menu.addItem(item(String(localized: "Quit Meno"), symbol: "power", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
        return menu
    }

    private func scenesItem() -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "Scenes"), action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if model.settings.scenes.isEmpty {
            let empty = NSMenuItem(title: String(localized: "No Scenes Yet"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        for scene in model.settings.scenes {
            let entry = item(scene.name, symbol: scene.symbol) {
                Task { await model.applyScene(scene) }
            }
            entry.state = model.activeSceneID == scene.id ? .on : .off
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(item(String(localized: "Manage Scenes…"), symbol: "slider.horizontal.3") {
            model.openSettings(.scenes)
        })
        parent.submenu = submenu
        return parent
    }

    private func item(
        _ title: String,
        symbol: String? = nil,
        hotkey: HotkeyAction? = nil,
        keyEquivalent: String = "",
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let handler = MenuActionHandler(action)
        let item = NSMenuItem(title: title, action: #selector(MenuActionHandler.invoke), keyEquivalent: keyEquivalent)
        item.target = handler
        item.representedObject = handler
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        if let hotkey, let combo = model.settings.hotkeys[hotkey] {
            applyShortcut(combo, to: item)
        }
        return item
    }

    /// Shows a global shortcut next to a menu item.
    private func applyShortcut(_ combo: KeyCombo, to item: NSMenuItem) {
        guard let name = KeyboardLayout.name(for: combo.keyCode), name.count == 1 else { return }
        item.keyEquivalent = name.lowercased()
        var mask: NSEvent.ModifierFlags = []
        if combo.modifiers.contains(.command) { mask.insert(.command) }
        if combo.modifiers.contains(.option) { mask.insert(.option) }
        if combo.modifiers.contains(.control) { mask.insert(.control) }
        if combo.modifiers.contains(.shift) { mask.insert(.shift) }
        item.keyEquivalentModifierMask = mask
    }
}

/// Target for closure-based menu items.
final class MenuActionHandler: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}
