import Foundation
import MenoCore

/// Shows items in the menu bar for a while and puts them back afterwards.
///
/// The placements are part of the settings, so an item still goes back
/// after Meno or the Mac restarted.
@MainActor
final class TemporaryPlacements {
    unowned let model: AppModel

    private var timer: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    /// When a temporarily shown item goes back, if it is shown for a while.
    func returnDate(of key: MenuItemKey) -> Date? {
        model.settings.temporaryPlacements.placement(of: key)?.until
    }

    /// Shows an item in the menu bar until `duration` has passed. Showing it
    /// again only changes when it goes back.
    func show(_ key: MenuItemKey, for duration: TimeInterval) {
        guard let item = model.inventory.item(for: key), item.isMovable else { return }
        let origin = model.settings.temporaryPlacements.placement(of: key)?.returnSection ?? item.section
        guard origin != .visible else { return }
        model.settings.temporaryPlacements.show(key, from: origin, until: Date().addingTimeInterval(duration))
        if item.section != .visible {
            model.move(key, to: .visible)
        }
        schedule()
    }

    /// Puts an item back now instead of when its time is up.
    func putBack(_ key: MenuItemKey) {
        guard let placement = model.settings.temporaryPlacements.placement(of: key) else { return }
        model.settings.temporaryPlacements.removeAll { $0.itemKey == key }
        if model.inventory.item(for: key)?.section == .visible {
            model.move(key, to: placement.returnSection)
        }
        schedule()
    }

    /// Puts back the items whose time is up, and checks again when the next
    /// one is due, at least every minute (timers do not count sleep).
    func schedule() {
        timer?.cancel()
        timer = nil
        putBackDueItems()
        guard let next = model.settings.temporaryPlacements.nextDue else { return }
        let delay = min(max(next.timeIntervalSinceNow, 1), 60)
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.schedule()
        }
    }

    private func putBackDueItems() {
        let now = Date()
        // Items of apps that are not running wait until they are back.
        let due = model.settings.temporaryPlacements.filter { placement in
            placement.until <= now && model.inventory.item(for: placement.itemKey) != nil
        }
        guard !due.isEmpty else { return }
        let keys = Set(due.map(\.itemKey))
        model.settings.temporaryPlacements.removeAll { keys.contains($0.itemKey) }
        for placement in due {
            // An item the person moved elsewhere meanwhile stays there.
            guard model.inventory.item(for: placement.itemKey)?.section == .visible else { continue }
            let key = placement.itemKey
            Task { [weak model] in
                do {
                    try await model?.mover.move(key, to: placement.returnSection, automatic: true)
                } catch {
                    Log.move.error("Putting back \(key.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
