import Foundation

/// The menu bar items Meno has seen, to tell which ones are new.
///
/// A steady key, an app's only item or one with an accessibility identifier,
/// names the same item for as long as the app shows it, so such an item is
/// new when its key was never seen. The other keys come from an item's text
/// or its place among its app's items, which change when the text does, for
/// example "Battery: Charging" becoming "Battery: 2:14 remaining". For those
/// the app counts instead: its items are new when the app was never seen, or
/// when it shows more of them than it ever did. Their keys are not kept, so
/// the list does not grow with every change of text.
public struct KnownItems: Codable, Equatable, Sendable {
    /// The steady keys seen, as raw values.
    public var keys: Set<String>
    /// For apps with items whose keys are not steady: the most of those
    /// items shown at once, by owner. Zero means the app is known but its
    /// count is not yet, as after reading what an earlier version wrote.
    public var itemCounts: [String: Int]

    public init(keys: Set<String> = [], itemCounts: [String: Int] = [:]) {
        self.keys = keys
        self.itemCounts = itemCounts
    }

    /// Reads `known-items.json`: this format, or the list of keys that
    /// earlier versions wrote, of which only the steady ones are kept.
    public static func decode(from data: Data) throws -> KnownItems {
        if let known = try? JSONDecoder().decode(KnownItems.self, from: data) {
            return known
        }
        let raw = try JSONDecoder().decode([String].self, from: data)
        var known = KnownItems()
        for key in raw.compactMap(MenuItemKey.init(rawValue:)) {
            if key.isSteady {
                known.keys.insert(key.rawValue)
            } else {
                known.itemCounts[key.owner] = 0
            }
        }
        return known
    }

    /// Remembers the items of a scan, given from left to right, and returns
    /// the keys of those that are new.
    public mutating func arrivals(in scan: [MenuItemKey]) -> [MenuItemKey] {
        var arrivals: [MenuItemKey] = []
        var owners: [String] = []
        var changing: [String: [MenuItemKey]] = [:]
        for key in scan {
            if key.isSteady {
                let seen = keys.contains(key.rawValue)
                    // The app's only item, after it showed several.
                    || (key.token == "solo" && itemCounts[key.owner] != nil)
                keys.insert(key.rawValue)
                if !seen { arrivals.append(key) }
            } else {
                if changing[key.owner] == nil { owners.append(key.owner) }
                changing[key.owner, default: []].append(key)
            }
        }
        for owner in owners {
            let items = changing[owner] ?? []
            // An app that showed a single item before counts it.
            let seen = itemCounts[owner] ?? (keys.contains(MenuItemKey(owner: owner, token: "solo").rawValue) ? 1 : nil)
            if let seen {
                // New items show up left of an app's other items.
                if seen > 0, items.count > seen {
                    arrivals.append(contentsOf: items.prefix(items.count - seen))
                }
                itemCounts[owner] = max(seen, items.count)
            } else {
                arrivals.append(contentsOf: items)
                itemCounts[owner] = items.count
            }
        }
        return arrivals
    }
}
