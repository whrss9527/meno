import Foundation

/// Finds elements that stand in for another app's menu bar item.
///
/// On macOS 26, Control Center can report an element for an item that
/// belongs to another app, at the same place as the app's own element.
/// Keeping both would list the item twice, once as a system item.
public enum HostedItems {
    public struct Element: Sendable {
        public var owner: String
        public var identifier: String?
        public var minX: Double
        public var maxX: Double
        public var minY: Double
        public var maxY: Double

        public init(owner: String, identifier: String? = nil, minX: Double, maxX: Double, minY: Double, maxY: Double) {
            self.owner = owner
            self.identifier = identifier
            self.minX = minX
            self.maxX = maxX
            self.minY = minY
            self.maxY = maxY
        }

        var width: Double { maxX - minX }
        var height: Double { maxY - minY }

        /// Apple's own items (Wi‑Fi, Sound, …) identify themselves as such
        /// and are never stand-ins.
        var isAppleItem: Bool { identifier?.hasPrefix("com.apple.") ?? false }
    }

    /// The processes that show items on behalf of other apps.
    public static let hosts: Set<String> = ["com.apple.controlcenter", "com.apple.systemuiserver"]

    /// Indices of host elements that cover most of an element of another
    /// owner, on the same menu bar.
    public static func duplicates(in elements: [Element], hosts: Set<String> = hosts) -> Set<Int> {
        var result: Set<Int> = []
        for (index, element) in elements.enumerated()
        where hosts.contains(element.owner) && !element.isAppleItem && element.width > 0 {
            let covers = elements.contains { other in
                !hosts.contains(other.owner) && other.width > 0 && other.height > 0
                    && overlap(element.minX, element.maxX, other.minX, other.maxX) >= 0.5 * min(element.width, other.width)
                    && overlap(element.minY, element.maxY, other.minY, other.maxY) > 0
            }
            if covers { result.insert(index) }
        }
        return result
    }

    private static func overlap(_ minA: Double, _ maxA: Double, _ minB: Double, _ maxB: Double) -> Double {
        max(0, min(maxA, maxB) - max(minA, minB))
    }
}
