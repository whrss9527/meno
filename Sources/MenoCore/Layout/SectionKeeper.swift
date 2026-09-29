import Foundation

/// Remembers the section each item was left in, so that an item its app or
/// macOS put elsewhere can go back.
///
/// An item that stays in the menu bar from one scan to the next and changes
/// section was moved on purpose, by the person or by Meno, and its new
/// section is remembered. An item that appears with its app (the app
/// launched or restarted, or Meno just started) in another section than it
/// was left in was put there by its app or by macOS, so it belongs back.
///
/// Only items of apps that appeared a moment ago go back. An item that
/// shows up in an app that was there all along may be an item whose key
/// changed with its text, so where it is counts. Items whose keys depend on
/// their position among an app's items are left alone: after a change they
/// could name another item.
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
    /// How long after an app appeared its items still count as appearing.
    public static let appearanceWindow: TimeInterval = 60

    /// Where the items were left, by key.
    public private(set) var memory: [String: Remembered]
    /// Whether `memory` changed since `markSaved()`.
    public private(set) var hasUnsavedChanges = false

    private var previous: [MenuItemKey: (section: ItemSection, process: Int32)] = [:]
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
        var current: [MenuItemKey: (section: ItemSection, process: Int32)] = [:]
        var misplaced: [Misplacement] = []
        var present: [Int32: Date] = [:]
        for observation in observations {
            present[observation.process] = processes[observation.process] ?? date
        }
        processes = present
        for observation in observations where !observation.key.isPositional {
            let key = observation.key
            let before = previous[key].flatMap { $0.process == observation.process ? $0 : nil }
            guard let found = observation.section.map({ Self.effective($0, includesStash: includesStash) }) else {
                // Unknown for now: the item stays as it was while its
                // process does, and counts as new once it is known again.
                if let before { current[key] = before }
                continue
            }
            current[key] = (found, observation.process)
            let remembered = memory[key.rawValue]
            if let before {
                // Moved while in the menu bar: on purpose.
                if before.section != found {
                    remember(found, for: key, at: date)
                } else {
                    touch(key, at: date)
                }
                continue
            }
            let appeared = present[observation.process].map { date.timeIntervalSince($0) <= Self.appearanceWindow } ?? true
            if let remembered,
               Self.effective(remembered.section, includesStash: includesStash) != found,
               appeared,
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
    /// Whether the key depends on the item's position among its app's
    /// items, so that after a change it may name another item.
    public var isPositional: Bool {
        token.hasPrefix("idx:") || token.contains("~")
    }
}
