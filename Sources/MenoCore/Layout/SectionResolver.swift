import Foundation

/// The horizontal extent of an item in global screen coordinates, where x
/// grows to the right.
public struct HorizontalSpan: Hashable, Sendable {
    public var minX: Double
    public var maxX: Double

    public init(minX: Double, maxX: Double) {
        self.minX = min(minX, maxX)
        self.maxX = max(minX, maxX)
    }

    public init(x: Double, width: Double) {
        self.init(minX: x, maxX: x + width)
    }

    public var midX: Double { (minX + maxX) / 2 }
    public var width: Double { maxX - minX }

    public func contains(_ x: Double) -> Bool { x >= minX && x <= maxX }
}

/// Positions of Meno's own dividers.
public struct DividerLayout: Hashable, Sendable {
    /// Items left of this divider are hidden.
    public var hidden: HorizontalSpan
    /// Items left of this divider are stashed.
    public var stash: HorizontalSpan?

    public init(hidden: HorizontalSpan, stash: HorizontalSpan? = nil) {
        self.hidden = hidden
        self.stash = stash
    }

    /// The Stash divider has to sit left of the Hidden divider.
    public var isConsistent: Bool {
        guard let stash else { return true }
        return stash.midX < hidden.midX
    }
}

/// Assigns items to sections based on their position relative to the
/// dividers. Positions only need to be ordered correctly, so this also works
/// while the dividers are expanded and items are pushed off screen.
public enum SectionResolver {
    public static func section(of item: HorizontalSpan, dividers: DividerLayout) -> ItemSection {
        if item.midX >= dividers.hidden.midX {
            return .visible
        }
        if let stash = dividers.stash, dividers.isConsistent, item.midX < stash.midX {
            return .stash
        }
        return .hidden
    }

    /// Resolves sections for many items at once.
    public static func sections<Key: Hashable>(
        of items: [Key: HorizontalSpan],
        dividers: DividerLayout
    ) -> [Key: ItemSection] {
        items.mapValues { section(of: $0, dividers: dividers) }
    }
}
