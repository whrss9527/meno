import Foundation

/// Decides when a watched menu bar item changed enough to be shown.
///
/// Each check reports the item's text (with digits and punctuation
/// removed, so counters and percentages do not count) and, when it can be
/// captured, a fingerprint of its artwork. A change has to show up in
/// consecutive checks, which ignores brief flickers. After a report the item
/// has to settle (look the same in two checks in a row) before it can be
/// reported again, so an animation, such as a spinner while syncing, is
/// reported once. On top of that an item is shown at most once per cooldown.
public struct ChangeTracker: Sendable {
    public struct Sample: Equatable, Sendable {
        /// `nil` when the text could not be read in this check.
        public var text: String?
        /// `nil` when the artwork could not be captured in this check.
        public var glyph: GlyphSignature?

        public init(text: String?, glyph: GlyphSignature? = nil) {
            self.text = text
            self.glyph = glyph
        }

        /// A sample from raw accessibility texts, or `nil` texts when they
        /// could not be read.
        public init(texts: [String?]?, glyph: GlyphSignature? = nil) {
            self.init(text: texts.map { $0.compactMap { $0 }.map(MenuItemKey.normalize).joined(separator: " ") }, glyph: glyph)
        }
    }

    private struct State: Sendable {
        var text: String?
        var glyph: GlyphSignature?
        var pending = 0
        /// Reported (or seen while absorbing) and not yet steady again.
        var settling = false
        var lastShown: Date?

        /// Whether a sample has a part that can be compared with the state.
        func canCompare(_ sample: Sample) -> Bool {
            (sample.text != nil && text != nil) || (sample.glyph != nil && glyph != nil)
        }

        /// Whether a sample shows something else than the state knows.
        /// Parts that are unknown on either side do not count.
        func differs(from sample: Sample) -> Bool {
            if let new = sample.text, let old = text, new != old { return true }
            if let new = sample.glyph, let old = glyph, new.differs(from: old) { return true }
            return false
        }

        mutating func adopt(_ sample: Sample) {
            text = sample.text ?? text
            glyph = sample.glyph ?? glyph
        }
    }

    /// How many checks in a row have to see the change.
    public var confirmations: Int
    /// The minimum time between two reports for one item.
    public var cooldown: TimeInterval

    private var states: [MenuItemKey: State] = [:]

    public init(confirmations: Int = 2, cooldown: TimeInterval = 30) {
        self.confirmations = confirmations
        self.cooldown = cooldown
    }

    /// Records a check of the watched items and returns those that changed.
    ///
    /// While `absorbing` (for example while the items are revealed and may
    /// be in use), changes become the new baseline without being reported.
    /// Items missing from `samples` are forgotten.
    public mutating func update(_ samples: [MenuItemKey: Sample], at date: Date, absorbing: Bool = false) -> [MenuItemKey] {
        states = states.filter { samples[$0.key] != nil }
        var changed: [MenuItemKey] = []
        for (key, sample) in samples {
            guard var state = states[key] else {
                states[key] = State(text: sample.text, glyph: sample.glyph)
                continue
            }
            let isDifferent = state.differs(from: sample)
            if absorbing {
                state.adopt(sample)
                state.pending = 0
                state.settling = isDifferent
            } else if state.settling {
                // Follows the item until it looks the same twice in a row.
                let isSteady = !isDifferent && state.canCompare(sample)
                state.adopt(sample)
                state.pending = 0
                state.settling = !isSteady
            } else if isDifferent {
                state.pending += 1
                if state.pending >= confirmations {
                    state.adopt(sample)
                    state.pending = 0
                    state.settling = true
                    if state.lastShown.map({ date.timeIntervalSince($0) >= cooldown }) ?? true {
                        state.lastShown = date
                        changed.append(key)
                    }
                }
            } else {
                state.adopt(sample)
                state.pending = 0
            }
            states[key] = state
        }
        return changed.sorted()
    }

    public mutating func reset() {
        states = [:]
    }
}
