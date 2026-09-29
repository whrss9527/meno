import Foundation

/// A stable identifier for a menu bar item.
///
/// Keys survive relaunches of Meno and of the owning app, so they can be stored
/// in scenes, rules and hotkeys. A key combines the owner (usually the bundle
/// identifier of the process that created the item) with a token derived from
/// the item's accessibility attributes.
public struct MenuItemKey: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    /// Bundle identifier (or process name) of the app that owns the item.
    public let owner: String
    /// Distinguishes the items of one owner.
    public let token: String

    public init(owner: String, token: String) {
        self.owner = owner
        self.token = token
    }

    /// Parses a key from its `rawValue` representation.
    public init?(rawValue: String) {
        guard let separator = rawValue.firstIndex(of: "#") else { return nil }
        let owner = String(rawValue[..<separator])
        let token = String(rawValue[rawValue.index(after: separator)...])
        guard !owner.isEmpty, !token.isEmpty else { return nil }
        self.init(owner: owner, token: token)
    }

    /// A single-string representation, suitable for persistence.
    public var rawValue: String { "\(owner)#\(token)" }

    public var description: String { rawValue }

    public static func < (lhs: MenuItemKey, rhs: MenuItemKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let key = MenuItemKey(rawValue: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid menu item key: \(string)"
            )
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Token derivation

extension MenuItemKey {
    /// Accessibility attributes that describe one item of an app.
    public struct Attributes: Equatable, Sendable {
        public var identifier: String?
        public var description: String?
        public var title: String?

        public init(identifier: String? = nil, description: String? = nil, title: String? = nil) {
            self.identifier = identifier
            self.description = description
            self.title = title
        }
    }

    /// Derives stable tokens for all items that belong to one owner.
    ///
    /// - Items that expose an accessibility identifier use it verbatim.
    /// - An owner with a single item gets the token `solo`, because titles and
    ///   descriptions often contain live values (battery level, CPU load…).
    /// - Otherwise the description or title is normalized by stripping digits
    ///   and punctuation, so "CPU 12%" and "CPU 57%" map to the same token.
    /// - The position among siblings is the last resort.
    ///
    /// Duplicate tokens get a numeric suffix so every returned token is unique.
    /// - Parameter items: The items of one owner in left-to-right order.
    public static func tokens(for items: [Attributes]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if let identifier = item.identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               !identifier.isEmpty {
                result.append("id:" + identifier)
                continue
            }
            if items.count == 1 {
                result.append("solo")
                continue
            }
            let candidates = [item.description, item.title].compactMap { $0 }.map(normalize)
            if let text = candidates.first(where: { !$0.isEmpty }) {
                result.append("ax:" + text)
            } else {
                result.append("idx:\(index)")
            }
        }
        // Make tokens unique while keeping the first occurrence untouched.
        var seen: [String: Int] = [:]
        for index in result.indices {
            let token = result[index]
            if let count = seen[token] {
                seen[token] = count + 1
                result[index] = "\(token)~\(count + 1)"
            } else {
                seen[token] = 1
            }
        }
        return result
    }

    /// Lowercases text and removes everything except letters and single spaces.
    public static func normalize(_ text: String) -> String {
        var output = ""
        var pendingSpace = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                if pendingSpace, !output.isEmpty { output.append(" ") }
                pendingSpace = false
                output.unicodeScalars.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return output
    }
}

// MARK: - Sections

/// The part of the menu bar an item lives in.
public enum ItemSection: String, Codable, CaseIterable, Sendable {
    /// Always shown in the menu bar.
    case visible
    /// Shown on demand: by clicking the Meno icon, hovering, scrolling or a hotkey.
    case hidden
    /// Never shown in the menu bar; reachable from the Shelf and Quick Open.
    case stash

    /// Sections ordered from the right edge of the menu bar to the left.
    public static let rightToLeft: [ItemSection] = [.visible, .hidden, .stash]
}
