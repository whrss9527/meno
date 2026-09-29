import Foundation
import MenoCore

/// Shows items in the menu bar for a while and puts them back afterwards.
///
/// The placements are part of the settings and only go once the item is
/// back, so an item also goes back after Meno or the Mac restarted. Moving
/// the item in any other way (by hand, with a scene, a rule or undo) ends
/// its placement.
@MainActor
final class TemporaryPlacements {
    unowned let model: AppModel

    private var timer: Task<Void, Never>?
    /// Items being put back right now.
    private var puttingBack: Set<MenuItemKey> = []
    /// Items that could not be put back, and when to try again.
    private var failures: [MenuItemKey: (count: Int, retryAfter: Date)] = [:]

    /// Attempts before giving up on putting an item back.
    private static let attempts = 3
    /// How long an item whose app is not running is waited for.
    private static let patience: TimeInterval = 7 * 24 * 60 * 60

    init(model: AppModel) {
        self.model = model
    }

    /// When a temporarily shown item goes back, if it is shown for a while.
    func returnDate(of key: MenuItemKey) -> Date? {
        model.settings.temporaryPlacements.placement(of: key)?.until
    }

    /// Where a temporarily shown item goes back to.
    func returnSection(of key: MenuItemKey) -> ItemSection? {
        model.settings.temporaryPlacements.placement(of: key)?.returnSection
    }

    /// Shows an item in the menu bar until `duration` has passed. For an
    /// item that is already shown for a while, only the time changes.
    func show(_ key: MenuItemKey, for duration: TimeInterval) {
        guard let item = model.inventory.item(for: key), item.isMovable else { return }
        let until = Date().addingTimeInterval(duration)
        if item.section == .visible {
            guard let origin = returnSection(of: key) else { return }
            model.settings.temporaryPlacements.show(key, from: origin, until: until)
            schedule()
            return
        }
        let origin = item.section
        Task {
            do {
                try await model.mover.move(key, to: .visible)
                // Recorded once the item is shown; the move itself ends any
                // earlier placement.
                model.settings.temporaryPlacements.show(key, from: origin, until: until)
                schedule()
            } catch {
                model.toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Puts an item back now instead of when its time is up.
    func putBack(_ key: MenuItemKey) {
        guard let placement = model.settings.temporaryPlacements.placement(of: key) else { return }
        Task {
            do {
                try await model.mover.move(key, to: placement.returnSection, onlyFrom: .visible)
                forget([key])
                schedule()
            } catch {
                model.toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Ends the placements of items that were moved.
    func forget<Keys: Sequence>(_ keys: Keys) where Keys.Element == MenuItemKey {
        let keys = Set(keys)
        guard model.settings.temporaryPlacements.contains(where: { keys.contains($0.itemKey) }) else { return }
        model.settings.temporaryPlacements.removeAll { keys.contains($0.itemKey) }
        for key in keys {
            failures[key] = nil
        }
    }

    /// Puts back the items whose time is up, and checks again when the next
    /// one is due, at least every minute (timers do not count sleep).
    func schedule() {
        timer?.cancel()
        timer = nil
        putBackDueItems()
        guard let delay = model.settings.temporaryPlacements.delayUntilNextCheck(at: Date()) else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.schedule()
        }
    }

    private func putBackDueItems() {
        let now = Date()
        for placement in model.settings.temporaryPlacements where placement.until <= now {
            let key = placement.itemKey
            guard !puttingBack.contains(key) else { continue }
            if let failure = failures[key], failure.retryAfter > now { continue }
            guard let item = model.inventory.item(for: key) else {
                // Its app is not running; it goes back once the app is.
                if now.timeIntervalSince(placement.until) > Self.patience {
                    forget([key])
                }
                continue
            }
            guard item.section == .visible else {
                // The person moved it elsewhere meanwhile.
                forget([key])
                continue
            }
            // Zen keeps the menu bar still; the item goes back afterwards.
            guard !model.isZenActive else { continue }
            putBack(placement, name: item.displayName)
        }
    }

    private func putBack(_ placement: TemporaryPlacement, name: String) {
        let key = placement.itemKey
        puttingBack.insert(key)
        Task { [weak self] in
            guard let self else { return }
            do {
                // The move ends the placement once the item is back.
                try await self.model.mover.move(key, to: placement.returnSection, automatic: true, onlyFrom: .visible)
                self.forget([key])
            } catch {
                Log.move.error("Putting back \(key.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                let count = (self.failures[key]?.count ?? 0) + 1
                if count >= Self.attempts {
                    self.forget([key])
                    self.model.toasts.show(
                        String(localized: "Meno could not put \(name) back. \(error.localizedDescription)"),
                        symbol: "exclamationmark.triangle.fill"
                    )
                } else {
                    self.failures[key] = (count, Date().addingTimeInterval(5 * 60))
                }
            }
            self.puttingBack.remove(key)
            self.schedule()
        }
    }
}
