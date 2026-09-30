import AppKit
import MenoCore

/// Puts items back in the section they were left in when their app or
/// macOS puts them elsewhere, for example at the left end of the menu bar
/// after the app restarted.
///
/// A few items go back on their own, once the mouse and keyboard are idle.
/// When many items are elsewhere at once, something bigger changed, so
/// Meno only offers to put them back.
@MainActor
final class LayoutKeeper {
    unowned let model: AppModel

    private var keeper: SectionKeeper
    /// Items found elsewhere while Zen kept the menu bar still, by key.
    private var waiting: [MenuItemKey: SectionKeeper.Misplacement] = [:]
    /// When the scan taken in last began.
    private var lastScanStart: Date?
    /// Where the person's recent ⌘-drags in the menu bar ended, in Quartz
    /// coordinates, and where the drag that is going on started.
    private var drops: [(point: CGPoint, date: Date)] = []
    private var dragStart: NSPoint?
    private lazy var dragMonitor = GlobalEventMonitor(mask: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
        self?.mouse(event)
    }

    /// More items elsewhere at once than this are only offered to be put back.
    private static let automaticLimit = 3
    /// Items not seen for this long are forgotten.
    private static let memorySpan: TimeInterval = 180 * 24 * 60 * 60
    /// How long after Meno started scans are not taken in, while its
    /// dividers settle. Moves Meno makes meanwhile are still recorded.
    private static let settling: TimeInterval = 5
    /// How far from where it was let go of a dragged item can land.
    private static let dropReach: CGFloat = 16

    init(model: AppModel) {
        self.model = model
        keeper = SectionKeeper(memory: model.storage.loadSectionMemory())
        keeper.forget(notSeenSince: Date().addingTimeInterval(-Self.memorySpan))
        // Drags made while Meno starts count too.
        if model.settings.general.keepsSections {
            dragMonitor.start()
        }
    }

    /// Whether items may be put back right now.
    private var mayPutBack: Bool {
        model.settings.general.keepsSections && !model.isZenActive
    }

    /// Takes in a scan of the menu bar.
    func scanned(_ observations: [SectionKeeper.Observation]) {
        let now = Date()
        // An item that seems to move while the dividers settle would count
        // as moved on purpose.
        guard now.timeIntervalSince(model.startedAt) >= Self.settling else { return }
        defer { saveIfNeeded() }
        // The scan read the menu bar from when it began, so a drag that
        // ended after the previous scan began may not be in that one.
        let since = lastScanStart ?? model.startedAt
        let scanStart = model.inventory.scannedAt ?? now
        lastScanStart = scanStart
        let recentDrops = drops.filter { $0.date >= since }
        drops.removeAll { $0.date < scanStart }
        var misplaced = keeper.observe(observations, at: now, includesStash: model.settings.general.stashEnabled)
        guard model.settings.general.keepsSections else {
            dragMonitor.stop()
            drops = []
            keeper.accept(misplaced + Array(waiting.values), at: now)
            waiting = [:]
            return
        }
        dragMonitor.start()
        // An item the person dragged right after its app put it in the
        // menu bar, before a scan saw it, only looks as if its app put it
        // where it is now. It lies where the drag ended.
        let dragged = misplaced.filter { isDropped($0.key, among: recentDrops) }
        if !dragged.isEmpty {
            keeper.accept(dragged, at: now)
            let keys = Set(dragged.map(\.key))
            misplaced.removeAll { keys.contains($0.key) }
            for key in keys {
                waiting[key] = nil
            }
        }
        for misplacement in misplaced {
            waiting[misplacement.key] = misplacement
        }
        // Zen keeps the menu bar still; the items go back afterwards.
        guard !waiting.isEmpty, mayPutBack else { return }
        let due = waiting.values.filter { misplacement in
            // Only items that are still where they were found.
            model.inventory.item(for: misplacement.key)?.section == misplacement.found
        }
        waiting = [:]
        guard !due.isEmpty else { return }
        if due.count > Self.automaticLimit {
            keeper.accept(due, at: now)
            offerToPutBack(due)
        } else {
            for misplacement in due {
                putBack(misplacement)
            }
        }
    }

    /// Takes in where Meno just placed items, for example for a rule or a
    /// scene: that is where they belong now.
    func menoPlaced(_ keys: [MenuItemKey]) {
        let now = Date()
        let includesStash = model.settings.general.stashEnabled
        for key in keys {
            guard let item = model.inventory.item(for: key), model.inventory.knowsSection(of: key) else { continue }
            keeper.record(key, in: item.section, process: item.pid, at: now, includesStash: includesStash)
        }
        saveIfNeeded()
    }

    /// Whether one of `drops` ended on the item, as the last scan found it.
    private func isDropped(_ key: MenuItemKey, among drops: [(point: CGPoint, date: Date)]) -> Bool {
        guard !drops.isEmpty, let frame = model.inventory.item(for: key)?.frame, frame.width > 0 else { return false }
        let reach = frame.insetBy(dx: -Self.dropReach, dy: -Self.dropReach)
        return drops.contains { reach.contains($0.point) }
    }

    /// Notices ⌘-drags that end in the menu bar. Meno's own drags are
    /// recorded as it makes them.
    private func mouse(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            let isPersonDrag = event.modifierFlags.contains(.command) && !model.mover.isMoving
                && ScreenGeometry.isInMenuBar(cocoa: location)
            dragStart = isPersonDrag ? location : nil
        case .leftMouseUp:
            guard let start = dragStart else { return }
            dragStart = nil
            let moved = abs(location.x - start.x) > 2 || abs(location.y - start.y) > 2
            guard moved, ScreenGeometry.isInMenuBar(cocoa: location) else { return }
            let now = Date()
            // Drags a scan has taken in long ago no longer matter.
            drops.removeAll { now.timeIntervalSince($0.date) > 300 }
            drops.append((point: ScreenGeometry.quartzPoint(fromCocoa: location), date: now))
        default:
            break
        }
    }

    private func putBack(_ misplacement: SectionKeeper.Misplacement) {
        let key = misplacement.key
        Task {
            do {
                // Asked again right before dragging: waiting for an idle
                // moment can take a while, and Zen may have come on.
                try await model.mover.move(
                    key,
                    to: misplacement.belongs,
                    automatic: true,
                    onlyFrom: misplacement.found,
                    restoring: true
                ) { [weak self] in
                    self?.mayPutBack ?? false
                }
                keeper.didPutBack(key)
                Log.move.info("Put \(key.rawValue, privacy: .public) back in \(misplacement.belongs.rawValue, privacy: .public)")
            } catch ItemMover.MoveError.skipped {
                if model.settings.general.keepsSections {
                    waiting[key] = misplacement
                }
            } catch {
                Log.move.error("Putting \(key.rawValue, privacy: .public) back failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func offerToPutBack(_ misplaced: [SectionKeeper.Misplacement]) {
        model.toasts.show(
            String(localized: "\(misplaced.count) items are no longer where you left them."),
            symbol: "rectangle.3.group",
            actions: [ToastCenter.Action(title: String(localized: "Put Them Back")) { [weak self] in
                self?.putBackAll(misplaced)
            }],
            duration: 15
        )
    }

    private func putBackAll(_ misplaced: [SectionKeeper.Misplacement]) {
        Task {
            do {
                try await model.mover.restore(misplaced.map { (key: $0.key, section: $0.belongs, from: Optional($0.found)) })
                for misplacement in misplaced {
                    keeper.didPutBack(misplacement.key)
                }
            } catch {
                model.toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func saveIfNeeded() {
        guard keeper.hasUnsavedChanges else { return }
        keeper.markSaved()
        model.storage.saveSectionMemory(keeper.memory)
    }
}
