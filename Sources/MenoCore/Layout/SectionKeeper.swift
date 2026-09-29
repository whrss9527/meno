import Foundation

/// Remembers the section each item was left in, so that an item its app or
/// macOS put elsewhere can go back.
///
/// An item that stays in the menu bar from one scan to the next and changes
/// section was moved on purpose, by the person or by Meno, and its new
/// section is remembered; so is every move Meno reports. An item that
/// appears with its app (the app launched or restarted, or Meno just
/// started) in another section than it was left in was put there by its
/// app or by macOS, so it belongs back.
///
/// Only items of apps that appeared a moment before the item did go back:
/// an item that shows up in an app that was there all along was most likely
/// added on purpose, so where it is counts. Only items with steady keys are
/// kept, an app's only item or one with an accessibility identifier; keys
/// taken from an item's text or its position may name another item later.
public struct SectionKeeper: Sendable {
    public struct Observation: Equatable, Sendable {
        public var key: MenuItemKey
        /// Where the item is, or `nil` when its position is not known now.
        public var section: ItemSection?
        /// The process that shows the item. Another one means the item was
        /// made anew, even if it never went missing between two scans.
        public var process: Int32

        public init(key: MenuItemKey, section: ItemSection?, process: Int32) {
            self.key = key
            self.section = section
            self.process = process
        }
    }

    public struct Misplacement: Equatable, Sendable {
        public var key: MenuItemKey
        /// Where the item appeared.
        public var found: ItemSection
        /// Where it was left.
        public var belongs: ItemSection

        public init(key: MenuItemKey, found: ItemSection, belongs: ItemSection) {
            self.key = key
            self.found = found
            self.belongs = belongs
        }
    }

    public struct Remembered: Codable, Equatable, Sendable {
        public var section: ItemSection
        /// When the item was last seen, to the day, so that items of apps
        /// that are gone can be forgotten.
        public var seen: Date

        public init(section: ItemSection, seen: Date) {
            self.section = section
            self.seen = seen
        }
    }

    /// How often an item is put back while Meno runs before its app wins.
    public static let putBackLimit = 3
    /// How long after an app appeared its new items count as appearing
    /// with it.
    public static let appearanceWindow: TimeInterval = 60

    /// Where the items were left, by key.
    public private(set) var memory: [String: Remembered]
    /// Whether `memory` changed since `markSaved()`.
    public private(set) var hasUnsavedChanges = false

    private struct Sighting {
        /// Where the item was, `nil` while that is not known.
        var section: ItemSection?
        var process: Int32
        /// Whether the item appeared with its app, for as long as its
        /// section is not known yet.
        var appearedWithApp: Bool
    }

    private var previous: [MenuItemKey: Sighting] = [:]
    /// When each process in the menu bar was first seen.
    private var processes: [Int32: Date] = [:]
    private var putBacks: [MenuItemKey: Int] = [:]

    public init(memory: [String: Remembered] = [:]) {
        self.memory = memory
    }

    /// Takes in a scan and returns the items that appeared in another
    /// section than they were left in. Without the Stash, its items count
    /// as hidden.
    public mutating func observe(_ observations: [Observation], at date: Date, includesStash: Bool) -> [Misplacement] {
        var present: [Int32: Date] = [:]
        for observation in observations {
            present[observation.process] = processes[observation.process] ?? date
        }
        processes = present
        var current: [MenuItemKey: Sighting] = [:]
        var misplaced: [Misplacement] = []
        for observation in observations where observation.key.isSteady {
            let key = observation.key
            let before = previous[key].flatMap { $0.process == observation.process ? $0 : nil }
            guard let found = observation.section.map({ Self.effective($0, includesStash: includesStash) }) else {
                // Not known for now: the item stays as it was, and one that
                // just appeared keeps whether it came with its app.
                current[key] = before ?? Sighting(
                    section: nil,
                    process: observation.process,
                    appearedWithApp: appearedWithApp(observation.process, at: date)
                )
                continue
            }
            current[key] = Sighting(section: found, process: observation.process, appearedWithApp: false)
            if let before, let section = before.section {
                // Moved while in the menu bar: on purpose.
                if section != found {
                    remember(found, for: key, at: date)
                } else {
                    touch(key, at: date)
                }
                continue
            }
            let withApp = before?.appearedWithApp ?? appearedWithApp(observation.process, at: date)
            let remembered = memory[key.rawValue]
            if let remembered,
               Self.effective(remembered.section, includesStash: includesStash) != found,
               withApp,
               putBacks[key, default: 0] < Self.putBackLimit {
                misplaced.append(Misplacement(key: key, found: found, belongs: remembered.section))
                touch(key, at: date)
            } else if remembered.map({ Self.effective($0.section, includesStash: includesStash) }) == found {
                touch(key, at: date)
            } else {
                remember(found, for: key, at: date)
            }
        }
        previous = current
        return misplaced
    }

    /// Takes in that Meno just put an item in a section, for example with a
    /// rule or a scene: that is where it belongs now.
    public mutating func record(_ key: MenuItemKey, in section: ItemSection, process: Int32, at date: Date, includesStash: Bool) {
        guard key.isSteady else { return }
        remember(section, for: key, at: date)
        previous[key] = Sighting(
            section: Self.effective(section, includesStash: includesStash),
            process: process,
            appearedWithApp: false
        )
        if processes[process] == nil {
            processes[process] = date
        }
    }

    /// Counts that an item was put back, so that one whose app keeps moving
    /// it is left where its app wants it after a few times.
    public mutating func didPutBack(_ key: MenuItemKey) {
        putBacks[key, default: 0] += 1
    }

    /// Keeps the items where they are now, for when they are not put back.
    public mutating func accept(_ misplacements: [Misplacement], at date: Date) {
        for misplacement in misplacements {
            remember(misplacement.found, for: misplacement.key, at: date)
        }
    }

    /// Forgets items that were not seen since `date`.
    public mutating func forget(notSeenSince date: Date) {
        let before = memory.count
        memory = memory.filter { $0.value.seen >= date }
        if memory.count != before { hasUnsavedChanges = true }
    }

    public mutating func markSaved() {
        hasUnsavedChanges = false
    }

    private func appearedWithApp(_ process: Int32, at date: Date) -> Bool {
        processes[process].map { date.timeIntervalSince($0) <= Self.appearanceWindow } ?? true
    }

    private mutating func remember(_ section: ItemSection, for key: MenuItemKey, at date: Date) {
        let entry = Remembered(section: section, seen: Self.day(of: date))
        guard memory[key.rawValue] != entry else { return }
        memory[key.rawValue] = entry
        hasUnsavedChanges = true
    }

    private mutating func touch(_ key: MenuItemKey, at date: Date) {
        let day = Self.day(of: date)
        guard let entry = memory[key.rawValue], entry.seen < day else { return }
        memory[key.rawValue]?.seen = day
        hasUnsavedChanges = true
    }

    private static func effective(_ section: ItemSection, includesStash: Bool) -> ItemSection {
        section == .stash && !includesStash ? .hidden : section
    }

    /// The start of the UTC day, so that `seen` changes once a day at most.
    private static func day(of date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: seconds - seconds.truncatingRemainder(dividingBy: 86_400))
    }
}

extension MenuItemKey {
    /// Whether the key names the same item for as long as its app shows it:
    /// the app's only item, or one with an accessibility identifier. Keys
    /// taken from an item's text or its position among its app's items may
    /// name another item after a change.
    public var isSteady: Bool {
        (token == "solo" || token.hasPrefix("id:")) && !token.contains("~")
    }
}
