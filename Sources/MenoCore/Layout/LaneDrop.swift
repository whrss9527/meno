import Foundation

/// Where an item dragged in the layout editor lands among the items of a
/// section, which are laid out left to right in rows that wrap.
///
/// A gap is a place between two items: 0 is before the first item, and the
/// number of items is after the last one.
public enum LaneDrop {
    /// The gap a drop at `point` lands in, or nil when it would leave the
    /// dragged item where it is. `frames` and `movable` describe the items
    /// in their order; `draggedIndex` is the dragged item's place among
    /// them, or nil when it comes from another section.
    public static func target(at point: CGPoint, frames: [CGRect], movable: [Bool], draggedIndex: Int?) -> Int? {
        let landing = allowedGap(gap(at: point, frames: frames), movable: movable)
        return moves(into: landing, from: draggedIndex) ? landing : nil
    }

    /// The gap nearest `point`: in the row closest to it vertically, the
    /// gap before the first item whose middle lies right of it.
    public static func gap(at point: CGPoint, frames: [CGRect]) -> Int {
        guard !frames.isEmpty else { return 0 }
        // A row starts where an item lies left of the one before it.
        var rows: [Range<Int>] = []
        var start = 0
        for index in 1..<frames.count where frames[index].minX < frames[index - 1].minX {
            rows.append(start..<index)
            start = index
        }
        rows.append(start..<frames.count)
        func distance(to row: Range<Int>) -> CGFloat {
            let top = row.map { frames[$0].minY }.min() ?? 0
            let bottom = row.map { frames[$0].maxY }.max() ?? 0
            return max(top - point.y, point.y - bottom, 0)
        }
        let row = rows.min { distance(to: $0) < distance(to: $1) } ?? rows[0]
        return row.first { point.x < frames[$0].midX } ?? row.upperBound
    }

    /// `gap`, moved left past items macOS keeps in place, such as the
    /// clock: nothing can go right of those.
    public static func allowedGap(_ gap: Int, movable: [Bool]) -> Int {
        var gap = min(max(gap, 0), movable.count)
        while gap > 0, !movable[gap - 1] {
            gap -= 1
        }
        return gap
    }

    /// Whether dropping the item at `draggedIndex` into `gap` moves it: the
    /// gaps on either side of it leave it where it is.
    public static func moves(into gap: Int, from draggedIndex: Int?) -> Bool {
        guard let draggedIndex else { return true }
        return gap != draggedIndex && gap != draggedIndex + 1
    }
}
