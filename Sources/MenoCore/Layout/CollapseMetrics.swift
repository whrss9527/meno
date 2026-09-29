import Foundation

/// Sizes used to push hidden items out of the menu bar.
///
/// Dividers hide the items to their left by growing: a wide divider occupies
/// the space the hidden items would otherwise use.
///
/// Up to macOS 26 a single status item may grow far beyond the screen width.
/// Starting with macOS 27 the menu bar drops any item whose width (plus about
/// 16 pt of padding) reaches half of the display width, and a single large
/// change of length does not push the neighbours along. The stepped engine
/// therefore grows the divider together with a few helper spacers, each just
/// below that limit, in small increments.
public enum CollapseMetrics {
    public static let firstSteppedMajorVersion = 27
    /// Growth per step for the stepped engine.
    public static let steppedIncrement: Double = 40
    /// Padding macOS adds around each status item.
    public static let itemPadding: Double = 16
    public static let fallbackScreenWidth: Double = 1440

    /// Length of a single divider that pushes everything to its left off
    /// every attached screen: twice the widest screen, or more than all
    /// screens side by side reach (`horizontalSpan`).
    public static func wideLength(screenWidths: [Double], horizontalSpan: Double = 0) -> Double {
        let widest = screenWidths.filter { $0 > 0 }.max() ?? fallbackScreenWidth
        return min(max(widest * 2, horizontalSpan + 200, 2_400), 10_000)
    }

    /// The largest length one status item can have on every attached screen
    /// under the stepped engine.
    public static func steppedUnit(screenWidths: [Double]) -> Double {
        let narrowest = screenWidths.filter { $0 > 0 }.min() ?? fallbackScreenWidth
        return max((narrowest / 2).rounded(.down) - itemPadding - 1, 64)
    }

    /// How many spacers must grow along with a divider so their combined
    /// width covers the widest screen.
    public static func steppedSpacerCount(screenWidths: [Double], maximum: Int = 6) -> Int {
        let unit = steppedUnit(screenWidths: screenWidths)
        let widest = screenWidths.filter { $0 > 0 }.max() ?? fallbackScreenWidth
        let unitsNeeded = Int(((widest + 64) / unit).rounded(.up))
        return min(max(unitsNeeded - 1, 1), maximum)
    }

    /// Intermediate lengths from `start` to `end`. Shrinking happens in one
    /// step; growing is split into `increment`-sized steps.
    public static func rampSteps(from start: Double, to end: Double, increment: Double = steppedIncrement) -> [Double] {
        guard end > start, increment > 0 else { return [end] }
        var values: [Double] = []
        var value = start
        while value + increment < end {
            value += increment
            values.append(value)
        }
        values.append(end)
        return values
    }

    /// Preferred positions (points from the right edge of the menu bar) that
    /// place `count` helper items immediately right of an item stored at
    /// `position`.
    public static func positionsRight(of position: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let gap = min(0.9, max(position, 0)) / Double(count + 1)
        return (1...count).map { index in
            max(position - gap * Double(index), 0)
        }
    }
}
