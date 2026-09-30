import Foundation

/// Days of the week, numbered as `Calendar` numbers them: 1 is Sunday and
/// 7 is Saturday.
public enum Weekdays {
    public static let mondayToFriday = [2, 3, 4, 5, 6]

    /// All days in the order of a week that starts on `firstWeekday`, as
    /// `Calendar.firstWeekday` gives it.
    public static func ordered(startingOn firstWeekday: Int) -> [Int] {
        let first = (1...7).contains(firstWeekday) ? firstWeekday : 1
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// `days` without repeats or invalid numbers, in the order of a week
    /// that starts on `firstWeekday`.
    public static func normalized(_ days: [Int], firstWeekday: Int = 1) -> [Int] {
        let set = Set(days)
        return ordered(startingOn: firstWeekday).filter(set.contains)
    }

    /// `days` with `day` added or removed.
    public static func toggling(_ day: Int, in days: [Int]) -> [Int] {
        var set = Set(days)
        if set.remove(day) == nil { set.insert(day) }
        return normalized(Array(set))
    }
}
