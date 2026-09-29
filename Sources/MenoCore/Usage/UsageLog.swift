import Foundation

/// Where an item was opened from.
public enum UsageSource: String, Codable, CaseIterable, Sendable {
    /// Clicked directly in the menu bar.
    case menuBar
    case shelf
    case quickOpen
    case hotkey
    case rule
}

/// Usage of a single item.
public struct ItemUsage: Codable, Equatable, Sendable {
    public var total: Int = 0
    /// Opens while the item was in the Hidden section or the Stash.
    public var whileConcealed: Int = 0
    public var lastUsed: Date?
    /// Opens per day, keyed by `yyyy-MM-dd`.
    public var daily: [String: Int] = [:]

    public init() {}
}

/// A local, private record of how the menu bar is used. Nothing leaves the Mac.
public struct UsageLog: Codable, Equatable, Sendable {
    public var items: [String: ItemUsage] = [:]
    /// Reveals per day, keyed by `yyyy-MM-dd`.
    public var reveals: [String: Int] = [:]
    /// Reveals per trigger (click, hover, scroll, hotkey…).
    public var revealTriggers: [String: Int] = [:]
    public var firstRecorded: Date?

    public init() {}

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public mutating func recordItemUse(
        _ key: MenuItemKey,
        section: ItemSection?,
        source: UsageSource,
        at date: Date,
        calendar: Calendar = .current
    ) {
        if firstRecorded == nil { firstRecorded = date }
        var usage = items[key.rawValue] ?? ItemUsage()
        usage.total += 1
        if let section, section != .visible { usage.whileConcealed += 1 }
        usage.lastUsed = date
        usage.daily[Self.dayKey(for: date, calendar: calendar), default: 0] += 1
        items[key.rawValue] = usage
    }

    public mutating func recordReveal(trigger: String, at date: Date, calendar: Calendar = .current) {
        if firstRecorded == nil { firstRecorded = date }
        reveals[Self.dayKey(for: date, calendar: calendar), default: 0] += 1
        revealTriggers[trigger, default: 0] += 1
    }

    public func usage(of key: MenuItemKey) -> ItemUsage? {
        items[key.rawValue]
    }

    /// Day keys of the last `days` days, oldest first, ending with `now`.
    public static func recentDayKeys(_ days: Int, now: Date, calendar: Calendar) -> [(key: String, date: Date)] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (dayKey(for: date, calendar: calendar), date)
        }
    }

    /// Opens of an item during the last `days` days.
    public func count(of key: MenuItemKey, lastDays days: Int, now: Date, calendar: Calendar = .current) -> Int {
        guard let usage = items[key.rawValue] else { return 0 }
        return Self.recentDayKeys(days, now: now, calendar: calendar).reduce(0) { sum, day in
            sum + (usage.daily[day.key] ?? 0)
        }
    }

    /// The most used items, most used first. Ties are broken by key.
    public func topItems(
        limit: Int,
        lastDays days: Int? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(key: MenuItemKey, count: Int)] {
        let counts: [(key: MenuItemKey, count: Int)] = items.compactMap { raw, usage in
            guard let key = MenuItemKey(rawValue: raw) else { return nil }
            let count = days.map { self.count(of: key, lastDays: $0, now: now, calendar: calendar) } ?? usage.total
            return count > 0 ? (key, count) : nil
        }
        return Array(
            counts.sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.key < rhs.key
            }
            .prefix(max(limit, 0))
        )
    }

    /// Reveals per day for the last `days` days, oldest first.
    public func dailyReveals(lastDays days: Int, now: Date = Date(), calendar: Calendar = .current) -> [(date: Date, count: Int)] {
        Self.recentDayKeys(days, now: now, calendar: calendar).map { day in
            (day.date, reveals[day.key] ?? 0)
        }
    }

    /// Drops per-day records older than `days` days.
    public mutating func prune(keepingDays days: Int, now: Date = Date(), calendar: Calendar = .current) {
        let keep = Set(Self.recentDayKeys(days, now: now, calendar: calendar).map(\.key))
        reveals = reveals.filter { keep.contains($0.key) }
        for (raw, usage) in items {
            var trimmed = usage
            trimmed.daily = usage.daily.filter { keep.contains($0.key) }
            items[raw] = trimmed
        }
    }

    /// Suggestions for a tidier menu bar based on recent usage.
    ///
    /// - Items opened at least `promoteThreshold` times during the last week
    ///   while concealed are suggested for the Visible section.
    /// - Visible items unused for `idleDays` days are suggested for Hidden,
    ///   once Meno has been recording for at least that long.
    public func suggestions(
        sections: [MenuItemKey: ItemSection],
        movable: Set<MenuItemKey>,
        now: Date = Date(),
        calendar: Calendar = .current,
        promoteThreshold: Int = 5,
        idleDays: Int = 21
    ) -> [UsageSuggestion] {
        var result: [UsageSuggestion] = []
        for (key, section) in sections.sorted(by: { $0.key < $1.key }) where movable.contains(key) {
            switch section {
            case .hidden, .stash:
                let uses = count(of: key, lastDays: 7, now: now, calendar: calendar)
                if uses >= promoteThreshold {
                    result.append(.promote(key, uses: uses))
                }
            case .visible:
                guard let firstRecorded,
                      let recordingDays = calendar.dateComponents([.day], from: firstRecorded, to: now).day,
                      recordingDays >= idleDays else { continue }
                let lastUsed = items[key.rawValue]?.lastUsed ?? firstRecorded
                let idle = calendar.dateComponents([.day], from: lastUsed, to: now).day ?? 0
                if idle >= idleDays {
                    result.append(.demote(key, idleDays: idle))
                }
            }
        }
        return result.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (.promote(_, a), .promote(_, b)): return a > b
            case (.promote, .demote): return true
            case (.demote, .promote): return false
            case let (.demote(_, a), .demote(_, b)): return a > b
            }
        }
    }
}

public enum UsageSuggestion: Hashable, Sendable {
    /// Frequently opened while concealed: show it permanently.
    case promote(MenuItemKey, uses: Int)
    /// Not used for a long time: hide it.
    case demote(MenuItemKey, idleDays: Int)

    public var key: MenuItemKey {
        switch self {
        case .promote(let key, _), .demote(let key, _): return key
        }
    }
}
