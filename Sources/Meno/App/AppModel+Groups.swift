import Foundation
import MenoCore

extension AppModel {
    /// Creates a group, with a first item if given.
    @discardableResult
    func createGroup(named name: String, with key: MenuItemKey? = nil) -> ItemGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = ItemGroup(name: trimmed.isEmpty ? String(localized: "Group") : trimmed)
        settings.groups.append(group)
        if let key {
            addItem(key, toGroup: group.id)
        }
        return group
    }

    /// Puts an item in a group. A visible item also leaves the menu bar for
    /// the Stash (or Hidden without a Stash), since the group's icon shows it.
    func addItem(_ key: MenuItemKey, toGroup id: UUID) {
        settings.groups.add(key, to: id)
        let target: ItemSection = settings.general.stashEnabled ? .stash : .hidden
        if let item = inventory.item(for: key), item.section == .visible, item.isMovable {
            move(key, to: target)
        }
    }

    func removeItemFromGroups(_ key: MenuItemKey) {
        settings.groups.remove(key)
    }

    func deleteGroup(_ id: UUID) {
        settings.groups.removeAll { $0.id == id }
        if shelf.groupID == id {
            shelf.hide()
        }
    }
}
