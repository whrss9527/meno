import Foundation

/// An element of the menu bar order used for planning moves.
public enum LayoutToken: Hashable, Sendable, CustomStringConvertible {
    /// An item that can be moved.
    case item(MenuItemKey)
    /// Something that stays in place: Meno's dividers or system items that
    /// macOS does not allow to move.
    case anchor(String)

    public var description: String {
        switch self {
        case .item(let key): return key.rawValue
        case .anchor(let name): return "<\(name)>"
        }
    }

    public var itemKey: MenuItemKey? {
        if case .item(let key) = self { return key }
        return nil
    }
}

/// Where an item should be dropped relative to another token.
public enum Placement: Hashable, Sendable {
    case rightOf(LayoutToken)
    case leftOf(LayoutToken)

    public var reference: LayoutToken {
        switch self {
        case .rightOf(let token), .leftOf(let token): return token
        }
    }
}

/// A single ⌘-drag.
public struct MoveStep: Hashable, Sendable {
    public var item: MenuItemKey
    public var placement: Placement

    public init(item: MenuItemKey, placement: Placement) {
        self.item = item
        self.placement = placement
    }
}

/// Plans the smallest set of moves that turns one menu bar order into another.
public enum LayoutPlanner {
    public enum PlanError: Error, Equatable {
        /// Two anchors are in a different relative order in the target, which
        /// cannot be fixed because anchors never move.
        case anchorsOutOfOrder
    }

    public static let hiddenDivider = LayoutToken.anchor("divider.hidden")
    public static let stashDivider = LayoutToken.anchor("divider.stash")

    /// Computes the moves that bring the tokens of `target` into the target's
    /// relative order.
    ///
    /// Tokens of `target` that are not in `current` are ignored, and tokens of
    /// `current` that are not in `target` are left alone. Items that already
    /// form the longest correctly ordered run stay put, so the number of moves
    /// is minimal.
    ///
    /// - Parameters:
    ///   - current: Tokens in their current left-to-right order.
    ///   - target: Tokens in the desired left-to-right order.
    public static func plan(current: [LayoutToken], target: [LayoutToken]) throws -> [MoveStep] {
        var currentIndex: [LayoutToken: Int] = [:]
        for (index, token) in current.enumerated() where currentIndex[token] == nil {
            currentIndex[token] = index
        }
        var seen = Set<LayoutToken>()
        let tokens = target.filter { currentIndex[$0] != nil && seen.insert($0).inserted }
        let count = tokens.count
        guard count > 1 else { return [] }

        // Heaviest increasing subsequence of current positions, where anchors
        // outweigh any number of items so that they are always kept.
        let positions = tokens.map { currentIndex[$0]! }
        let weights = tokens.map { token -> Int in
            if case .anchor = token { return 1_000_000 }
            return 1
        }
        var best = weights
        var previous = [Int](repeating: -1, count: count)
        for i in 0..<count {
            for j in 0..<i where positions[j] < positions[i] && best[j] + weights[i] > best[i] {
                best[i] = best[j] + weights[i]
                previous[i] = j
            }
        }
        var end = 0
        for i in 1..<count where best[i] > best[end] {
            end = i
        }
        var kept = Set<Int>()
        var cursor = end
        while cursor >= 0 {
            kept.insert(cursor)
            cursor = previous[cursor]
        }
        for (index, token) in tokens.enumerated() {
            if case .anchor = token, !kept.contains(index) {
                throw PlanError.anchorsOutOfOrder
            }
        }

        var steps: [MoveStep] = []
        for index in 0..<count where !kept.contains(index) {
            guard case .item(let key) = tokens[index] else { continue }
            if index > 0 {
                steps.append(MoveStep(item: key, placement: .rightOf(tokens[index - 1])))
            } else if let next = (1..<count).first(where: { kept.contains($0) }) {
                steps.append(MoveStep(item: key, placement: .leftOf(tokens[next])))
            }
        }
        return steps
    }

    /// Applies moves to an order, the way the menu bar would.
    public static func apply(_ steps: [MoveStep], to order: [LayoutToken]) -> [LayoutToken] {
        var result = order
        for step in steps {
            let token = LayoutToken.item(step.item)
            guard let from = result.firstIndex(of: token) else { continue }
            result.remove(at: from)
            guard let referenceIndex = result.firstIndex(of: step.placement.reference) else {
                result.insert(token, at: min(from, result.count))
                continue
            }
            switch step.placement {
            case .rightOf: result.insert(token, at: referenceIndex + 1)
            case .leftOf: result.insert(token, at: referenceIndex)
            }
        }
        return result
    }

    /// The target order for a scene: stash items, the Stash divider, hidden
    /// items, the Hidden divider and finally the visible items.
    public static func targetOrder(for layout: SceneLayout, includesStash: Bool) -> [LayoutToken] {
        var order: [LayoutToken] = []
        if includesStash {
            order += layout.stash.map(LayoutToken.item)
            order.append(stashDivider)
            order += layout.hidden.map(LayoutToken.item)
        } else {
            order += (layout.stash + layout.hidden).map(LayoutToken.item)
        }
        order.append(hiddenDivider)
        order += layout.visible.map(LayoutToken.item)
        return order
    }

    /// The section an item in `section` really ends up in: without a Stash,
    /// its items are hidden.
    public static func effectiveSection(_ section: ItemSection, includesStash: Bool) -> ItemSection {
        section == .stash && !includesStash ? .hidden : section
    }

    /// Where to drop an item that is in `current` so that it ends up in
    /// `section`, or `nil` when it is already there.
    ///
    /// Items are placed right next to the divider they have to cross, which
    /// keeps the drag distance short.
    public static func placement(moving current: ItemSection, to section: ItemSection, includesStash: Bool) -> Placement? {
        let from = effectiveSection(current, includesStash: includesStash)
        let to = effectiveSection(section, includesStash: includesStash)
        guard from != to else { return nil }
        switch to {
        case .visible:
            return .rightOf(hiddenDivider)
        case .hidden:
            return from == .stash ? .rightOf(stashDivider) : .leftOf(hiddenDivider)
        case .stash:
            return .leftOf(stashDivider)
        }
    }

    /// Whether a step already holds in `order`: its item is right next to its
    /// reference, on the requested side.
    ///
    /// Only tokens in `counted` may not lie in between; others (items a
    /// scene does not know, for example) are ignored. With `nil`, every token
    /// counts.
    public static func isSatisfied(_ step: MoveStep, in order: [LayoutToken], counting counted: Set<LayoutToken>? = nil) -> Bool {
        let relevant = order.filter { token in
            token == .item(step.item) || token == step.placement.reference || counted?.contains(token) ?? true
        }
        guard let itemIndex = relevant.firstIndex(of: .item(step.item)),
              let referenceIndex = relevant.firstIndex(of: step.placement.reference) else { return false }
        switch step.placement {
        case .rightOf: return itemIndex == referenceIndex + 1
        case .leftOf: return itemIndex == referenceIndex - 1
        }
    }
}
