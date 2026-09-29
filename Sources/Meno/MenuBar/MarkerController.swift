import AppKit
import MenoCore

/// Keeps the user's markers (spaces, lines, symbols, labels) in the menu bar.
@MainActor
final class MarkerController {
    unowned let model: AppModel
    private var items: [UUID: NSStatusItem] = [:]

    init(model: AppModel) {
        self.model = model
    }

    func sync() {
        let markers = model.settings.markers
        let ids = Set(markers.map(\.id))
        for (id, item) in items where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            items[id] = nil
        }
        for marker in markers {
            let item = items[marker.id] ?? makeItem(for: marker)
            configure(item, for: marker)
        }
    }

    private func makeItem(for marker: MenuMarker) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = marker.autosaveName
        item.isVisible = true
        items[marker.id] = item
        return item
    }

    private func configure(_ item: NSStatusItem, for marker: MenuMarker) {
        guard let button = item.button else { return }
        button.image = nil
        button.title = ""
        button.imagePosition = .imageOnly
        switch marker.kind {
        case .space:
            item.length = CGFloat(max(marker.width, 2))
        case .line:
            item.length = 9
            button.image = MenoIconRenderer.dividerImage(.line, double: false)
        case .dot:
            item.length = 10
            button.image = MenoIconRenderer.dividerImage(.dot, double: false)
        case .symbol:
            item.length = NSStatusItem.variableLength
            button.image = MenoIconRenderer.symbol(marker.symbol, pointSize: 13)
                ?? MenoIconRenderer.symbol("star.fill", pointSize: 13)
        case .text:
            item.length = NSStatusItem.variableLength
            button.imagePosition = .noImage
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.title = marker.text.isEmpty ? "•" : marker.text
        }
        button.setAccessibilityLabel(marker.displayName)
        button.toolTip = String(localized: "Meno marker — ⌘-drag to move it")
    }

    /// Current frames of the markers in Quartz coordinates.
    func frames() -> [UUID: CGRect] {
        var result: [UUID: CGRect] = [:]
        for (id, item) in items {
            guard let window = item.button?.window, window.frame.width > 0 else { continue }
            result[id] = ScreenGeometry.quartzRect(fromCocoa: window.frame)
        }
        return result
    }

    func inventoryItems(sections: [UUID: ItemSection]) -> [MenuBarItem] {
        let frames = frames()
        return model.settings.markers.compactMap { marker in
            guard let frame = frames[marker.id] else { return nil }
            return MenuBarItem(
                key: MenuItemKey(owner: AppInfo.bundleIdentifier, token: "marker:\(marker.id.uuidString)"),
                kind: .marker,
                pid: AppInfo.ownPID,
                bundleID: AppInfo.bundleIdentifier,
                appName: "Meno",
                displayName: marker.displayName,
                detail: nil,
                identifier: nil,
                frame: frame,
                section: sections[marker.id] ?? .visible,
                isMovable: true,
                element: nil,
                keywords: [],
                markerID: marker.id
            )
        }
    }
}
