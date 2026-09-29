import AppKit
@preconcurrency import ApplicationServices
import MenoCore

/// A menu bar item as Meno sees it right now.
struct MenuBarItem: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Created by a regular app.
        case app
        /// Created by macOS (Control Center, clock, Spotlight…).
        case system
        /// One of Meno's own markers.
        case marker
    }

    let key: MenuItemKey
    let kind: Kind
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let displayName: String
    let detail: String?
    let identifier: String?
    var frame: CGRect
    var section: ItemSection
    /// Whether macOS lets the item be ⌘-dragged.
    let isMovable: Bool
    let element: AXUIElement?
    /// Extra search terms, such as a romanization of the name.
    let keywords: [String]
    let markerID: UUID?

    var id: MenuItemKey { key }

    var span: HorizontalSpan {
        HorizontalSpan(minX: Double(frame.minX), maxX: Double(frame.maxX))
    }

    var runningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: pid)
    }

    var searchFields: [String] {
        [displayName, appName] + keywords
    }

    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.key == rhs.key
            && lhs.frame == rhs.frame
            && lhs.section == rhs.section
            && lhs.displayName == rhs.displayName
            && lhs.pid == rhs.pid
            && sameElement(lhs.element, rhs.element)
    }

    /// An app can replace its item with a new one in the same place; the
    /// old element then no longer answers.
    private static func sameElement(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return CFEqual(lhs, rhs)
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

extension MenuBarItem {
    /// How layout plans refer to the item. Items macOS keeps in place are
    /// anchors that other items line up against.
    var layoutToken: LayoutToken {
        isMovable ? .item(key) : .anchor("pinned:\(key.rawValue)")
    }

    /// Whether the item is currently drawn on one of the screens.
    @MainActor
    var isOnScreen: Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        return NSScreen.screens.contains { screen in
            let bounds = ScreenGeometry.quartzRect(fromCocoa: screen.frame)
            return bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }
}
