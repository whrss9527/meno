import Foundation

/// Decides when a watched menu bar item changed enough to be shown.
///
/// Each check reports the item's text (with digits and punctuation
/// removed, so counters and percentages do not count) and, when it can be
/// captured, a fingerprint of its artwork. A change has to show up in
/// consecutive checks, which ignores brief flickers, and an item is shown
/// at most once per cooldown.
public struct ChangeTracker: Sendable {
    public struct Sample: Equatable, Sendable {
        public var text: String
        public var glyph: GlyphSignature?

        public init(text: String, glyph: GlyphSignature? = nil) {
            self.text = text
            self.glyph = glyph
        }

        /// A sample from raw accessibility texts.
        public init(texts: [String?], glyph: GlyphSignature? = nil) {
            self.init(text: texts.compactMap { $0 }.map(MenuItemKey.normalize).joined(separator: " "), glyph: glyph)
        }
    }

    private struct State: Sendable {
        var text: String
        var glyph: GlyphSignature?
        var pending = 0
        var lastShown: Date?
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
            var glyphChanged = false
            if let new = sample.glyph, let old = state.glyph {
                glyphChanged = new.differs(from: old)
            }
            let isDifferent = sample.text != state.text || glyphChanged
            if absorbing || !isDifferent {
                state.text = sample.text
                state.glyph = sample.glyph ?? state.glyph
                state.pending = 0
            } else {
                state.pending += 1
                if state.pending >= confirmations {
                    state.text = sample.text
                    state.glyph = sample.glyph ?? state.glyph
                    state.pending = 0
                    if state.lastShown.map({ date.timeIntervalSince($0) >= cooldown }) ?? true {
                        state.lastShown = date
                        changed.append(key)
                    }
                }
            }
            states[key] = state
        }
        return changed.sorted()
    }

    public mutating func reset() {
        states = [:]
    }
}
