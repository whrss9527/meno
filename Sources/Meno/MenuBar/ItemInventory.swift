import AppKit
import Combine
import MenoCore

/// The list of menu bar items, refreshed by scanning.
///
/// Sections come from each item's position relative to Meno's dividers.
/// While the stepped engine (macOS 27) pushes items into the system overflow
/// their positions are unreliable, so the last reliable result is kept.
@MainActor
final class ItemInventory: ObservableObject {
    unowned let model: AppModel

    @Published private(set) var items: [MenuBarItem] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false

    private var cachedSections: [MenuItemKey: ItemSection] = [:]
    private var cachedPositions: [MenuItemKey: CGFloat] = [:]
    private var knownKeys: Set<String>?
    /// Items that were missing from the last scan but kept.
    private var missingOnce: Set<MenuItemKey> = []
    private var refreshTask: Task<Void, Never>?
    private var scheduledTask: Task<Void, Never>?
    private var refreshAgain = false

    init(model: AppModel) {
        self.model = model
        knownKeys = model.storage.loadKnownItems()
    }

    // MARK: - Queries

    func items(in section: ItemSection) -> [MenuBarItem] {
        items.filter { $0.section == section }
    }

    func item(for key: MenuItemKey) -> MenuBarItem? {
        items.first { $0.key == key }
    }

    var sections: [MenuItemKey: ItemSection] {
        Dictionary(items.map { ($0.key, $0.section) }, uniquingKeysWith: { first, _ in first })
    }

    var movableKeys: Set<MenuItemKey> {
        Set(items.filter(\.isMovable).map(\.key))
    }

    /// The current arrangement of movable items.
    func currentLayout() -> SceneLayout {
        var layout = SceneLayout()
        for item in items where item.isMovable {
            layout[item.section].append(item.key)
        }
        return layout
    }

    /// Items and Meno's dividers in left-to-right order, for planning moves.
    func layoutTokens() -> [LayoutToken] {
        var entries: [(x: CGFloat, token: LayoutToken)] = items.map { ($0.frame.midX, $0.layoutToken) }
        if let hidden = model.statusBar.hiddenDividerFrame {
            entries.append((hidden.midX, LayoutPlanner.hiddenDivider))
        }
        if let stash = model.statusBar.stashDividerFrame {
            entries.append((stash.midX, LayoutPlanner.stashDivider))
        }
        if let toggle = model.statusBar.toggleFrame {
            entries.append((toggle.midX, .anchor("meno.toggle")))
        }
        return entries.sorted { $0.x < $1.x }.map(\.token)
    }

    // MARK: - Refreshing

    /// Refreshes soon, coalescing bursts of requests.
    func scheduleRefresh(after delay: TimeInterval = 0.4) {
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Scans the menu bar now. Concurrent calls wait for one extra pass.
    func refresh() async {
        if let refreshTask {
            refreshAgain = true
            await refreshTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.refreshAgain = false
                await self.performRefresh()
            } while self.refreshAgain
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        guard model.permissions.accessibility else {
            if !items.isEmpty { items = model.markers.inventoryItems(sections: [:]) }
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let raw = await MenuBarScanner.scan(MenuBarScanner.currentTargets())
        let built = keepingBriefAbsences(build(from: raw))
        if built != items {
            items = built
        }
        lastRefresh = Date()
        model.statusBar.ensureDividerOrder()
        model.statusBar.refreshAppearance()
        detectNewArrivals()
        model.images.refresh(for: items, captureAllowed: model.permissions.screenRecording)
    }

    private var framesAreReliable: Bool {
        let state = model.statusBar.state
        switch model.statusBar.engine {
        case .wide:
            return true
        case .stepped:
            return !state.hiddenCollapsed && !state.stashCollapsed && !state.zen
        }
    }

    /// A busy app can miss the scan's timeout, which would make its items
    /// vanish for one scan. Items of running apps are dropped only when they
    /// are missing twice in a row.
    private func keepingBriefAbsences(_ built: [MenuBarItem]) -> [MenuBarItem] {
        let present = Set(built.map(\.key))
        var kept: [MenuBarItem] = []
        var missing: Set<MenuItemKey> = []
        for item in items where item.kind != .marker && !present.contains(item.key) && !missingOnce.contains(item.key) {
            guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else { continue }
            kept.append(item)
            missing.insert(item.key)
        }
        missingOnce = missing
        guard !kept.isEmpty else { return built }
        return (built + kept).sorted { $0.frame.minX < $1.frame.minX }
    }

    private func build(from raw: [RawMenuBarItem]) -> [MenuBarItem] {
        let reliable = framesAreReliable
        let dividers = model.statusBar.dividerLayout
        let menoFrames = [model.statusBar.hiddenDividerFrame, model.statusBar.stashDividerFrame, model.statusBar.toggleFrame]
            .compactMap { $0 }
        var result: [MenuBarItem] = []

        let grouped = Dictionary(grouping: raw) { $0.target.bundleID ?? $0.target.name }
        for (owner, group) in grouped {
            let sorted = group.sorted { $0.frame.minX < $1.frame.minX }
            let tokens = MenuItemKey.tokens(for: sorted.map {
                MenuItemKey.Attributes(identifier: $0.identifier, description: $0.detail, title: $0.title)
            })
            for (entry, token) in zip(sorted, tokens) {
                let key = MenuItemKey(owner: owner, token: token)
                let isSystem = owner.hasPrefix("com.apple.")
                let name = Self.displayName(for: entry, siblings: sorted.count, isSystem: isSystem)
                var frame = entry.frame
                var section = ItemSection.visible
                let trustworthy = (reliable || isOnScreen(frame)) && !Self.overlaps(frame, menoFrames)
                if trustworthy, let dividers {
                    section = SectionResolver.section(of: HorizontalSpan(minX: Double(frame.minX), maxX: Double(frame.maxX)), dividers: dividers)
                    cachedSections[key] = section
                    cachedPositions[key] = frame.minX
                } else {
                    section = cachedSections[key] ?? .hidden
                    if let x = cachedPositions[key] {
                        frame.origin.x = x
                    }
                }
                result.append(MenuBarItem(
                    key: key,
                    kind: isSystem ? .system : .app,
                    pid: entry.target.pid,
                    bundleID: entry.target.bundleID,
                    appName: entry.target.name,
                    displayName: name,
                    detail: entry.detail,
                    identifier: entry.identifier,
                    frame: frame,
                    section: section,
                    isMovable: !Self.isPinned(entry, owner: owner),
                    element: entry.element,
                    keywords: Self.keywords(for: name, appName: entry.target.name, bundleID: entry.target.bundleID, identifier: entry.identifier),
                    markerID: nil
                ))
            }
        }

        var markerSections: [UUID: ItemSection] = [:]
        if let dividers {
            for (id, frame) in model.markers.frames() {
                markerSections[id] = SectionResolver.section(of: HorizontalSpan(minX: Double(frame.minX), maxX: Double(frame.maxX)), dividers: dividers)
            }
        }
        result += model.markers.inventoryItems(sections: markerSections)
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Items never overlap Meno's own items. One reported inside a divider
    /// still has its position from before the divider grew over it.
    static func overlaps(_ frame: CGRect, _ menoFrames: [CGRect]) -> Bool {
        menoFrames.contains { $0.minX < frame.midX && frame.midX < $0.maxX }
    }

    private func isOnScreen(_ frame: CGRect) -> Bool {
        guard frame.width > 0 else { return false }
        return NSScreen.screens.contains { screen in
            ScreenGeometry.quartzRect(fromCocoa: screen.frame).contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    // MARK: - New arrivals

    private func detectNewArrivals() {
        let current = Set(items.filter { $0.kind != .marker }.map(\.key.rawValue))
        guard var known = knownKeys else {
            // First scan ever: everything that exists now is already known.
            knownKeys = current
            model.storage.saveKnownItems(current)
            return
        }
        let arrivals = items.filter { $0.kind == .app && !known.contains($0.key.rawValue) }
        known.formUnion(current)
        knownKeys = known
        model.storage.saveKnownItems(known)
        for item in arrivals {
            model.handleNewArrival(item)
        }
    }

    func forgetKnownItems() {
        knownKeys = nil
        model.storage.saveKnownItems([])
    }

    // MARK: - Naming

    static func displayName(for entry: RawMenuBarItem, siblings: Int, isSystem: Bool) -> String {
        let text = [entry.detail, entry.title, entry.help]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if isSystem {
            return text ?? entry.target.name
        }
        if siblings > 1, let text, text.caseInsensitiveCompare(entry.target.name) != .orderedSame {
            return "\(entry.target.name) – \(text)"
        }
        return entry.target.name
    }

    /// The clock and the Control Center icon cannot be moved.
    static func isPinned(_ entry: RawMenuBarItem, owner: String) -> Bool {
        guard owner == "com.apple.controlcenter" || owner == "com.apple.systemuiserver" else { return false }
        let identifier = (entry.identifier ?? "").lowercased()
        return identifier.hasSuffix(".clock") || identifier.hasSuffix(".controlcenter") || identifier == "clock"
    }

    static func keywords(for name: String, appName: String, bundleID: String?, identifier: String?) -> [String] {
        var words: [String] = []
        for text in [name, appName] {
            if let latin = romanized(text) {
                words.append(latin)
                words.append(FuzzyMatcher.initials(of: latin))
            }
        }
        if let bundleID { words.append(bundleID) }
        if let identifier { words.append(identifier) }
        return Array(Set(words)).sorted()
    }

    /// A Latin transcription (for example pinyin) for names in other scripts.
    static func romanized(_ text: String) -> String? {
        guard text.unicodeScalars.contains(where: { $0.value > 0x2E7F }) else { return nil }
        guard let latin = text.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) else { return nil }
        return latin == text ? nil : latin
    }
}
