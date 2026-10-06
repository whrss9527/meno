import Foundation

/// Decides which misplaced divider must be reseated first.
public enum DividerOrder {
    public struct Frames: Sendable {
        public var hidden: HorizontalSpan?
        public var stash: HorizontalSpan?
        public var toggle: HorizontalSpan?
        public var toggleExists: Bool
        public init(hidden: HorizontalSpan?, stash: HorizontalSpan? = nil, toggle: HorizontalSpan? = nil, toggleExists: Bool = true) {
            self.hidden = hidden
            self.stash = stash
            self.toggle = toggle
            self.toggleExists = toggleExists
        }
    }
    public enum Repair: Equatable, Sendable { case hidden, stash }
    public static func isInOrder(frames: Frames) -> Bool {
        guard frames.hidden != nil else { return false }
        return repair(frames: frames) == nil
    }
    public static func repair(frames: Frames) -> Repair? {
        guard let hidden = frames.hidden else { return nil }
        if frames.toggleExists, let toggle = frames.toggle, hidden.maxX > toggle.maxX { return .hidden }
        if let stash = frames.stash, stash.maxX > hidden.maxX { return .stash }
        return nil
    }
}
