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
            case .didNotMove(let name):
                return String(localized: "\(name) did not move. Try dragging it with ⌘ held down.")
            case .plan:
                return String(localized: "The layout could not be planned.")
            case .personBusy:
                return String(localized: "Meno did not rearrange the menu bar because the mouse and keyboard were in use the whole time.")
            }
        }
    }

    unowned let model: AppModel

    @Published private(set) var isMoving = false
    @Published private(set) var progress: (done: Int, total: Int)?
    /// The arrangement before the last change the person made through Meno.
    @Published private(set) var undoLayout: SceneLayout?

    init(model: AppModel) {
        self.model = model
    }

    /// Moves an item into a section. Automatic moves (from rules and for new
    /// items) wait until the mouse and keyboard are idle.
    func move(_ key: MenuItemKey, to section: ItemSection, automatic: Bool = false) async throws {
        let placement = LayoutPlanner.placement(for: section, includesStash: model.settings.general.stashEnabled)
        try await perform([MoveStep(item: key, placement: placement)], layout: nil, automatic: automatic)
    }

    func move(_ key: MenuItemKey, placement: Placement) async throws {
        try await perform([MoveStep(item: key, placement: placement)], layout: nil, automatic: false)
    }

    /// Arranges the menu bar like `layout`.
    func apply(_ layout: SceneLayout, automatic: Bool = false) async throws {
        try await perform(nil, layout: layout, automatic: automatic)
    }

    func perform(_ steps: [MoveStep]) async throws {
        try await perform(steps, layout: nil, automatic: false)
    }

    /// Puts the items back where they were before the last change.
    func undo() async throws {
        guard let layout = undoLayout else { return }
        try await perform(nil, layout: layout, automatic: false, isUndo: true)
    }

    private func perform(_ plannedSteps: [MoveStep]?, layout: SceneLayout?, automatic: Bool, isUndo: Bool = false) async throws {
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
        do {
            try await Task.sleep(nanoseconds: 450_000_000)
            await model.inventory.refresh()
            let before = model.inventory.currentLayout()
            var steps = plannedSteps ?? []
            if let layout {
                let target = LayoutPlanner.targetOrder(for: layout, includesStash: model.settings.general.stashEnabled)
                do {
                    steps = try LayoutPlanner.plan(current: model.inventory.layoutTokens(), target: target)
                } catch {
                    throw MoveError.plan
                }
            }
            for (index, step) in steps.enumerated() {
                progress = (index, steps.count)
                if automatic && index > 0 {
                    try await waitForIdleInput(duringMove: true)
                }
                try await execute(step)
            }
            progress = (steps.count, steps.count)
            // Rules undo their own changes, so only changes made by the
            // person can be undone here.
            if isUndo {
                undoLayout = nil
            } else if !automatic, !steps.isEmpty {
                undoLayout = before
            }
            model.reveal.endLayoutSession()
            model.inventory.scheduleRefresh(after: 0.5)
        } catch {
            model.reveal.endLayoutSession()
            model.inventory.scheduleRefresh(after: 0.5)
            throw error
        }
    }

    private func execute(_ step: MoveStep) async throws {
        for attempt in 0..<3 {
            guard let item = model.inventory.item(for: step.item) else { throw MoveError.itemMissing }
            guard item.isMovable else { throw MoveError.notMovable(item.displayName) }
            if isSatisfied(step) { return }
            guard let reference = frame(of: step.placement.reference) else { throw MoveError.referenceMissing }
            guard item.isOnScreen else { throw MoveError.offScreen(item.displayName) }

            let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
            let end = dropPoint(for: item.frame, reference: reference, placement: step.placement, attempt: attempt)
            Log.move.info("Moving \(item.key.rawValue, privacy: .public) attempt \(attempt)")
            await EventSynthesizer.commandDrag(from: start, to: end)
            try await Task.sleep(nanoseconds: 450_000_000)
            await model.inventory.refresh()
            if isSatisfied(step) { return }
        }
        let name = model.inventory.item(for: step.item)?.displayName ?? step.item.owner
        throw MoveError.didNotMove(name)
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

    private func isSatisfied(_ step: MoveStep) -> Bool {
        let tokens = model.inventory.layoutTokens()
        guard let itemIndex = tokens.firstIndex(of: .item(step.item)),
              let referenceIndex = tokens.firstIndex(of: step.placement.reference) else { return false }
        switch step.placement {
        case .rightOf: return itemIndex > referenceIndex
        case .leftOf: return itemIndex < referenceIndex
        }
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
