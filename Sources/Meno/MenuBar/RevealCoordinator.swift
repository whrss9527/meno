import AppKit
import MenoCore

/// Which sections are currently shown in the menu bar.
enum SectionVisibility: Equatable {
    case collapsed
    case revealed
    case revealedAll
}

/// What caused a reveal or collapse.
enum RevealTrigger: String {
    case click
    case emptyArea
    case hover
    case scroll
    case hotkey
    case menu
    case activation
    case rule
    case layout
    case launch
    case timer
    case focus
    case pointerExit
    case zen
}

/// Decides when hidden items are shown and hidden again.
@MainActor
final class RevealCoordinator: ObservableObject {
    unowned let model: AppModel

    @Published private(set) var visibility: SectionVisibility = .collapsed

    private var holds = 0
    private var zenLifted = false
    private var layoutSessions = 0
    private var visibilityBeforeLayout: SectionVisibility = .collapsed
    private var revealedByHover = false

    private var rehideTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var pointerExitTask: Task<Void, Never>?

    private var previousApp: NSRunningApplication?
    private var activatedForAppMenus = false
    @Published private(set) var appMenuFrame: CGRect?

    private var scrollAccumulator: CGFloat = 0
    private var lastScroll = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    private lazy var pointerMonitor = GlobalEventMonitor(mask: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
        self?.pointerMoved(event)
    }

    private lazy var clickMonitor = GlobalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
        self?.clickedElsewhere(event)
    }

    private lazy var scrollMonitor = GlobalEventMonitor(mask: [.scrollWheel]) { [weak self] event in
        self?.scrolled(event)
    }

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                self?.applicationActivated(pid: pid)
            }
        })
        settingsChanged()
        refreshAppMenuFrame(for: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        apply()
    }

    func settingsChanged() {
        let reveal = model.settings.reveal
        if reveal.onHover || reveal.rehideOnMouseExit {
            pointerMonitor.start()
        } else {
            pointerMonitor.stop()
        }
        clickMonitor.start()
        if reveal.onScroll {
            scrollMonitor.start()
        } else {
            scrollMonitor.stop()
        }
        apply()
        if visibility != .collapsed {
            scheduleRehide()
        }
    }

    // MARK: - State

    var barState: BarState {
        let zen = model.isZenActive && !zenLifted
        return BarState(
            hiddenCollapsed: zen || visibility == .collapsed,
            stashCollapsed: zen || visibility != .revealedAll,
            zen: zen
        )
    }

    /// Pushes the current state to the status items.
    func apply() {
        model.statusBar.apply(barState)
        model.tint.update()
    }

    var isHolding: Bool { holds > 0 }

    /// Keeps items revealed until ``release()`` is called.
    func hold() {
        holds += 1
        rehideTask?.cancel()
    }

    func release() {
        holds = max(holds - 1, 0)
        if holds == 0 {
            scheduleRehide()
        }
    }

    // MARK: - Commands

    /// The Meno icon was clicked.
    func primaryClick() {
        if visibility == .collapsed {
            requestReveal(all: false, trigger: .click)
        } else {
            collapse(trigger: .click)
        }
    }

    func toggle(trigger: RevealTrigger) {
        if visibility == .collapsed {
            requestReveal(all: false, trigger: trigger)
        } else {
            collapse(trigger: trigger)
        }
    }

    func toggleAll(trigger: RevealTrigger) {
        if visibility == .revealedAll {
            collapse(trigger: trigger)
        } else {
            requestReveal(all: true, trigger: trigger)
        }
    }

    /// An empty part of the menu bar (a grown divider) was clicked.
    func emptyAreaClicked() {
        guard model.settings.reveal.onEmptyAreaClick else { return }
        toggle(trigger: .emptyArea)
    }

    /// Reveals in the menu bar or opens the Shelf, depending on settings.
    func requestReveal(all: Bool, trigger: RevealTrigger) {
        if model.isZenActive {
            let passive: Set<RevealTrigger> = [.hover, .scroll, .emptyArea]
            if model.settings.zen.blocksReveal && passive.contains(trigger) { return }
            model.setZen(false)
        }
        if shouldUseShelf(all: all) {
            model.shelf.show(includeStash: all, trigger: trigger)
        } else {
            reveal(all: all, trigger: trigger)
        }
    }

    /// Reveals in the menu bar.
    func reveal(all: Bool, trigger: RevealTrigger) {
        let wasCollapsed = visibility == .collapsed
        let target: SectionVisibility = all || visibility == .revealedAll ? .revealedAll : .revealed
        guard target != visibility || trigger == .activation else {
            scheduleRehide()
            return
        }
        visibility = target
        revealedByHover = wasCollapsed && trigger == .hover
        apply()
        hideAppMenusIfNeeded(all: target == .revealedAll)
        if wasCollapsed {
            model.recordReveal(trigger: trigger)
        }
        scheduleRehide()
        model.inventory.scheduleRefresh(after: 0.45)
    }

    func collapse(trigger: RevealTrigger) {
        rehideTask?.cancel()
        hoverTask?.cancel()
        hoverTask = nil
        pointerExitTask?.cancel()
        pointerExitTask = nil
        revealedByHover = false
        let changed = visibility != .collapsed
        visibility = .collapsed
        apply()
        restoreAppMenus()
        if changed || trigger == .launch {
            model.inventory.scheduleRefresh(after: 0.45)
        }
    }

    // MARK: - Temporary reveals

    /// Shows the section of an item that is about to be opened, and keeps it
    /// shown until the item's menu closes.
    func revealForActivation(of section: ItemSection) {
        hold()
        zenLifted = model.isZenActive
        if section == .visible {
            apply()
        } else {
            reveal(all: section == .stash, trigger: .activation)
        }
    }

    /// Ends a reveal started with ``revealForActivation(of:)`` once the
    /// app that owns `pid` no longer shows a menu or popover.
    func endActivation(watching pid: pid_t) {
        Task { [weak self] in
            guard let self else { return }
            let height = self.model.statusBar.screen.map { ScreenGeometry.menuBarHeight(on: $0) } ?? 24
            let start = Date()
            var sawPopup = false
            while Date().timeIntervalSince(start) < 300 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                let open = WindowCapture.hasOpenPopup(ownedBy: pid, menuBarHeight: height) || WindowCapture.anyMenuOpen()
                if open {
                    sawPopup = true
                } else if sawPopup || Date().timeIntervalSince(start) > 2.5 {
                    break
                }
            }
            if self.zenLifted {
                self.zenLifted = false
                self.apply()
            }
            self.release()
            self.scheduleRehide(after: 0.8)
        }
    }

    /// Reveals everything and keeps it that way while items are moved.
    func beginLayoutSession() {
        layoutSessions += 1
        guard layoutSessions == 1 else { return }
        visibilityBeforeLayout = visibility
        hold()
        zenLifted = model.isZenActive
        model.statusBar.setDividersForcedVisible(true)
        reveal(all: true, trigger: .layout)
    }

    func endLayoutSession() {
        guard layoutSessions > 0 else { return }
        layoutSessions -= 1
        guard layoutSessions == 0 else { return }
        model.statusBar.setDividersForcedVisible(false)
        zenLifted = false
        holds = max(holds - 1, 0)
        switch visibilityBeforeLayout {
        case .collapsed: collapse(trigger: .layout)
        case .revealed: visibility = .revealed; apply(); scheduleRehide()
        case .revealedAll: apply(); scheduleRehide()
        }
    }

    // MARK: - Automatic rehide

    func scheduleRehide(after delay: TimeInterval? = nil) {
        rehideTask?.cancel()
        guard visibility != .collapsed, holds == 0, model.settings.reveal.autoRehide || delay != nil else { return }
        let seconds = max(delay ?? model.settings.reveal.rehideDelay, 0.2)
        rehideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.rehideIfIdle()
        }
    }

    private func rehideIfIdle() {
        guard visibility != .collapsed, holds == 0 else { return }
        if pointerIsInMenuBar || WindowCapture.anyMenuOpen() {
            scheduleRehide(after: 1.5)
            return
        }
        guard model.settings.reveal.autoRehide || revealedByHover else { return }
        collapse(trigger: .timer)
    }

    private var pointerIsInMenuBar: Bool {
        ScreenGeometry.isInMenuBar(cocoa: NSEvent.mouseLocation)
    }

    private func applicationActivated(pid: pid_t?) {
        refreshAppMenuFrame(for: pid)
        guard let pid, pid != AppInfo.ownPID else { return }
        if activatedForAppMenus {
            // The user switched apps while Meno held the menu bar.
            activatedForAppMenus = false
            previousApp = nil
        }
        guard visibility != .collapsed, holds == 0, model.settings.reveal.rehideOnFocusChange else { return }
        collapse(trigger: .focus)
    }

    // MARK: - Pointer, clicks and scrolling

    private var passiveRevealBlocked: Bool {
        model.isZenActive && model.settings.zen.blocksReveal
    }

    private func pointerMoved(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let inMenuBar = ScreenGeometry.isInMenuBar(cocoa: location)
        let settings = model.settings.reveal

        if inMenuBar {
            pointerExitTask?.cancel()
            pointerExitTask = nil
        }

        if settings.onHover, visibility == .collapsed, !passiveRevealBlocked {
            let point = ScreenGeometry.quartzPoint(fromCocoa: location)
            if inMenuBar, isEmptySpot(point) {
                if hoverTask == nil {
                    let delay = max(settings.hoverDelay, 0.05)
                    hoverTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        guard let self, !Task.isCancelled else { return }
                        self.hoverTask = nil
                        let current = ScreenGeometry.quartzPoint(fromCocoa: NSEvent.mouseLocation)
                        if self.visibility == .collapsed, self.isEmptySpot(current) {
                            self.requestReveal(all: false, trigger: .hover)
                        }
                    }
                }
            } else {
                hoverTask?.cancel()
                hoverTask = nil
            }
        }

        let exitRehides = settings.rehideOnMouseExit || revealedByHover
        if !inMenuBar, exitRehides, visibility != .collapsed, holds == 0, pointerExitTask == nil {
            pointerExitTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard let self, !Task.isCancelled else { return }
                self.pointerExitTask = nil
                if !self.pointerIsInMenuBar, !WindowCapture.anyMenuOpen(), self.holds == 0 {
                    self.collapse(trigger: .pointerExit)
                }
            }
        }
    }

    private func clickedElsewhere(_ event: NSEvent) {
        guard visibility != .collapsed, holds == 0 else { return }
        let location = NSEvent.mouseLocation
        let point = ScreenGeometry.quartzPoint(fromCocoa: location)
        if ScreenGeometry.isInMenuBar(cocoa: location) {
            if event.type == .leftMouseDown, model.settings.reveal.onEmptyAreaClick, isEmptySpot(point) {
                collapse(trigger: .emptyArea)
            }
            return
        }
        guard model.settings.reveal.rehideOnFocusChange else { return }
        // Clicks into menus or popovers of revealed items keep them revealed.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, self.visibility != .collapsed, self.holds == 0 else { return }
            if WindowCapture.anyMenuOpen() || Self.isFloatingWindow(at: point) { return }
            self.collapse(trigger: .focus)
        }
    }

    private static func isFloatingWindow(at point: CGPoint) -> Bool {
        let floating = Int(CGWindowLevelForKey(.floatingWindow))
        return WindowCapture.windowList(onScreenOnly: true).contains { window in
            window.pid != AppInfo.ownPID && window.layer >= floating && window.bounds.contains(point)
        }
    }

    private func scrolled(_ event: NSEvent) {
        guard model.settings.reveal.onScroll, !passiveRevealBlocked,
              ScreenGeometry.isInMenuBar(cocoa: NSEvent.mouseLocation) else { return }
        let now = Date()
        if now.timeIntervalSince(lastScroll) > 0.35 {
            scrollAccumulator = 0
        }
        lastScroll = now
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        // Positive when the fingers (or wheel) move downwards.
        let physical = event.isDirectionInvertedFromDevice ? delta : -delta
        scrollAccumulator += physical
        let threshold: CGFloat = 14
        if scrollAccumulator > threshold {
            scrollAccumulator = 0
            if visibility == .collapsed {
                requestReveal(all: false, trigger: .scroll)
            }
        } else if scrollAccumulator < -threshold {
            scrollAccumulator = 0
            if visibility != .collapsed {
                collapse(trigger: .scroll)
            }
        }
    }

    /// Whether a point (Quartz) is on an empty part of the menu bar that
    /// shows Meno's items.
    private func isEmptySpot(_ point: CGPoint) -> Bool {
        guard let screen = model.statusBar.screen else { return false }
        let screenRect = ScreenGeometry.quartzRect(fromCocoa: screen.frame)
        guard screenRect.contains(point) else { return false }
        if let menus = appMenuFrame, point.x <= menus.maxX + 6 { return false }
        if let notch = ScreenGeometry.notchRect(on: screen) {
            let housing = ScreenGeometry.quartzRect(fromCocoa: notch)
            if point.x >= housing.minX - 4, point.x <= housing.maxX + 4 { return false }
        }
        if visibility == .collapsed {
            return model.statusBar.emptyAreaFrames.contains { frame in
                point.x >= frame.minX && point.x <= frame.maxX
            }
        }
        // While revealed, the gap left of the leftmost item counts as empty.
        let occupied = (model.inventory.items.map(\.frame) + model.statusBar.ownFrames)
            .filter { $0.width > 0 && screenRect.intersects($0) }
        guard let leftmost = occupied.map(\.minX).min() else { return false }
        return point.x < leftmost - 2
    }

    // MARK: - App menus

    func refreshAppMenuFrame(for pid: pid_t?) {
        guard let pid, model.permissions.accessibility else {
            appMenuFrame = nil
            return
        }
        guard pid != AppInfo.ownPID else { return }
        Task { [weak self] in
            let frame = await AppMenuInspector.menuFrame(ofPID: pid)
            self?.appMenuFrame = frame
        }
    }

    /// Width the revealed items need, from the latest scan.
    private func requiredWidth(all: Bool) -> CGFloat {
        let sections: Set<ItemSection> = all ? [.visible, .hidden, .stash] : [.visible, .hidden]
        let items = model.inventory.items.filter { sections.contains($0.section) }
        return items.reduce(0) { $0 + max($1.frame.width, 0) } + 48
    }

    /// Whether revealed items fit next to the app menus and the notch.
    func revealFits(all: Bool) -> Bool {
        guard let screen = model.statusBar.screen else { return true }
        let screenRect = ScreenGeometry.quartzRect(fromCocoa: screen.frame)
        var leftLimit = screenRect.minX + 60
        if let notch = ScreenGeometry.notchRect(on: screen) {
            leftLimit = max(leftLimit, ScreenGeometry.quartzRect(fromCocoa: notch).maxX)
        } else if model.settings.general.appMenuHiding == .never, let menus = appMenuFrame {
            leftLimit = max(leftLimit, menus.maxX)
        }
        return requiredWidth(all: all) <= screenRect.maxX - leftLimit
    }

    func shouldUseShelf(all: Bool) -> Bool {
        switch model.settings.general.revealStyle {
        case .shelf: return true
        case .menuBar: return false
        case .automatic: return !revealFits(all: all)
        }
    }

    private func revealCollidesWithAppMenus(all: Bool) -> Bool {
        guard let screen = model.statusBar.screen, let menus = appMenuFrame else { return false }
        if ScreenGeometry.hasNotch(screen) { return false }
        let screenRect = ScreenGeometry.quartzRect(fromCocoa: screen.frame)
        return requiredWidth(all: all) > screenRect.maxX - menus.maxX
    }

    private func hideAppMenusIfNeeded(all: Bool) {
        let mode = model.settings.general.appMenuHiding
        guard mode != .never, !activatedForAppMenus, model.permissions.accessibility else { return }
        if mode == .whenNeeded, !revealCollidesWithAppMenus(all: all) { return }
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != AppInfo.ownPID else { return }
        previousApp = front
        activatedForAppMenus = true
        NSApp.activate()
    }

    private func restoreAppMenus() {
        guard activatedForAppMenus else { return }
        activatedForAppMenus = false
        defer { previousApp = nil }
        guard NSApp.isActive, !model.hasVisibleWindows, let previousApp, !previousApp.isTerminated else { return }
        NSApp.yieldActivation(to: previousApp)
        _ = previousApp.activate(options: [])
    }
}
