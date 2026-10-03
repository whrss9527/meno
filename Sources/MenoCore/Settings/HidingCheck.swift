import Foundation

/// Whether hiding works: after items are hidden, the ones that belong in a
/// collapsed section should have left the screen.
///
/// Hiding relies on how the menu bar treats a divider that grows, which macOS
/// does not promise. A scan made while sections are collapsed shows whether
/// it still works; one scan can catch the menu bar in the middle of a change,
/// so it takes two in a row to count as failed.
public struct HidingCheck: Equatable, Sendable {
    public enum Verdict: String, Equatable, Sendable {
        /// No scan of hidden items yet.
        case unknown
        /// The items that belong hidden were off the screen.
        case verified
        /// They stayed on the screen in two scans in a row.
        case failed
    }

    public private(set) var verdict = Verdict.unknown
    private var misses = 0

    public init() {}

    /// Takes in a scan made while sections are collapsed: how many of the
    /// items that belong in them were still on a screen, out of how many.
    /// Returns whether hiding has just been found not to work.
    public mutating func record(onScreen: Int, of total: Int) -> Bool {
        guard total > 0 else { return false }
        guard onScreen > 0 else {
            misses = 0
            verdict = .verified
            return false
        }
        misses += 1
        guard misses >= 2, verdict != .failed else { return false }
        verdict = .failed
        return true
    }

    /// Starts over, for example with another engine.
    public mutating func reset() {
        self = HidingCheck()
    }
}

extension HidingEngine {
    /// The engine to switch to when `failed` did not hide items: the other
    /// one while Meno picks the engine, and none when the person picked it.
    public func fallback(after failed: ResolvedHidingEngine) -> ResolvedHidingEngine? {
        guard self == .automatic else { return nil }
        switch failed {
        case .wide: return .stepped
        case .stepped: return .wide
        }
    }
}
