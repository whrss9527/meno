import Foundation

/// Builds inventory values without Accessibility objects or a running app.
public enum InventoryBuilder {
    public struct RawItem: Sendable {
        public var owner: String
        public var appName: String
        public var frame: CGRect
        public var identifier: String?
        public var detail: String?
        public var title: String?
        public var help: String?
        public var isOnScreen: Bool
        public var isWithinScreenWidth: Bool

        public init(owner: String, appName: String, frame: CGRect, identifier: String? = nil,
                    detail: String? = nil, title: String? = nil, help: String? = nil,
                    isOnScreen: Bool = true, isWithinScreenWidth: Bool = true) {
            self.owner = owner
            self.appName = appName
            self.frame = frame
            self.identifier = identifier
            self.detail = detail
            self.title = title
            self.help = help
            self.isOnScreen = isOnScreen
            self.isWithinScreenWidth = isWithinScreenWidth
        }
    }

    public struct Dividers: Sendable {
        public var layout: DividerLayout?
        public var ownFrames: [CGRect]
        public var framesAreReliable: Bool

        public init(layout: DividerLayout?, ownFrames: [CGRect] = [], framesAreReliable: Bool = true) {
            self.layout = layout
            self.ownFrames = ownFrames
            self.framesAreReliable = framesAreReliable
        }
    }

    public struct Cache: Sendable {
        public var sections: [MenuItemKey: ItemSection]
        public var positions: [MenuItemKey: CGFloat]

        public init(sections: [MenuItemKey: ItemSection] = [:], positions: [MenuItemKey: CGFloat] = [:]) {
            self.sections = sections
            self.positions = positions
        }
    }

    public struct SkippedElements: Equatable, Sendable {
        public var unnamed: [String: Int] = [:]
        public var duplicates: [String: Int] = [:]
        public var empty: [String: Int] = [:]
        public init() {}
    }

    public struct Item: Sendable {
        /// Index of the original element, whose platform payload stays in the app.
        public var sourceIndex: Int
        public var key: MenuItemKey
        public var displayName: String
        public var frame: CGRect
        public var section: ItemSection
        public var isSystem: Bool
        public var isMovable: Bool
    }

    public struct Result: Sendable {
        public var items: [Item]
        public var cached: Cache
        public var reliablySectioned: Set<MenuItemKey>
        public var skipped: SkippedElements
    }

    public static func build(raw: [RawItem], dividers: Dividers, cached: Cache) -> Result {
        var cache = cached
        var skipped = SkippedElements()
        var named = raw.indices.filter { index in
            let entry = raw[index]
            guard ItemNaming.isUnnamedSystemElement(owner: entry.owner, texts: [entry.detail, entry.title, entry.help]) else { return true }
            skipped.unnamed[entry.owner, default: 0] += 1
            return false
        }
        let placements = named.map { index in
            let entry = raw[index]
            let frame = dividers.framesAreReliable || entry.isOnScreen ? entry.frame : .zero
            return HostedItems.Element(owner: entry.owner, identifier: entry.identifier,
                                       minX: Double(frame.minX), maxX: Double(frame.maxX),
                                       minY: Double(frame.minY), maxY: Double(frame.maxY))
        }
        let duplicates = HostedItems.duplicates(in: placements)
        for index in duplicates { skipped.duplicates[placements[index].owner, default: 0] += 1 }
        named = named.enumerated().filter { !duplicates.contains($0.offset) }.map(\.element)
        // Remove leftovers before counting siblings and deriving their keys.
        named = named.filter { index in
            let entry = raw[index]
            guard entry.frame.width < 1, dividers.framesAreReliable, entry.isWithinScreenWidth else { return true }
            skipped.empty[entry.owner, default: 0] += 1
            return false
        }
        let grouped = Dictionary(grouping: named) { raw[$0].owner }
        var items: [Item] = []
        var reliablySectioned: Set<MenuItemKey> = []
        for (owner, group) in grouped {
            let sorted = group.sorted { raw[$0].frame.minX < raw[$1].frame.minX }
            let tokens = MenuItemKey.tokens(for: sorted.map { index in
                let entry = raw[index]
                return MenuItemKey.Attributes(identifier: entry.identifier, description: entry.detail, title: entry.title)
            })
            for (index, token) in zip(sorted, tokens) {
                let entry = raw[index]
                let key = MenuItemKey(owner: owner, token: token)
                var frame = entry.frame
                let trustworthy = (dividers.framesAreReliable || entry.isOnScreen) && !overlaps(frame, dividers.ownFrames)
                let section: ItemSection
                if trustworthy, let layout = dividers.layout {
                    section = SectionResolver.section(of: HorizontalSpan(minX: Double(frame.minX), maxX: Double(frame.maxX)), dividers: layout)
                    cache.sections[key] = section
                    cache.positions[key] = frame.minX
                    reliablySectioned.insert(key)
                } else {
                    section = cache.sections[key] ?? .hidden
                    if trustworthy { cache.positions[key] = frame.minX }
                    else if let x = cache.positions[key] { frame.origin.x = x }
                }
                items.append(Item(sourceIndex: index, key: key, displayName: displayName(for: entry, siblings: sorted.count),
                                  frame: frame, section: section, isSystem: owner.hasPrefix("com.apple."),
                                  isMovable: !isPinned(entry)))
            }
        }
        return Result(items: items.sorted { $0.frame.minX < $1.frame.minX }, cached: cache,
                      reliablySectioned: reliablySectioned, skipped: skipped)
    }

    public static func overlaps(_ frame: CGRect, _ ownFrames: [CGRect]) -> Bool {
        ownFrames.contains { $0.minX < frame.midX && frame.midX < $0.maxX }
    }

    private static func displayName(for entry: RawItem, siblings: Int) -> String {
        let text = [entry.detail, entry.title, entry.help].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        if entry.owner.hasPrefix("com.apple.") { return text.map { ItemNaming.leadingName(of: $0) } ?? entry.appName }
        if siblings > 1, let text, text.caseInsensitiveCompare(entry.appName) != .orderedSame { return "\(entry.appName) – \(text)" }
        return entry.appName
    }

    private static func isPinned(_ entry: RawItem) -> Bool {
        guard HostedItems.hosts.contains(entry.owner) else { return false }
        let identifier = (entry.identifier ?? "").lowercased()
        return identifier.hasSuffix(".clock") || identifier.hasSuffix(".controlcenter") || identifier == "clock"
    }
}
