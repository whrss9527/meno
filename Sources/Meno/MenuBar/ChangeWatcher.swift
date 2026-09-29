import AppKit
import MenoCore

/// Shows a hidden item for a moment when its icon or text changes, for the
/// items the person picked (for example to notice when a sync fails).
///
/// Texts come from Accessibility. Icons are compared too when Screen
/// Recording is allowed and items can be captured (up to macOS 26).
@MainActor
final class ChangeWatcher {
    unowned let model: AppModel

    /// How long a changed item stays shown.
    static let showDuration: TimeInterval = 6

    private var tracker = ChangeTracker()
    private var loop: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    /// Starts or stops checking to match the settings.
    func settingsChanged() {
        let watching = !model.settings.revealOnChange.isEmpty
        if watching, loop == nil {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await self?.check()
                }
            }
        } else if !watching {
            loop?.cancel()
            loop = nil
            tracker.reset()
        }
    }

    private func check() async {
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
        let absorbing = model.reveal.visibility != .collapsed || model.shelf.isVisible
            || model.mover.isMoving || model.isZenActive
        let changed = tracker.update(samples, at: Date(), absorbing: absorbing)
            .compactMap { model.inventory.item(for: $0) }
        if !changed.isEmpty {
            show(changed)
        }
    }

    private func show(_ items: [MenuBarItem]) {
        Log.menuBar.info("Showing \(items.map(\.key.rawValue).joined(separator: ", "), privacy: .public) after a change")
        model.reveal.requestReveal(all: items.contains { $0.section == .stash }, trigger: .change)
        // A whole section is shown, so the notice says which items changed.
        let names = ListFormatter.localizedString(byJoining: items.map(\.displayName))
        model.toasts.show(String(localized: "\(names) changed."), symbol: "bell.fill", duration: Self.showDuration)
        if model.shelf.isVisible {
            model.shelf.hide(after: Self.showDuration)
        } else {
            model.reveal.scheduleRehide(after: Self.showDuration, force: true)
        }
    }
}
