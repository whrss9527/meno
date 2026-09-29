import Foundation

/// A saved arrangement of the menu bar that can be applied later, for
/// example "Work", "Home" or "Presenting".
public struct LayoutScene: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// An SF Symbol shown next to the name.
    public var symbol: String
    public var layout: SceneLayout
    public var createdAt: Date
    public var updatedAt: Date
    /// A global shortcut that applies the scene.
    public var hotkey: KeyCombo?

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "square.grid.2x2",
        layout: SceneLayout,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        hotkey: KeyCombo? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.layout = layout
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.hotkey = hotkey
    }
}

/// Items per section, each list in left-to-right menu bar order.
public struct SceneLayout: Codable, Hashable, Sendable {
    public var visible: [MenuItemKey]
    public var hidden: [MenuItemKey]
    public var stash: [MenuItemKey]

    public init(visible: [MenuItemKey] = [], hidden: [MenuItemKey] = [], stash: [MenuItemKey] = []) {
        self.visible = visible
        self.hidden = hidden
        self.stash = stash
    }

    public subscript(section: ItemSection) -> [MenuItemKey] {
        get {
            switch section {
            case .visible: return visible
            case .hidden: return hidden
            case .stash: return stash
            }
        }
        set {
            switch section {
            case .visible: visible = newValue
            case .hidden: hidden = newValue
            case .stash: stash = newValue
            }
        }
    }

    public func section(of key: MenuItemKey) -> ItemSection? {
        if visible.contains(key) { return .visible }
        if hidden.contains(key) { return .hidden }
        if stash.contains(key) { return .stash }
        return nil
    }

    public var itemCount: Int { visible.count + hidden.count + stash.count }

    /// All keys in left-to-right order: stash, hidden, then visible.
    public var leftToRight: [MenuItemKey] { stash + hidden + visible }
}
