import Foundation

public enum SectionVisibility: Equatable, Sendable {
    case collapsed
    case revealed
    case revealedAll
}

/// State shared by rules, item activation and nested layout sessions.
/// The coordinator performs system effects after these pure transitions.
public struct RevealState: Equatable, Sendable {
    public private(set) var visibility: SectionVisibility
    public private(set) var holds = 0
    public private(set) var zenLifts = 0
    public private(set) var layoutSessions = 0
    public private(set) var activations = 0
    private var visibilityBeforeLayout: SectionVisibility = .collapsed
    private var visibilityBeforeActivation: SectionVisibility?

    public init(visibility: SectionVisibility = .collapsed) { self.visibility = visibility }

    public mutating func reveal(all: Bool) {
        visibility = all || visibility == .revealedAll ? .revealedAll : .revealed
    }

    /// A collapse requested during a move is applied once the last session ends.
    @discardableResult
    public mutating func collapse() -> Bool {
        if layoutSessions > 0 {
            visibilityBeforeLayout = .collapsed
            return false
        }
        visibility = .collapsed
        return true
    }

    public mutating func hold() { holds += 1 }
    public mutating func release() { holds = max(holds - 1, 0) }

    public mutating func beginActivation() {
        if activations == 0 { visibilityBeforeActivation = visibility }
        activations += 1
        hold()
        zenLifts += 1
    }

    /// The final activation's previous visibility, when no other hold remains.
    public mutating func endActivation() -> SectionVisibility? {
        guard activations > 0 else { return nil }
        activations -= 1
        zenLifts = max(zenLifts - 1, 0)
        release()
        guard activations == 0 else { return nil }
        let restore = visibilityBeforeActivation
        visibilityBeforeActivation = nil
        return holds == 0 ? restore : nil
    }

    /// Only the outermost session owns a hold and a Zen lift.
    public mutating func beginLayoutSession() -> Bool {
        layoutSessions += 1
        guard layoutSessions == 1 else { return false }
        visibilityBeforeLayout = visibility
        hold()
        zenLifts += 1
        return true
    }

    public enum LayoutEnd: Equatable, Sendable {
        case held
        case restore(SectionVisibility)
    }

    /// Nil means a nested or unmatched end, with no system effects to perform.
    public mutating func endLayoutSession() -> LayoutEnd? {
        guard layoutSessions > 0 else { return nil }
        layoutSessions -= 1
        guard layoutSessions == 0 else { return nil }
        zenLifts = max(zenLifts - 1, 0)
        release()
        if holds > 0 {
            if activations > 0, visibilityBeforeLayout == .collapsed { visibilityBeforeActivation = .collapsed }
            if activations == 0, visibilityBeforeLayout == .revealed { visibility = .revealed }
            return .held
        }
        if visibilityBeforeLayout == .revealed { visibility = .revealed }
        return .restore(visibilityBeforeLayout)
    }

    public func barState(zenActive: Bool) -> BarState {
        let zen = zenActive && zenLifts == 0
        return BarState(hiddenCollapsed: zen || visibility == .collapsed,
                        stashCollapsed: zen || visibility != .revealedAll, zen: zen)
    }
}
