import AppKit
import MenoCore

/// Which dividers are grown.
struct BarState: Equatable {
    /// Items left of the Hidden divider are pushed away.
    var hiddenCollapsed = false
    /// Items left of the Stash divider are pushed away.
    var stashCollapsed = false
    /// Zen: everything left of the Meno icon is pushed away.
    var zen = false
}

/// Owns Meno's status items: the Meno icon, the section dividers and the
/// helper spacers of the stepped engine.
///
/// Dividers hide the items to their left by growing. With the wide engine a
/// single divider grows far past the screen edge. With the stepped engine
/// (macOS 27 and later) the divider and a few spacers next to it each grow to
/// just under half of the narrowest display, in small steps, because larger
/// items are dropped from the menu bar there.
@MainActor
final class StatusBarController: NSObject {
    enum Name {
        static let toggle = "meno.toggle"
        static let hiddenDivider = "meno.divider.hidden"
        static let stashDivider = "meno.divider.stash"

        static func spacer(_ group: SpacerGroup, _ index: Int) -> String {
            "meno.spacer.\(group.rawValue).\(index)"
        }

        static func group(_ id: UUID) -> String {
            "meno.group.\(id.uuidString)"
        }
    }

    enum SpacerGroup: String, CaseIterable {
        case hidden
        case stash
        case zen
    }

    unowned let model: AppModel

    private(set) var toggle: NSStatusItem?
    var hiddenDivider: NSStatusItem?
    var stashDivider: NSStatusItem?
    private var spacers: [SpacerGroup: [NSStatusItem]] = [:]
    /// The icons of item groups.
    private var groupItems: [UUID: NSStatusItem] = [:]
    private(set) var state = BarState()
    private var applyTask: Task<Void, Never>?
    private var zenGlyphView: NSImageView?
    private var dividersForcedVisible = false
    private var orderRepairs = 0
    private var orderHintShown = false
    /// The display whose menu bar had the items when last looked at.
    private var menuBarDisplay: CGDirectDisplayID?
    /// When Meno's items were first seen out of order, until they are in
    /// order again.
    private var outOfOrderSince: Date?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var engine: ResolvedHidingEngine {
        model.settings.general.hidingEngine.resolved(osMajorVersion: AppInfo.osMajorVersion)
    }

    // MARK: - Setup

    func install() {
        // On the very first launch macOS inserts new items at the left end of
        // the status area, so creating the icon first puts the dividers to
        // its left.
        toggle = makeItem(name: Name.toggle, action: #selector(toggleClicked(_:)))
        hiddenDivider = makeItem(name: Name.hiddenDivider, action: #selector(dividerClicked(_:)))
        syncStashDivider()
        refreshAppearance()
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didMoveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(itemWindowMoved(_:)), name: name, object: nil)
        }
        menuBarDisplay = screen.flatMap(ScreenGeometry.displayID(of:))
    }

    /// Rules can depend on the display whose menu bar has the items, which
    /// changes as the person moves to another display.
    @objc private func itemWindowMoved(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === toggle?.button?.window || window === hiddenDivider?.button?.window else { return }
        let display = screen.flatMap(ScreenGeometry.displayID(of:))
        guard display != menuBarDisplay else { return }
        menuBarDisplay = display
        model.automation.evaluate()
    }

    /// Adds or removes the Stash divider to match the settings.
    func syncStashDivider() {
        if model.settings.general.stashEnabled {
            guard stashDivider == nil else { return }
            stashDivider = makeItem(name: Name.stashDivider, action: #selector(dividerClicked(_:)))
        } else if let divider = stashDivider {
            removeSpacers(.stash)
            NSStatusBar.system.removeStatusItem(divider)
            stashDivider = nil
        }
        apply(state)
    }

    // MARK: - Groups

    /// Adds, updates and removes the icons of item groups to match the
    /// settings.
    func syncGroups() {
        let groups = model.settings.groups
        let ids = Set(groups.map(\.id))
        for (id, item) in groupItems where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            UserDefaults.standard.removeObject(forKey: Self.positionKey(Name.group(id)))
            groupItems[id] = nil
        }
        for group in groups {
            let item = groupItems[group.id] ?? makeGroupItem(for: group)
            groupItems[group.id] = item
            let image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: group.name)
                ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: group.name)
            image?.isTemplate = true
            item.button?.image = image
            item.button?.setAccessibilityLabel(group.name)
        }
        refreshGroupTooltips()
    }

    /// Names the group and its items in each group icon's tooltip.
    func refreshGroupTooltips() {
        for group in model.settings.groups {
            let names = group.items.compactMap { model.inventory.item(for: $0)?.displayName }
            groupItems[group.id]?.button?.toolTip = names.isEmpty ? group.name : group.name + "\n" + names.joined(separator: ", ")
        }
    }

    /// Where a group's icon is, in Cocoa coordinates, for placing its Shelf.
    func groupIconFrame(_ id: UUID) -> NSRect? {
        guard let frame = groupItems[id]?.button?.window?.frame, frame.width > 0 else { return nil }
        return frame
    }

    private func makeGroupItem(for group: ItemGroup) -> NSStatusItem {
        let name = Name.group(group.id)
        // A new group's icon starts right next to the Meno icon, on its
        // visible side. Positions grow to the left, so a value just above the
        // Meno icon's puts it between the icon and whatever is left of it,
        // such as the Hidden divider.
        if Self.preferredPosition(of: name) == nil, let base = Self.preferredPosition(of: Name.toggle) {
            UserDefaults.standard.set(base + 1 + Double(groupItems.count), forKey: Self.positionKey(name))
        }
        return makeItem(name: name, action: #selector(groupClicked(_:)))
    }

    @objc private func groupClicked(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton,
              let entry = groupItems.first(where: { $0.value.button === button }) else { return }
        if clickIsSecondary {
            entry.value.menu = groupMenu(entry.key)
            button.performClick(nil)
            entry.value.menu = nil
            return
        }
        model.shelf.toggle(group: entry.key)
    }

    /// The group's items, to open one without the Shelf.
    private func groupMenu(_ id: UUID) -> NSMenu {
        let menu = NSMenu()
        let group = model.settings.groups.first { $0.id == id }
        for key in group?.items ?? [] {
            guard let item = model.inventory.item(for: key) else { continue }
            let handler = MenuActionHandler { [weak model = self.model] in
                Task { await model?.activator.open(item, source: .shelf) }
            }
            let entry = NSMenuItem(title: item.displayName, action: #selector(MenuActionHandler.invoke), keyEquivalent: "")
            entry.target = handler
            entry.representedObject = handler
            menu.addItem(entry)
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let handler = MenuActionHandler { [weak model = self.model] in
            model?.openSettings(.layout)
        }
        let edit = NSMenuItem(title: String(localized: "Edit Groups…"), action: #selector(MenuActionHandler.invoke), keyEquivalent: "")
        edit.target = handler
        edit.representedObject = handler
        menu.addItem(edit)
        return menu
    }

    func uninstall() {
        applyTask?.cancel()
        for group in SpacerGroup.allCases { removeSpacers(group) }
        for item in [toggle, hiddenDivider, stashDivider].compactMap({ $0 }) + Array(groupItems.values) {
            NSStatusBar.system.removeStatusItem(item)
        }
        groupItems = [:]
        toggle = nil
        hiddenDivider = nil
        stashDivider = nil
    }

    /// Whether the dividers sit left of the Meno icon, and the Stash divider
    /// left of the Hidden divider. Right after launch macOS may not have
    /// placed them yet, and where their windows are then says otherwise.
    var isInOrder: Bool {
        guard let hiddenFrame = hiddenDividerFrame else { return false }
        // Without the Meno icon its item has no width and no frame, but the
        // Stash divider is still checked.
        if toggle != nil, let toggleFrame, hiddenFrame.maxX > toggleFrame.maxX { return false }
        if let stashFrame = stashDividerFrame, stashFrame.maxX > hiddenFrame.maxX { return false }
        return true
    }

    /// Makes sure the dividers stay in order. Otherwise collapsing would push
    /// the Meno icon itself out of the menu bar.
    func ensureDividerOrder() {
        guard let hiddenFrame = hiddenDividerFrame else { return }
        guard !isInOrder else {
            outOfOrderSince = nil
            return
        }
        // Only an order that lasts is repaired, not one of items that macOS
        // is still placing; a scan soon tells.
        let now = Date()
        guard let since = outOfOrderSince, now.timeIntervalSince(since) >= 1 else {
            if outOfOrderSince == nil {
                outOfOrderSince = now
            }
            model.inventory.scheduleRefresh(after: 1.5)
            return
        }
        let repaired: Bool
        if let toggle, let toggleFrame, hiddenFrame.maxX > toggleFrame.maxX {
            repaired = reseat(\.hiddenDivider, name: Name.hiddenDivider, leftOf: Name.toggle, item: toggle)
        } else if let hiddenDivider {
            repaired = reseat(\.stashDivider, name: Name.stashDivider, leftOf: Name.hiddenDivider, item: hiddenDivider)
        } else {
            return
        }
        if repaired {
            // The new divider gets a moment of its own to be placed.
            outOfOrderSince = nil
            apply(state)
            model.inventory.scheduleRefresh(after: 1.5)
        } else if !orderHintShown {
            orderHintShown = true
            model.toasts.show(
                String(localized: "Hold ⌘ and drag Meno's dividers to the left of the Meno icon."),
                symbol: "exclamationmark.triangle.fill",
                duration: 8
            )
        }
    }

    /// Recreates a divider right next to (left of) another item, using the
    /// position macOS stored for that item.
    private func reseat(
        _ keyPath: ReferenceWritableKeyPath<StatusBarController, NSStatusItem?>,
        name: String,
        leftOf reference: String,
        item: NSStatusItem
    ) -> Bool {
        guard orderRepairs < 2, let base = Self.preferredPosition(of: reference) else { return false }
        orderRepairs += 1
        Log.menuBar.info("Moving \(name, privacy: .public) back next to \(reference, privacy: .public)")
        if let old = self[keyPath: keyPath] {
            NSStatusBar.system.removeStatusItem(old)
        }
        // The stepped engine's spacers belong next to the divider, so they
        // are made again where it goes.
        removeSpacers(name == Name.stashDivider ? .stash : .hidden)
        let width = Double(item.button?.window?.frame.width ?? 20)
        UserDefaults.standard.set(base + max(width / 2, 4), forKey: Self.positionKey(name))
        let replacement = makeItem(name: name, action: #selector(dividerClicked(_:)))
        self[keyPath: keyPath] = replacement
        return true
    }

    private func makeItem(name: String, action: Selector) -> NSStatusItem {
        UserDefaults.standard.removeObject(forKey: Self.visibilityKey(name))
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        item.isVisible = true
        if let button = item.button {
            button.target = self
            button.action = action
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(Self.accessibilityLabel(for: name))
        }
        return item
    }

    private static func accessibilityLabel(for name: String) -> String? {
        switch name {
        case Name.toggle: return "Meno"
        case Name.hiddenDivider: return String(localized: "Hidden section divider")
        case Name.stashDivider: return String(localized: "Stash section divider")
        default: return nil
        }
    }

    // MARK: - State

    func apply(_ newState: BarState) {
        state = newState
        applyTask?.cancel()
        applyTask = nil
        switch engine {
        case .wide:
            applyWide()
        case .stepped:
            applyTask = Task { [weak self] in
                await self?.applyStepped()
            }
        }
        refreshAppearance()
    }

    /// Re-applies the current state, for example after the screens changed.
    func reapply() {
        apply(state)
    }

    /// Shows the dividers even if the user hid them, so that items can be
    /// dropped next to them while moving.
    func setDividersForcedVisible(_ visible: Bool) {
        guard dividersForcedVisible != visible else { return }
        dividersForcedVisible = visible
        apply(state)
    }

    private var expandedDividerLength: CGFloat {
        model.settings.appearance.showsDividers || dividersForcedVisible ? NSStatusItem.variableLength : 0
    }

    private var zenPushesVisibleItems: Bool {
        state.zen && model.settings.zen.hidesVisibleItems
    }

    /// Without the Meno icon, its item stays in place with no width, so
    /// Zen can still grow it and the dividers keep their order.
    private var toggleLength: CGFloat {
        model.settings.appearance.showsMenoIcon ? NSStatusItem.variableLength : 0
    }

    private func applyWide() {
        for group in SpacerGroup.allCases { removeSpacers(group) }
        let wide = CGFloat(CollapseMetrics.wideLength(
            screenWidths: ScreenGeometry.screenWidths,
            horizontalSpan: ScreenGeometry.horizontalSpan
        ))
        hiddenDivider?.length = state.hiddenCollapsed ? wide : expandedDividerLength
        stashDivider?.length = state.stashCollapsed ? wide : expandedDividerLength
        toggle?.length = zenPushesVisibleItems ? wide : toggleLength
    }

    private func applyStepped() async {
        let widths = ScreenGeometry.screenWidths
        let unit = CGFloat(CollapseMetrics.steppedUnit(screenWidths: widths))
        let count = CollapseMetrics.steppedSpacerCount(screenWidths: widths)

        // Shrinking is instant.
        if !state.hiddenCollapsed {
            removeSpacers(.hidden)
            hiddenDivider?.length = expandedDividerLength
        }
        if !state.stashCollapsed {
            removeSpacers(.stash)
            stashDivider?.length = expandedDividerLength
        }
        if !zenPushesVisibleItems {
            removeSpacers(.zen)
            toggle?.length = toggleLength
        }

        // Growing happens in small steps so the neighbours are carried along.
        var growing: [NSStatusItem] = []
        if state.hiddenCollapsed, let divider = hiddenDivider {
            growing.append(divider)
            growing += ensureSpacers(.hidden, count: count, next: Name.hiddenDivider, item: divider, onLeft: false)
        }
        if state.stashCollapsed, let divider = stashDivider {
            growing.append(divider)
            growing += ensureSpacers(.stash, count: count, next: Name.stashDivider, item: divider, onLeft: false)
        }
        if zenPushesVisibleItems, let toggle {
            growing.append(toggle)
            growing += ensureSpacers(.zen, count: count, next: Name.toggle, item: toggle, onLeft: true)
        }
        await ramp(growing, to: unit)
    }

    private func ramp(_ items: [NSStatusItem], to target: CGFloat) async {
        guard !items.isEmpty else { return }
        // Longer items (left by the wide engine or a wider screen) would be
        // dropped from the menu bar, so they shrink at once.
        for item in items where item.length > target {
            item.length = target
        }
        var lengths = items.map { max($0.length, 0) }
        let increment = CGFloat(CollapseMetrics.steppedIncrement)
        while lengths.contains(where: { $0 < target }) {
            if Task.isCancelled { return }
            for index in items.indices where lengths[index] < target {
                lengths[index] = min(lengths[index] + increment, target)
                items[index].length = lengths[index]
            }
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
    }

    /// Creates helper spacers right next to `name`: on its right for
    /// dividers (between the divider and the items that stay visible) or on
    /// its left for the Meno icon (Zen).
    private func ensureSpacers(
        _ group: SpacerGroup,
        count: Int,
        next name: String,
        item: NSStatusItem,
        onLeft: Bool
    ) -> [NSStatusItem] {
        if let existing = spacers[group], existing.count == count {
            return existing
        }
        removeSpacers(group)
        let base = Self.preferredPosition(of: name) ?? estimatedPosition(of: item)
        let positions: [Double]
        if onLeft {
            positions = (1...max(count, 1)).map { base + 0.3 * Double($0) }
        } else {
            positions = CollapseMetrics.positionsRight(of: base, count: count)
        }
        var created: [NSStatusItem] = []
        for (index, position) in positions.enumerated() {
            let spacerName = Name.spacer(group, index)
            UserDefaults.standard.set(position, forKey: Self.positionKey(spacerName))
            UserDefaults.standard.removeObject(forKey: Self.visibilityKey(spacerName))
            let spacer = NSStatusBar.system.statusItem(withLength: 0)
            spacer.autosaveName = spacerName
            spacer.isVisible = true
            if let button = spacer.button {
                button.target = self
                button.action = #selector(dividerClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.image = nil
                button.title = ""
            }
            created.append(spacer)
        }
        spacers[group] = created
        return created
    }

    private func removeSpacers(_ group: SpacerGroup) {
        guard let items = spacers[group] else { return }
        for item in items {
            NSStatusBar.system.removeStatusItem(item)
        }
        spacers[group] = nil
    }

    // MARK: - Appearance

    func refreshAppearance() {
        let appearance = model.settings.appearance
        if let button = toggle?.button {
            if !appearance.showsMenoIcon && !zenPushesVisibleItems {
                button.image = nil
            } else if state.zen {
                button.image = zenPushesVisibleItems ? nil : MenoIconRenderer.zenGlyph()
            } else {
                button.image = MenoIconRenderer.toggleImage(for: appearance, revealed: !state.hiddenCollapsed)
            }
            updateBadge(on: button)
            var toolTip = state.zen
                ? String(localized: "Zen is on. Click to leave Zen.")
                : String(localized: "Meno — click to show or hide items, ⌥-click to include the Stash, right-click for more")
            let changed = changedItemNames
            if !changed.isEmpty {
                toolTip += "\n" + String(localized: "Changed: \(ListFormatter.localizedString(byJoining: changed))")
            }
            button.toolTip = toolTip
            setChangeDot(on: button, visible: !changed.isEmpty)
        }
        // A group's icon is marked when one of its items changed.
        for group in model.settings.groups {
            guard let button = groupItems[group.id]?.button else { continue }
            setChangeDot(on: button, visible: !model.changes.changedItems.isDisjoint(with: group.items))
        }
        updateZenGlyph()
        if let button = hiddenDivider?.button {
            button.image = state.hiddenCollapsed ? nil : MenoIconRenderer.dividerImage(appearance.dividerGlyph, double: false)
            button.toolTip = String(localized: "Items left of this divider are hidden")
        }
        if let button = stashDivider?.button {
            button.image = state.stashCollapsed ? nil : MenoIconRenderer.dividerImage(appearance.dividerGlyph, double: true)
            button.toolTip = String(localized: "Items left of this divider go to the Stash")
        }
    }

    /// Names of watched hidden items that changed unseen, while the icon
    /// can show them.
    private var changedItemNames: [String] {
        guard model.settings.appearance.showsMenoIcon, state.hiddenCollapsed, !state.zen else { return [] }
        return model.changes.changedItems.sorted().map { key in
            model.inventory.item(for: key)?.displayName ?? key.owner
        }
    }

    private static let changeDotID = NSUserInterfaceItemIdentifier("meno.changeDot")

    /// Puts a dot on an icon while items behind it changed unseen.
    private func setChangeDot(on button: NSStatusBarButton, visible: Bool) {
        let existing = button.subviews.first { $0.identifier == Self.changeDotID }
        guard visible else {
            if existing != nil {
                existing?.removeFromSuperview()
                button.setAccessibilityValue(nil)
            }
            return
        }
        let size: CGFloat = 6
        let dot = existing ?? NSView()
        dot.identifier = Self.changeDotID
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dot.layer?.cornerRadius = size / 2
        let top = button.isFlipped ? 3 : button.bounds.height - 3 - size
        dot.frame = NSRect(x: max(button.bounds.width - size - 2, 0), y: top, width: size, height: size)
        dot.autoresizingMask = button.isFlipped ? [.minXMargin, .maxYMargin] : [.minXMargin, .minYMargin]
        if dot.superview == nil {
            button.addSubview(dot)
        }
        button.setAccessibilityValue(String(localized: "Items changed"))
    }

    private func updateBadge(on button: NSStatusBarButton) {
        let count = model.inventory.items(in: .hidden).count
        if model.settings.general.showsHiddenCount, model.settings.appearance.showsMenoIcon,
           state.hiddenCollapsed, !state.zen, count > 0 {
            button.title = "\(count)"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    /// While Zen grows the Meno icon, its glyph is pinned to the right edge
    /// so it stays visible next to the system items.
    private func updateZenGlyph() {
        guard let button = toggle?.button else { return }
        guard zenPushesVisibleItems else {
            zenGlyphView?.removeFromSuperview()
            zenGlyphView = nil
            return
        }
        let view = zenGlyphView ?? NSImageView()
        view.image = MenoIconRenderer.zenGlyph()
        view.imageScaling = .scaleNone
        view.autoresizingMask = [.minXMargin, .height]
        let width: CGFloat = 24
        view.frame = NSRect(x: max(button.bounds.width - width, 0), y: 0, width: width, height: button.bounds.height)
        if view.superview == nil {
            button.addSubview(view)
        }
        zenGlyphView = view
    }

    // MARK: - Geometry

    /// The frame of a status item in Quartz coordinates.
    func frame(of item: NSStatusItem?) -> CGRect? {
        guard let window = item?.button?.window, window.frame.width > 0 else { return nil }
        return ScreenGeometry.quartzRect(fromCocoa: window.frame)
    }

    var toggleFrame: CGRect? { frame(of: toggle) }
    var hiddenDividerFrame: CGRect? { frame(of: hiddenDivider) }
    var stashDividerFrame: CGRect? { frame(of: stashDivider) }

    /// The screen that shows Meno's items. With several displays macOS
    /// keeps the items on the menu bar of the display in use.
    var screen: NSScreen? {
        // The icon has no width while it is hidden.
        let windows = [toggle, hiddenDivider].compactMap { $0?.button?.window }
        guard let window = windows.first(where: { $0.frame.width > 0 }) ?? windows.first else {
            return ScreenGeometry.primaryScreen
        }
        // Zen grows the icon, and a divider grows to hide items, across the
        // screens to their left, so the right end tells where they are.
        let end = NSPoint(x: window.frame.maxX - 1, y: window.frame.midY)
        return ScreenGeometry.screen(containingCocoa: end) ?? window.screen ?? ScreenGeometry.primaryScreen
    }

    /// Where the dividers are, while they are in order, to tell the items'
    /// sections by.
    var dividerLayout: DividerLayout? {
        guard isInOrder, let hidden = hiddenDividerFrame else { return nil }
        let stash = stashDividerFrame.map { HorizontalSpan(minX: Double($0.minX), maxX: Double($0.maxX)) }
        return DividerLayout(hidden: HorizontalSpan(minX: Double(hidden.minX), maxX: Double(hidden.maxX)), stash: stash)
    }

    /// Parts of the menu bar that belong to grown dividers and spacers. They
    /// look empty, so pointing at or clicking them counts as the empty area.
    var emptyAreaFrames: [CGRect] {
        var items: [NSStatusItem] = []
        if state.hiddenCollapsed, let hiddenDivider { items.append(hiddenDivider) }
        items += spacers[.hidden] ?? []
        if zenPushesVisibleItems, let toggle { items.append(toggle) }
        items += spacers[.zen] ?? []
        return items.compactMap { frame(of: $0) }
    }

    /// All of Meno's own status item frames.
    var ownFrames: [CGRect] {
        var items = [toggle, hiddenDivider, stashDivider].compactMap { $0 } + Array(groupItems.values)
        for group in SpacerGroup.allCases { items += spacers[group] ?? [] }
        return items.compactMap { frame(of: $0) }
    }

    private func estimatedPosition(of item: NSStatusItem) -> Double {
        guard let window = item.button?.window else { return 0 }
        let screenMaxX = (window.screen ?? ScreenGeometry.primaryScreen)?.frame.maxX ?? window.frame.maxX
        return max(Double(screenMaxX - window.frame.maxX), 0)
    }

    static func positionKey(_ name: String) -> String {
        "NSStatusItem Preferred Position \(name)"
    }

    static func visibilityKey(_ name: String) -> String {
        "NSStatusItem Visible \(name)"
    }

    static func preferredPosition(of name: String) -> Double? {
        (UserDefaults.standard.object(forKey: positionKey(name)) as? NSNumber)?.doubleValue
    }

    // MARK: - Clicks

    private var clickIsSecondary: Bool {
        guard let event = NSApp.currentEvent else { return false }
        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }

    @objc private func toggleClicked(_ sender: Any?) {
        if clickIsSecondary {
            showMenu()
            return
        }
        if state.zen {
            model.setZen(false)
            return
        }
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            model.reveal.toggleAll(trigger: .click)
        } else {
            model.reveal.primaryClick()
        }
    }

    @objc private func dividerClicked(_ sender: Any?) {
        if clickIsSecondary {
            showMenu()
            return
        }
        if state.zen {
            model.setZen(false)
            return
        }
        model.reveal.emptyAreaClicked()
    }

    /// Shows Meno's menu below the Meno icon, or at the pointer while the
    /// icon is hidden or grown by Zen.
    func showMenu() {
        guard let toggle else { return }
        let menu = model.makeStatusMenu()
        guard model.settings.appearance.showsMenoIcon, toggleFrame != nil, !zenPushesVisibleItems else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }
        toggle.menu = menu
        toggle.button?.performClick(nil)
        toggle.menu = nil
    }
}
