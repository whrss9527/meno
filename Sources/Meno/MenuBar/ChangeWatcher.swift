import AppKit
import MenoCore

/// Shows a hidden item for a moment when its icon or text changes, for the
/// items the person picked (for example to notice when a sync fails).
///
/// Texts come from Accessibility. Icons are compared too when Screen
/// Recording is allowed and items can be captured (up to macOS 26).
@MainActor
final class ChangeWatcher: ObservableObject {
    unowned let model: AppModel

    /// How long a changed item stays shown.
    private var showDuration: TimeInterval {
        min(max(model.settings.reveal.changeDuration, 2), 60)
    }

    /// Items that changed since the person last saw them. The Meno icon
    /// and the Shelf mark them until they are opened or shown.
    @Published private(set) var changedItems: Set<MenuItemKey> = []

    private var tracker = ChangeTracker()
    private var loop: Task<Void, Never>?
    /// Until when items are shown because they changed. Changes of other
    /// watched items meanwhile are still news.
    private var showingChangesUntil = Date.distantPast

    init(model: AppModel) {
        self.model = model
    }

    /// Starts or stops checking to match the settings.
    func settingsChanged() {
        let watching = !model.settings.revealOnChange.isEmpty
        if watching, loop == nil {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    // Low Power Mode asks apps to do less in the background.
                    let seconds: UInt64 = ProcessInfo.processInfo.isLowPowerModeEnabled ? 10 : 3
                    try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                    await self?.check()
                }
            }
        } else if !watching {
            loop?.cancel()
            loop = nil
            tracker.reset()
        }
        let watched = Set(model.settings.revealOnChange.compactMap(MenuItemKey.init(rawValue:)))
        markSeen(changedItems.subtracting(watched))
    }

    /// Takes the marks off items the person opened or looked at.
    func markSeen<Keys: Sequence>(_ keys: Keys) where Keys.Element == MenuItemKey {
        let remaining = changedItems.subtracting(keys)
        guard remaining != changedItems else { return }
        changedItems = remaining
        model.statusBar.refreshAppearance()
    }

    private func check() async {
        // Nobody sees the menu bar while the displays sleep.
        guard !model.isAway else { return }
        // Items that are gone or visible now need no mark.
        markSeen(changedItems.filter { key in
            model.inventory.item(for: key).map { $0.section == .visible } ?? true
        })
        let keys = Set(model.settings.revealOnChange.compactMap(MenuItemKey.init(rawValue:)))
        let items = model.inventory.items.filter {
            keys.contains($0.key) && $0.section != .visible && $0.kind != .marker && $0.element != nil
        }
        guard model.permissions.accessibility, !items.isEmpty else {
            _ = tracker.update([:], at: Date())
            return
        }
        let texts = await MenuBarScanner.texts(of: items.compactMap(\.element))
        var glyphs: [MenuItemKey: GlyphSignature] = [:]
        if model.permissions.screenRecording, ItemImageCache.captureIsSupported {
            let requests = items.filter { $0.frame.width > 0 }.map { WindowCapture.Request(key: $0.key, frame: $0.frame) }
            for (key, image) in await WindowCapture.captureItems(requests) {
                glyphs[key] = WindowCapture.signature(of: image)
            }
        }
        var samples: [MenuItemKey: ChangeTracker.Sample] = [:]
        for (item, itemTexts) in zip(items, texts) {
            samples[item.key] = ChangeTracker.Sample(texts: itemTexts, glyph: glyphs[item.key])
        }
        // While items are shown or rearranged they may be in use, so what
        // changes then is not news.
        let revealed = model.reveal.visibility != .collapsed || model.shelf.isVisible
        if !revealed {
            // Hidden again: a later reveal is the person's.
            showingChangesUntil = .distantPast
        }
        // An open menu highlights its item, which is no change either.
        let showingChanges = revealed && Date() < showingChangesUntil && !WindowCapture.anyMenuOpen()
        let absorbing = (revealed && !showingChanges) || model.mover.isMoving || model.isZenActive
        let changed = tracker.update(samples, at: Date(), absorbing: absorbing)
            .compactMap { model.inventory.item(for: $0) }
        if !changed.isEmpty {
            show(changed)
        }
    }

    private func show(_ items: [MenuBarItem]) {
        Log.menuBar.info("Showing \(items.map(\.key.rawValue).joined(separator: ", "), privacy: .public) after a change")
        changedItems.formUnion(items.map(\.key))
        showingChangesUntil = Date().addingTimeInterval(showDuration)
        model.reveal.requestReveal(all: items.contains { $0.section == .stash }, trigger: .change)
        // A whole section is shown, so the notice says which items changed.
        let names = ListFormatter.localizedString(byJoining: items.map(\.displayName))
        model.toasts.show(String(localized: "\(names) changed."), symbol: "bell.fill", duration: showDuration)
        if model.shelf.isVisible {
            model.shelf.hide(after: showDuration)
        } else {
            model.reveal.scheduleRehide(after: showDuration, force: true)
        }
        model.statusBar.refreshAppearance()
    }
}
