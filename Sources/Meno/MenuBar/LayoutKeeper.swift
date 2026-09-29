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
    /// Items found elsewhere while Zen kept the menu bar still.
    private var waiting: [SectionKeeper.Misplacement] = []

    /// More items elsewhere at once than this are only offered to be put back.
    private static let automaticLimit = 3
    /// Items not seen for this long are forgotten.
    private static let memorySpan: TimeInterval = 180 * 24 * 60 * 60
    /// How long after launch scans are not taken in.
    private static let settling: TimeInterval = 5

    init(model: AppModel) {
        self.model = model
        keeper = SectionKeeper(memory: model.storage.loadSectionMemory())
        keeper.forget(notSeenSince: Date().addingTimeInterval(-Self.memorySpan))
    }

    /// Takes in a scan of the menu bar.
    func scanned(_ observations: [SectionKeeper.Observation]) {
        let now = Date()
        // Right after launch Meno's dividers may still be settling, and an
        // item that seems to move then would count as moved on purpose.
        if let launched = NSRunningApplication.current.launchDate, now.timeIntervalSince(launched) < Self.settling {
            return
        }
        defer { saveIfNeeded() }
        let misplaced = keeper.observe(observations, at: now, includesStash: model.settings.general.stashEnabled)
        guard model.settings.general.keepsSections else {
            keeper.accept(misplaced + waiting, at: now)
            waiting = []
            return
        }
        waiting += misplaced
        // Zen keeps the menu bar still; the items go back afterwards.
        guard !waiting.isEmpty, !model.isZenActive else { return }
        let due = waiting.filter { misplacement in
            // Only items that are still where they were found.
            model.inventory.item(for: misplacement.key)?.section == misplacement.found
        }
        waiting = []
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

    private func putBack(_ misplacement: SectionKeeper.Misplacement) {
        let key = misplacement.key
        keeper.didPutBack(key)
        // Moving an item ends it being shown for a while, but this move only
        // undoes what its app did.
        let placement = model.settings.temporaryPlacements.placement(of: key)
        Task {
            do {
                try await model.mover.move(key, to: misplacement.belongs, automatic: true, onlyFrom: misplacement.found)
                Log.move.info("Put \(key.rawValue, privacy: .public) back in \(misplacement.belongs.rawValue, privacy: .public)")
                if let placement, model.settings.temporaryPlacements.placement(of: key) == nil {
                    model.settings.temporaryPlacements.show(key, from: placement.returnSection, until: placement.until)
                    model.temporary.schedule()
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
        for misplacement in misplaced {
            keeper.didPutBack(misplacement.key)
        }
        Task {
            do {
                try await model.mover.move(misplaced.map { (key: $0.key, section: $0.belongs, from: Optional($0.found)) })
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
