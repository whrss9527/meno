import AppKit
import MenoCore
import SwiftUI

/// Takes the mouse over an item in the layout editor.
///
/// SwiftUI gestures there lost clicks and drags to the window, which moved
/// instead, so an AppKit view handles them: a click opens the item's menu,
/// a drag starts a drag session, and dropping another item on it reports
/// the side it landed on.
struct ChipMouseArea: NSViewRepresentable {
    let key: MenuItemKey
    /// What VoiceOver reads for the item.
    let label: String
    let toolTip: String
    /// Whether the item can be dragged: macOS keeps some items in place, and
    /// nothing is dragged while Meno moves items.
    let canDrag: Bool
    /// Whether dropping an item on a side would move it anywhere.
    let accepts: (MenuItemKey, HorizontalEdge) -> Bool
    let makeMenu: () -> NSMenu
    let makeDragImage: () -> NSImage
    let onHover: (Bool) -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onDropEdge: (HorizontalEdge?) -> Void
    let onDrop: (MenuItemKey, HorizontalEdge) -> Void

    func makeNSView(context: Context) -> ChipMouseView {
        let view = ChipMouseView()
        view.registerForDraggedTypes([.string])
        return view
    }

    func updateNSView(_ view: ChipMouseView, context: Context) {
        view.key = key
        view.label = label
        view.toolTip = toolTip
        view.canDrag = canDrag
        view.accepts = accepts
        view.makeMenu = makeMenu
        view.makeDragImage = makeDragImage
        view.onHover = onHover
        view.onDragStart = onDragStart
        view.onDragEnd = onDragEnd
        view.onDropEdge = onDropEdge
        view.onDrop = onDrop
    }
}

final class ChipMouseView: NSView, NSDraggingSource {
    var key: MenuItemKey?
    var label = ""
    var canDrag = true
    var accepts: (MenuItemKey, HorizontalEdge) -> Bool = { _, _ in true }
    var makeMenu: () -> NSMenu = { NSMenu() }
    var makeDragImage: () -> NSImage = { NSImage() }
    var onHover: (Bool) -> Void = { _ in }
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onDropEdge: (HorizontalEdge?) -> Void = { _ in }
    var onDrop: (MenuItemKey, HorizontalEdge) -> Void = { _, _ in }

    private var mouseDownPoint: NSPoint?
    private var isDragging = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover(false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: Click and drag

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard canDrag, !isDragging, let start = mouseDownPoint, let key else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
        isDragging = true
        onDragStart()
        let image = makeDragImage()
        let item = NSDraggingItem(pasteboardWriter: key.rawValue as NSString)
        item.setDraggingFrame(NSRect(origin: .zero, size: image.size), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !isDragging, mouseDownPoint != nil else { return }
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeMenu()
    }

    // MARK: Accessibility

    // The view covers the chip, so it stands for the item: VoiceOver reads
    // its name and section, and pressing it opens the same menu as a click.

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .menuButton }

    override func accessibilityLabel() -> String? { label }

    override func accessibilityPerformPress() -> Bool {
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        accessibilityPerformPress()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        mouseDownPoint = nil
        onDragEnd()
    }

    // MARK: Dropping another item

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropEdge(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDropEdge(nil)
        let side = edge(of: sender)
        guard let dragged = draggedKey(sender), dragged != key, accepts(dragged, side) else { return false }
        onDrop(dragged, side)
        return true
    }

    /// Shows the side a drop would land on, where it would move the item.
    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        let side = edge(of: sender)
        guard let dragged = draggedKey(sender), dragged != key, accepts(dragged, side) else {
            onDropEdge(nil)
            return []
        }
        onDropEdge(side)
        return .move
    }

    private func draggedKey(_ sender: NSDraggingInfo) -> MenuItemKey? {
        sender.draggingPasteboard.string(forType: .string).flatMap { MenuItemKey(rawValue: $0) }
    }

    private func edge(of sender: NSDraggingInfo) -> HorizontalEdge {
        convert(sender.draggingLocation, from: nil).x < bounds.midX ? .leading : .trailing
    }

    // MARK: Drag image

    /// The item's icon and name on a rounded plate.
    static func dragImage(icon: NSImage, name: String) -> NSImage {
        let text = NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ])
        let textSize = text.size()
        let size = NSSize(width: ceil(textSize.width) + 40, height: 28)
        let glyph = icon.isTemplate ? tinted(icon) : icon
        return NSImage(size: size, flipped: false) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
            glyph.draw(in: NSRect(x: 8, y: (rect.height - 16) / 2, width: 16, height: 16))
            text.draw(at: NSPoint(x: 30, y: (rect.height - textSize.height) / 2))
            return true
        }
    }

    /// Template images are black; menu bar icons need the label color.
    private static func tinted(_ image: NSImage) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
