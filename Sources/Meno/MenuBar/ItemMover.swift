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
                return String(localized: "\(name) is not visible, so it cannot be dragged. Make room in the menu bar and try again.")
            case .behindHousing(let name):
                return String(localized: "\(name) sits behind the camera housing, where it cannot be dragged. Move other visible items to Hidden to make room, then try again.")
            case .didNotMove(let name):
                return String(localized: "\(name) did not move. Try dragging it with ⌘ held down.")
            case .plan:
                return String(localized: "The layout could not be planned.")
            case .personBusy:
                return String(localized: "Meno did not rearrange the menu bar because the mouse and keyboard were in use the whole time.")
            }
        }
    }

    /// One drag and how to tell that it is done.
    private enum Move {
        /// Into a section, across the divider that bounds it.
        case section(MenuItemKey, ItemSection)
        /// Right next to another token. Only tokens in `counted` may lie in
        /// between; with `nil`, every token counts.
        case step(MoveStep, counted: Set<LayoutToken>?)

        var key: MenuItemKey {
            switch self {
            case .section(let key, _): return key
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
    /// items) wait until the mouse and keyboard are idle.
    func move(_ key: MenuItemKey, to section: ItemSection, automatic: Bool = false) async throws {
        try await perform(.moves([.section(key, section)]), automatic: automatic)
    }

    /// Moves an item right next to another one.
    func move(_ key: MenuItemKey, placement: Placement) async throws {
        try await perform(.moves([.step(MoveStep(item: key, placement: placement), counted: nil)]), automatic: false)
    }

    /// Arranges the menu bar like `layout`.
    func apply(_ layout: SceneLayout, automatic: Bool = false) async throws {
        try await perform(.layout(layout), automatic: automatic)
    }

    /// Puts the items back where they were before the last change. Undoing
    /// again goes back one more change.
    func undo() async throws {
        guard let layout = undoLayout else { return }
        try await perform(.layout(layout), automatic: false, isUndo: true)
    }

    private func perform(_ request: Request, automatic: Bool, isUndo: Bool = false) async throws {
        guard model.permissions.accessibility else { throw MoveError.noPermission }
        if automatic {
            try await waitForIdleInput(duringMove: false)
        }
        guard !isMoving else { throw MoveError.busy }
        isMoving = true
        model.reveal.beginLayoutSession()
        defer {
            isMoving = false
            progress = nil
        }
        var before: SceneLayout?
        var moved = false
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
                if try await execute(move) {
                    moved = true
                }
            }
            progress = (moves.count, moves.count)
            if isUndo, !undoStack.isEmpty {
                undoStack.removeLast()
            }
        } catch {
            finish(before: before, moved: moved, automatic: automatic, isUndo: isUndo)
            throw error
        }
        finish(before: before, moved: moved, automatic: automatic, isUndo: isUndo)
    }

    private func finish(before: SceneLayout?, moved: Bool, automatic: Bool, isUndo: Bool) {
        // Rules undo their own changes, so only changes made by the person
        // can be undone here, including the part of one that failed midway.
        if moved, !automatic, !isUndo, let before {
            undoStack.append(before)
            if undoStack.count > Self.undoLimit {
                undoStack.removeFirst(undoStack.count - Self.undoLimit)
            }
        }
        model.reveal.endLayoutSession()
        model.inventory.scheduleRefresh(after: 0.5)
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
            guard item.isOnScreen else { throw MoveError.offScreen(item.displayName) }
            guard !Self.isBehindHousing(item.frame) else { throw MoveError.behindHousing(item.displayName) }

            let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
            let end = dropPoint(for: item.frame, reference: reference, placement: placement, attempt: attempt)
            Log.move.info("Moving \(item.key.rawValue, privacy: .public) attempt \(attempt)")
            await EventSynthesizer.commandDrag(from: start, to: end, pace: 1 + Double(attempt) * 0.75)
            try await Task.sleep(nanoseconds: 450_000_000)
            await model.inventory.refresh()
        }
        if let item = model.inventory.item(for: move.key), remainingPlacement(for: move, item: item) == nil {
            return true
        }
        let name = model.inventory.item(for: move.key)?.displayName ?? move.key.owner
        throw MoveError.didNotMove(name)
    }

    /// Where the item still has to be dropped, or `nil` when the move is done.
    private func remainingPlacement(for move: Move, item: MenuBarItem) -> Placement? {
        switch move {
        case .section(_, let section):
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

    /// Whether the middle of a frame is behind the camera housing of a
    /// screen, where clicks do not reach the item.
    static func isBehindHousing(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            guard let notch = ScreenGeometry.notchRect(on: screen) else { return false }
            let housing = ScreenGeometry.quartzRect(fromCocoa: notch)
            return housing.minX < frame.midX && frame.midX < housing.maxX
                && housing.minY <= frame.midY && frame.midY <= housing.maxY
        }
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
