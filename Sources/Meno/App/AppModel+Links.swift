import AppKit
import MenoCore

extension AppModel {
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
        case .group(let name):
            guard let group = settings.groups.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
                toasts.show(String(localized: "There is no group named “\(name)”."), symbol: "questionmark.circle")
                return
            }
            shelf.toggle(group: group.id)
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
}
