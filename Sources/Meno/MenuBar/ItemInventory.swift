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
    /// When the scan behind `items` began. Their positions are from then.
    private(set) var scannedAt: Date?
    /// Elements left out of the last scan, for the diagnostic report.
    private(set) var skipped = SkippedElements()

    typealias SkippedElements = InventoryBuilder.SkippedElements
    private var cached = InventoryBuilder.Cache()
    private var scanGate = MenuBarScanGate()
    private(set) var fullScans = 0
    private(set) var skippedScans = 0
    // Diagnostic comparison mode, leaving ordinary refreshes unchanged.
    private let usesScanGate = AppInfo.osMajorVersion < 27
        && ProcessInfo.processInfo.environment["MENO_SCAN_GATE"] != "0"

    private var knownItems: KnownItems?
    /// Items whose section the last scan could tell from their position.
    private var reliablySectioned: Set<MenuItemKey> = []
    /// Items that were missing from the last scan but kept.
    private var missingOnce: Set<MenuItemKey> = []
    private var refreshTask: Task<Void, Never>?
    private var scheduledTask: Task<Void, Never>?
    private var refreshAgain = false

    init(model: AppModel) {
        self.model = model
        knownItems = model.storage.loadKnownItems()
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

    /// Periodic catch-up may reuse a stable menu bar on macOS 26 and earlier.
    func refreshPeriodically() async {
        if usesScanGate, model.permissions.accessibility, refreshTask == nil,
           missingOnce.isEmpty, model.statusBar.isInOrder,
           !scanGate.needsScan(WindowCapture.menuBarFingerprint()) {
            refreshDependentState(sectioned: true, validatedAt: Date())
            skippedScans += 1
            Diagnostics.event("scan mode=skipped items=\(items.count) full=\(fullScans) skipped=\(skippedScans) footprint_kb=\(Diagnostics.physicalFootprint ?? 0)")
            return
        }
        await refresh()
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
            // Cleared here, not by the caller, so that a request arriving
            // after the last pass starts a new scan.
            self.refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        guard model.permissions.accessibility else {
            if !items.isEmpty { items = model.markers.inventoryItems(sections: [:]) }
            Diagnostics.event("scan accessibility=missing footprint_kb=\(Diagnostics.physicalFootprint ?? 0)")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let fingerprint = usesScanGate ? WindowCapture.menuBarFingerprint() : nil
        let started = Date()
        let raw = await MenuBarScanner.scan(MenuBarScanner.currentTargets())
        // Sections come from where items are next to Meno's dividers, which
        // macOS may not have placed yet right after launch.
        let sectioned = model.statusBar.isInOrder
        let built = keepingBriefAbsences(build(from: raw))
        if built != items {
            items = built
        }
        scannedAt = started
        lastRefresh = Date()
        refreshDependentState(sectioned: sectioned)
        fullScans += 1
        if usesScanGate {
            // An empty or partially unresolved AX result must be retried even
            // when the windows have settled, especially just after launch.
            let reusable = sectioned && !reliablySectioned.isEmpty
                && items.allSatisfy { $0.kind == .marker || knowsSection(of: $0.key) }
            scanGate.scanned(before: reusable ? fingerprint : nil, after: WindowCapture.menuBarFingerprint())
        }
        Diagnostics.event("scan mode=full items=\(items.count) ms=\(Int(Date().timeIntervalSince(started) * 1000))"
            + " full=\(fullScans) skipped=\(skippedScans) sectioned=\(sectioned ? 1 : 0) footprint_kb=\(Diagnostics.physicalFootprint ?? 0)")
    }

    /// A reused window snapshot is still an observation for settling, retries
    /// and visible artwork; only the cross-process Accessibility query is skipped.
    private func refreshDependentState(sectioned: Bool, validatedAt: Date? = nil) {
        model.statusBar.ensureDividerOrder()
        model.statusBar.refreshAppearance()
        model.statusBar.refreshGroupTooltips()
        if sectioned {
            detectNewArrivals()
            model.statusBar.checkHiding(items)
        }
        model.keeper.scanned(keeperObservations(), validatedAt: validatedAt)
        // Capture only while artwork is visible, as for a full scan.
        if model.showsItemArtwork {
            model.images.refresh(for: items, captureAllowed: model.permissions.canCapture)
        }
    }

    /// Whether the last scan could tell the item's section from its
    /// position, rather than going by an earlier scan.
    func knowsSection(of key: MenuItemKey) -> Bool {
        reliablySectioned.contains(key) && !missingOnce.contains(key)
    }

    /// The movable items, for keeping them in their sections. Where an item
    /// kept from an earlier scan is now is not known.
    private func keeperObservations() -> [SectionKeeper.Observation] {
        items.filter { $0.kind != .marker && $0.isMovable }.map { item in
            SectionKeeper.Observation(key: item.key, section: knowsSection(of: item.key) ? item.section : nil, process: item.pid)
        }
    }

    /// Whether item positions reflect the menu bar right now. While the
    /// stepped engine hides items, their positions are not reported.
    var framesAreReliable: Bool {
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
        let dividers = model.statusBar.dividerLayout
        let rawValues = raw.map { entry in
            InventoryBuilder.RawItem(
                owner: entry.target.bundleID ?? entry.target.name,
                appName: entry.target.name, frame: entry.frame,
                identifier: entry.identifier, detail: entry.detail,
                title: entry.title, help: entry.help,
                isOnScreen: isOnScreen(entry.frame),
                isWithinScreenWidth: isWithinScreenWidth(entry.frame)
            )
        }
        let built = InventoryBuilder.build(
            raw: rawValues,
            dividers: .init(layout: dividers, ownFrames: model.statusBar.ownFrames, framesAreReliable: framesAreReliable),
            cached: cached
        )
        cached = built.cached
        skipped = built.skipped
        reliablySectioned = built.reliablySectioned
        var result = built.items.map { item in
            let entry = raw[item.sourceIndex]
            let customName = model.settings.itemNames[item.key.rawValue]
            return MenuBarItem(
                key: item.key, kind: item.isSystem ? .system : .app,
                pid: entry.target.pid, bundleID: entry.target.bundleID,
                appName: entry.target.name, displayName: customName ?? item.displayName,
                detail: entry.detail, identifier: entry.identifier,
                frame: item.frame, section: item.section, isMovable: item.isMovable,
                element: entry.element,
                keywords: Self.keywords(
                    for: [customName, item.displayName].compactMap { $0 },
                    appName: entry.target.name, bundleID: entry.target.bundleID,
                    identifier: entry.identifier
                ), markerID: nil
            )
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

    /// A zero-width slot on any screen is a leftover only with reliable frames.
    private func isWithinScreenWidth(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            let bounds = ScreenGeometry.quartzRect(fromCocoa: screen.frame)
            return bounds.minX <= frame.midX && frame.midX <= bounds.maxX
        }
    }

    private func isOnScreen(_ frame: CGRect) -> Bool {
        guard frame.width > 0 else { return false }
        return NSScreen.screens.contains { screen in
            ScreenGeometry.quartzRect(fromCocoa: screen.frame).contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    // MARK: - New arrivals

    private func detectNewArrivals() {
        let scan = items.filter { $0.kind != .marker }
        // The first scan ever finds everything already known.
        let isFirst = knownItems == nil
        var known = knownItems ?? KnownItems()
        let arrivals = Set(known.arrivals(in: scan.map(\.key)))
        guard known != knownItems else { return }
        knownItems = known
        model.storage.saveKnownItems(known)
        guard !isFirst else { return }
        for item in scan where item.kind == .app && arrivals.contains(item.key) {
            model.handleNewArrival(item)
        }
    }

    func forgetKnownItems() {
        knownItems = nil
        model.storage.saveKnownItems(nil)
    }

    // MARK: - Naming

    static func keywords(for names: [String], appName: String, bundleID: String?, identifier: String?) -> [String] {
        // The first name is shown; the others stay searchable.
        var words = Array(names.dropFirst())
        for text in names + [appName] {
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
    nonisolated static func romanized(_ text: String) -> String? {
        guard text.unicodeScalars.contains(where: { $0.value > 0x2E7F }) else { return nil }
        guard let latin = text.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) else { return nil }
        return latin == text ? nil : latin
    }
}
