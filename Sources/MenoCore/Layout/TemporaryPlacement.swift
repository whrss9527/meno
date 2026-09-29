import Foundation

/// An item shown in the menu bar for a while, and the section it goes back
/// to afterwards.
public struct TemporaryPlacement: Codable, Hashable, Identifiable, Sendable {
    public var itemKey: MenuItemKey
    /// Where the item goes back to.
    public var returnSection: ItemSection
    /// When it goes back.
    public var until: Date

    public var id: MenuItemKey { itemKey }

    public init(itemKey: MenuItemKey, returnSection: ItemSection, until: Date) {
        self.itemKey = itemKey
        self.returnSection = returnSection
        self.until = until
    }

    /// The durations offered for showing an item for a while, in seconds.
    public static let durations: [TimeInterval] = [15 * 60, 60 * 60, 4 * 60 * 60]
}

extension Array where Element == TemporaryPlacement {
    /// The placement of an item, if it is shown for a while.
    public func placement(of key: MenuItemKey) -> TemporaryPlacement? {
        first { $0.itemKey == key }
    }

    /// Records that an item is shown until `date`. An item that already is
    /// keeps its original section and gets the new time.
    public mutating func show(_ key: MenuItemKey, from section: ItemSection, until date: Date) {
        if let index = firstIndex(where: { $0.itemKey == key }) {
            self[index].until = date
        } else {
            append(TemporaryPlacement(itemKey: key, returnSection: section, until: date))
        }
    }

    /// Takes out and returns the placements whose time is up.
    public mutating func removeDue(at date: Date) -> [TemporaryPlacement] {
        let due = filter { $0.until <= date }
        removeAll { $0.until <= date }
        return due
    }

    /// When the next placement is due.
    public var nextDue: Date? {
        map(\.until).min()
    }

    /// How long to wait before checking again: until the next placement is
    /// due, and at most a minute while any is due but still waiting (for
    /// example for its app). `nil` without placements.
    public func delayUntilNextCheck(at date: Date, maximum: TimeInterval = 60) -> TimeInterval? {
        guard !isEmpty else { return nil }
        let upcoming = map(\.until).filter { $0 > date }.min()
        let delay = upcoming.map { $0.timeIntervalSince(date) } ?? maximum
        return Swift.min(Swift.max(delay, 1), maximum)
    }
}
