import AppKit
import MenoCore

/// Rearranges menu bar items by performing the same ⌘-drag a person would.
@MainActor
final class ItemMover: ObservableObject {
    enum MoveError: LocalizedError {
        case noPermission
        case busy
        case itemMissing
        case notMovable(String)
        case referenceMissing
        case offScreen(String)
        case behindHousing(String)
        case didNotMove(String)
        case plan
        case personBusy
        /// The caller called the move off right before it started.
        case skipped

        var errorDescription: String? {
            switch self {
            case .noPermission:
                return String(localized: "Meno needs Accessibility access to move items.")
            case .busy:
                return String(localized: "Another move is still in progress.")
            case .itemMissing:
                return String(localized: "The item is no longer in the menu bar.")
            case .notMovable(let name):
                return String(localized: "macOS does not allow \(name) to be moved.")
            case .referenceMissing:
                return String(localized: "Meno could not find where to drop the item.")
            case .offScreen(let name):
                return String(localized: "\(name) does not fit in the menu bar, and Meno could not move it from there. Quit menu bar apps you do not need, or narrow the icon spacing in Appearance, then try again.")
            case .behindHousing(let name):
                return String(localized: "\(name) is behind the camera housing, where macOS keeps items that do not fit, and Meno could not move it from there. Quit menu bar apps you do not need, or narrow the icon spacing in Appearance, then try again.")
            case .didNotMove(let name):
                return String(localized: "\(name) did not move. Try dragging it with ⌘ held down.")
            case .plan:
                return String(localized: "The layout could not be planned.")
            case .personBusy:
                return String(localized: "Meno did not rearrange the menu bar because the mouse and keyboard were in use the whole time.")
            case .skipped:
                return String(localized: "The move was called off.")
            }
        }
    }

    /// One drag and how to tell that it is done.
    private enum Move {
        /// Into a section, across the divider that bounds it; with `from`,
        /// only while the item is still in that section.
        case section(MenuItemKey, ItemSection, from: ItemSection?)
        /// Right next to another token. Only tokens in `counted` may lie in
        /// between; with `nil`, every token counts.
        case step(MoveStep, counted: Set<LayoutToken>?)

        var key: MenuItemKey {
            switch self {
            case .section(let key, _, _): return key
            case .step(let step, _): return step.item
            }
        }
    }

    private enum Request {
        case moves([Move])
        case layout(SceneLayout)
    }

    unowned let model: AppModel

    @Published private(set) var isMoving = false
    @Published private(set) var progress: (done: Int, total: Int)?
    /// The item being dragged right now.
    @Published private(set) var movingKey: MenuItemKey?
    /// The arrangements before the latest changes the person made through
    /// Meno, oldest first.
    @Published private(set) var undoStack: [SceneLayout] = []
    /// How many changes can be undone.
    static let undoLimit = 20

    /// The arrangement before the last change the person made through Meno.
    var undoLayout: SceneLayout? { undoStack.last }

    init(model: AppModel) {
        self.model = model
    }

    /// Moves an item into a section. Automatic moves (from rules and for new
    /// items) wait until the mouse and keyboard are idle. With `onlyFrom`,
    /// an item that left that section meanwhile stays where it is.
    ///
    /// A restoring move puts an item back where it was after its app or
    /// macOS moved it, so the undo history and items shown for a while stay
    /// as they are. `proceeds` is asked right before dragging starts; when
    /// it says no, the move is called off with `MoveError.skipped`.
    func move(
        _ key: MenuItemKey,
        to section: ItemSection,
        automatic: Bool = false,
        onlyFrom: ItemSection? = nil,
        restoring: Bool = false,
        proceeds: (() -> Bool)? = nil
    ) async throws {
        try await perform(
            .moves([.section(key, section, from: onlyFrom)]),
            automatic: automatic,
            restoring: restoring,
            proceeds: proceeds
        )
    }

    /// Puts items back into sections, one after the other, once other moves
    /// are done. With `from`, an item that left that section meanwhile stays
    /// where it is. Like a restoring move, it leaves the undo history and
    /// items shown for a while as they are.
    func restore(_ targets: [(key: MenuItemKey, section: ItemSection, from: ItemSection?)]) async throws {
        try await perform(.moves(targets.map { .section($0.key, $0.section, from: $0.from) }), automatic: false, restoring: true)
    }

    /// Moves an item right next to another one.
    func move(_ key: MenuItemKey, placement: Placement) async throws {
        try await perform(.moves([.step(MoveStep(item: key, placement: placement), counted: nil)]), automatic: false)
    }

    /// Arranges the menu bar like `layout`.
    func apply(_ layout: SceneLayout, automatic: Bool = false, proceeds: (() -> Bool)? = nil) async throws {
        try await perform(.layout(layout), automatic: automatic, proceeds: proceeds)
    }

    /// Puts the items back where they were before the last change. Undoing
    /// again goes back one more change.
    func undo() async throws {
        guard let layout = undoLayout else { return }
        try await perform(.layout(layout), automatic: false, isUndo: true)
    }

    private func perform(
        _ request: Request,
        automatic: Bool,
        isUndo: Bool = false,
        restoring: Bool = false,
        proceeds: (() -> Bool)? = nil
    ) async throws {
        guard model.permissions.accessibility else { throw MoveError.noPermission }
        if automatic {
            try await waitForIdleInput(duringMove: false)
        } else if restoring {
            try await waitForOtherMoves()
        }
        if let proceeds, !proceeds() {
            throw MoveError.skipped
        }
        // Nothing to drag: the menu bar does not have to open for it.
        if isAlreadyDone(request) {
            // Rules and items put back are not undone by the person's undo,
            // so the snapshots follow them.
            if automatic || restoring {
                keepUndoInStep(with: request, restoring: restoring)
            }
            if !restoring {
                model.temporary.forget(Self.keys(of: request))
            }
            model.keeper.menoPlaced(Self.keys(of: request))
            return
        }
        guard !isMoving else { throw MoveError.busy }
        isMoving = true
        model.reveal.beginLayoutSession()
        defer {
            isMoving = false
            progress = nil
            movingKey = nil
        }
        var before: SceneLayout?
        var moved = false
        /// Items that are where this request puts them.
        var placed: [MenuItemKey] = []
        do {
            try await Task.sleep(nanoseconds: 450_000_000)
            await model.inventory.refresh()
            before = model.inventory.currentLayout()
            let moves = try plannedMoves(for: request)
            for (index, move) in moves.enumerated() {
                progress = (index, moves.count)
                if automatic && index > 0 {
                    try await waitForIdleInput(duringMove: true)
                }
                movingKey = move.key
                if try await execute(move) {
                    moved = true
                }
                placed.append(move.key)
            }
            progress = (moves.count, moves.count)
            if isUndo, !undoStack.isEmpty {
                undoStack.removeLast()
            }
            // Rules and items put back are not undone by the person's undo,
            // so the snapshots follow them.
            if automatic || restoring {
                keepUndoInStep(with: request, restoring: restoring)
            }
            if !restoring {
                // Items that were placed now are no longer shown for a while.
                model.temporary.forget(Self.keys(of: request))
            }
        } catch {
            Diagnostics.event("move failed: \(error.localizedDescription)")
            model.keeper.menoPlaced(placed)
            finish(before: before, moved: moved, automatic: automatic || restoring, isUndo: isUndo)
            if moved, !restoring {
                model.forgetActiveScene()
            }
            throw error
        }
        model.keeper.menoPlaced(placed)
        finish(before: before, moved: moved, automatic: automatic || restoring, isUndo: isUndo)
        // Applying a scene marks it again once this returns; any other change
        // leaves the scene behind. Putting items back keeps it.
        if moved, !restoring {
            model.forgetActiveScene()
        }
    }

    /// Whether every item of a request is already where it puts it, going
    /// by the last scan. Only single moves are judged; whole arrangements
    /// are planned once everything is shown.
    private func isAlreadyDone(_ request: Request) -> Bool {
        guard case .moves(let moves) = request else { return false }
        return moves.allSatisfy { move in
            guard let item = model.inventory.item(for: move.key) else { return false }
            switch move {
            case .section:
                return model.inventory.knowsSection(of: move.key) && remainingPlacement(for: move, item: item) == nil
            case .step:
                // Positions of hidden items are only known with the wide engine.
                return model.inventory.framesAreReliable && remainingPlacement(for: move, item: item) == nil
            }
        }
    }

    /// Waits for the moves under way to finish, for up to half a minute.
    private func waitForOtherMoves() async throws {
        let deadline = Date().addingTimeInterval(30)
        while isMoving {
            guard Date() < deadline else { throw MoveError.busy }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func finish(before: SceneLayout?, moved: Bool, automatic: Bool, isUndo: Bool) {
        // Rules undo their own changes and items that are put back were
        // already there, so only changes made by the person can be undone
        // here, including the part of one that failed midway.
        if moved, !automatic, !isUndo, let before {
            undoStack.append(before)
            if undoStack.count > Self.undoLimit {
                undoStack.removeFirst(undoStack.count - Self.undoLimit)
            }
        }
        model.reveal.endLayoutSession()
        model.inventory.scheduleRefresh(after: 0.5)
    }

    /// Keeps the undo snapshots in step with moves the person did not
    /// make, so undoing one of their changes does not undo those as well.
    /// Putting an item back only changes snapshots taken while it was out
    /// of place.
    private func keepUndoInStep(with request: Request, restoring: Bool = false) {
        switch request {
        case .moves(let moves):
            for case .section(let key, let section, let from) in moves {
                undoStack = undoStack.map { snapshot in
                    if restoring, let from, snapshot.section(of: key) != from {
                        return snapshot
                    }
                    return snapshot.moving(key, to: section)
                }
            }
        case .layout:
            // A whole new arrangement makes the snapshots meaningless.
            undoStack.removeAll()
        }
    }

    private static func keys(of request: Request) -> [MenuItemKey] {
        switch request {
        case .moves(let moves): return moves.map(\.key)
        case .layout(let layout): return layout.leftToRight
        }
    }

    private func plannedMoves(for request: Request) throws -> [Move] {
        switch request {
        case .moves(let moves):
            return moves
        case .layout(let layout):
            let target = LayoutPlanner.targetOrder(for: layout, includesStash: model.settings.general.stashEnabled)
            let steps: [MoveStep]
            do {
                steps = try LayoutPlanner.plan(current: model.inventory.layoutTokens(), target: target)
            } catch {
                throw MoveError.plan
            }
            // Items the layout does not know stay where they are, so they
            // may end up between the items it places.
            let counted = Set(target)
            return steps.map { .step($0, counted: counted) }
        }
    }

    /// Carries out a move, returning whether anything was dragged.
    private func execute(_ move: Move) async throws -> Bool {
        for attempt in 0..<3 {
            guard let item = model.inventory.item(for: move.key) else { throw MoveError.itemMissing }
            guard item.isMovable else { throw MoveError.notMovable(item.displayName) }
            guard let placement = remainingPlacement(for: move, item: item) else { return attempt > 0 }
            guard let reference = frame(of: placement.reference) else { throw MoveError.referenceMissing }

            let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
            let end = dropPoint(for: item.frame, reference: reference, placement: placement, attempt: attempt)
            let pace = 1 + Double(attempt) * 0.75
            let reachesItem = ScreenGeometry.isReachable(start)
            // Behind the camera housing or off the screen, where the pointer
            // cannot reach, the item is dragged by its window instead.
            let drag = reachesItem && ScreenGeometry.isReachable(end) && !Diagnostics.movesByWindow
                ? nil
                : windowDrag(of: item, reference: reference, placement: placement)
            if let drag {
                Log.move.info("Moving \(item.key.rawValue, privacy: .public) by its window, attempt \(attempt)")
                Diagnostics.event("move \(item.key.rawValue) by window \(drag.window.id) to x=\(Int(drag.end.x)) attempt=\(attempt)")
                await EventSynthesizer.commandDrag(window: drag.window, to: drag.end, target: drag.target, pace: pace)
            } else if reachesItem {
                Log.move.info("Moving \(item.key.rawValue, privacy: .public) attempt \(attempt)")
                await EventSynthesizer.commandDrag(from: start, to: end, pace: pace)
            } else {
                throw Self.outOfReach(item)
            }
            try await Task.sleep(nanoseconds: 450_000_000)
            await model.inventory.refresh()
        }
        guard let item = model.inventory.item(for: move.key) else { throw MoveError.itemMissing }
        if remainingPlacement(for: move, item: item) == nil {
            return true
        }
        // Telling the person to drag it by hand only helps where they can.
        if !ScreenGeometry.isReachable(CGPoint(x: item.frame.midX, y: item.frame.midY)) {
            throw Self.outOfReach(item)
        }
        throw MoveError.didNotMove(item.displayName)
    }

    /// Why an item the pointer cannot reach was not moved.
    private static func outOfReach(_ item: MenuBarItem) -> MoveError {
        item.isOnScreen ? .behindHousing(item.displayName) : .offScreen(item.displayName)
    }

    /// The windows and drop point for dragging an item by its window, or
    /// `nil` where items have no windows of their own (macOS 27).
    private func windowDrag(
        of item: MenuBarItem,
        reference: CGRect,
        placement: Placement
    ) -> (window: WindowCapture.WindowInfo, target: WindowCapture.WindowInfo, end: CGPoint)? {
        let windows = WindowCapture.itemWindows(at: [item.frame, reference])
        // The release has to name the window it lands next to.
        guard let window = windows[0], let target = windows[1] else { return nil }
        // The edge of the reference it goes next to, which works wherever
        // that edge is, even off the screen.
        let x: CGFloat
        switch placement {
        case .rightOf: x = reference.maxX
        case .leftOf: x = reference.minX
        }
        return (window, target, CGPoint(x: x, y: reference.midY))
    }

    /// Where the item still has to be dropped, or `nil` when the move is done.
    private func remainingPlacement(for move: Move, item: MenuBarItem) -> Placement? {
        switch move {
        case .section(_, let section, let from):
            if let from, item.section != from {
                return nil
            }
            return LayoutPlanner.placement(moving: item.section, to: section, includesStash: model.settings.general.stashEnabled)
        case .step(let step, let counted):
            let done = LayoutPlanner.isSatisfied(step, in: model.inventory.layoutTokens(), counting: counted)
            return done ? nil : step.placement
        }
    }

    /// Waits for a pause in mouse and keyboard use, so an automatic move
    /// never takes the pointer mid-gesture or turns typing into ⌘ shortcuts.
    /// Before a move starts it also waits for other moves to finish. Gives
    /// up after five minutes.
    private func waitForIdleInput(duringMove: Bool) async throws {
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            try Task.checkCancellation()
            let idle = Self.secondsSinceInput >= 1.5
                && NSEvent.pressedMouseButtons == 0
                && NSEvent.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
            if idle && (duringMove || !isMoving) {
                return
            }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        throw MoveError.personBusy
    }

    /// Seconds since the person last used a mouse, trackpad or keyboard.
    /// Meno's own synthesized events do not count.
    private static var secondsSinceInput: TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown, .flagsChanged]
        return types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? .greatestFiniteMagnitude
    }

    private func frame(of token: LayoutToken) -> CGRect? {
        switch token {
        case .item(let key):
            return model.inventory.item(for: key)?.frame
        case .anchor(let name):
            if token == LayoutPlanner.hiddenDivider { return model.statusBar.hiddenDividerFrame }
            if token == LayoutPlanner.stashDivider { return model.statusBar.stashDividerFrame }
            if name == "meno.toggle" { return model.statusBar.toggleFrame }
            if name.hasPrefix("pinned:"), let key = MenuItemKey(rawValue: String(name.dropFirst("pinned:".count))) {
                return model.inventory.item(for: key)?.frame
            }
            return nil
        }
    }

    /// Where to release the item. Neighbours swap once the dragged item's
    /// center passes theirs, so the target depends on the direction.
    private func dropPoint(for item: CGRect, reference: CGRect, placement: Placement, attempt: Int) -> CGPoint {
        let nudge = CGFloat(attempt) * 3
        let inset = min(reference.width * 0.3, 7)
        let x: CGFloat
        switch placement {
        case .rightOf:
            x = item.midX < reference.midX
                ? reference.maxX - inset + nudge
                : reference.maxX + 2 + nudge
        case .leftOf:
            x = item.midX > reference.midX
                ? reference.minX + inset - nudge
                : reference.minX - 2 - nudge
        }
        return CGPoint(x: x, y: item.midY)
    }
}
