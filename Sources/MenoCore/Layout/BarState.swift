/// Which dividers are grown.
public struct BarState: Equatable, Sendable {
    public var hiddenCollapsed: Bool
    public var stashCollapsed: Bool
    public var zen: Bool

    public init(hiddenCollapsed: Bool = false, stashCollapsed: Bool = false, zen: Bool = false) {
        self.hiddenCollapsed = hiddenCollapsed
        self.stashCollapsed = stashCollapsed
        self.zen = zen
    }
}
