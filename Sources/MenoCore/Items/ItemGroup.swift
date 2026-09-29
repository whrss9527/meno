import Foundation

/// Items reached from one icon in the menu bar, for example a few tools
/// that are rarely needed but belong together. The items themselves usually
/// live in the Stash, and the group's icon shows them in a Shelf below it.
public struct ItemGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// The SF Symbol of the group's icon.
    public var symbol: String
    /// In the order they are shown.
    public var items: [MenuItemKey]

    public init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2", items: [MenuItemKey] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.items = items
    }

    /// Symbols offered for group icons.
    public static let symbols = [
        "square.grid.2x2", "folder", "tray.full", "shippingbox", "wrench.and.screwdriver",
        "hammer", "paintbrush", "bolt", "cloud", "network", "lock", "star",
        "heart", "leaf", "gamecontroller", "music.note", "bubble.left.and.bubble.right", "chart.bar",
    ]
}

extension Array where Element == ItemGroup {
    /// The group an item belongs to.
    public func group(containing key: MenuItemKey) -> ItemGroup? {
        first { $0.items.contains(key) }
    }

    /// Adds an item to a group. An item belongs to one group at most, so it
    /// leaves any other group.
    public mutating func add(_ key: MenuItemKey, to groupID: UUID) {
        guard let index = firstIndex(where: { $0.id == groupID }) else { return }
        remove(key)
        self[index].items.append(key)
    }

    /// Takes an item out of its group.
    public mutating func remove(_ key: MenuItemKey) {
        for index in indices {
            self[index].items.removeAll { $0 == key }
        }
    }
}
