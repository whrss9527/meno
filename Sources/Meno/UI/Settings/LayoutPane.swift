import AppKit
import MenoCore
import SwiftUI
import UniformTypeIdentifiers

/// Editor for the menu bar layout. Clicking an item offers where to move it;
/// items can also be dragged into a section or next to another item.
struct LayoutPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var inventory: ItemInventory
    @ObservedObject var images: ItemImageCache
    @ObservedObject var mover: ItemMover
    @ObservedObject var permissions: PermissionCenter

    @State private var targetedSection: ItemSection?
    @State private var draggedKey: MenuItemKey?
    @State private var savingScene = false
    @State private var sceneName = ""
    @State private var isRenaming = false
    @State private var renamingKey: MenuItemKey?
    @State private var newName = ""
    @State private var isNamingGroup = false
    @State private var groupDraftKey: MenuItemKey?
    @State private var groupName = ""

    private var sections: [ItemSection] {
        model.settings.general.stashEnabled ? [.visible, .hidden, .stash] : [.visible, .hidden]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if permissions.needsAccessibilityAgain {
                Banner(
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .orange,
                    title: "Grant access again after the update",
                    message: "System Settings still lists the previous build of Meno, which no longer counts. Reset the entry, then turn Meno on when macOS asks.",
                    actionTitle: "Reset and Grant Again",
                    action: { model.resetAccessibility() }
                )
            } else if !permissions.accessibility {
                Banner(
                    symbol: "hand.raised.fill",
                    tint: .orange,
                    title: "Accessibility access is needed",
                    message: "Meno reads and moves menu bar items through Accessibility.",
                    actionTitle: "Grant Access…",
                    action: { permissions.requestAccessibility() }
                )
            }
            toolbar
            ForEach(sections, id: \.self) { section in
                lane(for: section)
            }
            groupsCard
            SettingsCard("Good to know", symbol: "lightbulb") {
                tip("cursorarrow.click", "Click an item to choose where it goes: another section, or one step to the left or right.")
                tip("hand.draw", "Or drag it onto a section, or onto another item. A line shows on which side it will land.")
                tip("command", "You can also hold ⌘ and drag icons directly in the menu bar. Meno's dividers mark the sections: the single chevron starts the Hidden section, the double chevron the Stash.")
                tip("cursorarrow.motionlines", "While Meno moves an item it briefly takes over the pointer. It puts the pointer back when it is done.")
                tip("bell", "Choose Show When It Changes for a hidden item, and Meno shows it for a moment when its icon or text changes, for example when a sync fails. Icons are compared when Screen Recording is allowed.")
                if AppInfo.osMajorVersion >= 26 {
                    HStack(alignment: .top, spacing: 10) {
                        tip("menubar.arrow.up.rectangle", "An app's items are missing? macOS 26 and later only show the items of apps that are allowed in System Settings › Menu Bar.")
                        Spacer(minLength: 8)
                        Button("Open Menu Bar Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .overlay {
            if mover.isMoving {
                movingOverlay
            }
        }
        .alert("Save Layout as Scene", isPresented: $savingScene) {
            TextField("Name", text: $sceneName)
            Button("Save") {
                let name = sceneName.trimmingCharacters(in: .whitespacesAndNewlines)
                model.saveScene(named: name.isEmpty ? String(localized: "My Layout") : name, symbol: "square.grid.2x2")
                sceneName = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A scene remembers which items are visible, hidden or stashed.")
        }
        .alert("New Group", isPresented: $isNamingGroup) {
            TextField("Name", text: $groupName)
            Button("Create") {
                model.createGroup(named: groupName, with: groupDraftKey)
                groupDraftKey = nil
            }
            Button("Cancel", role: .cancel) { groupDraftKey = nil }
        } message: {
            Text("A group gets its own icon in the menu bar that shows its items. Visible items move to the Stash.")
        }
        .alert("Rename Item", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let key = renamingKey { model.rename(key, to: newName) }
            }
            if let key = renamingKey, model.settings.itemNames[key.rawValue] != nil {
                Button("Use Original Name") { model.rename(key, to: nil) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Meno shows this name in the Shelf, Quick Open, hotkeys and rules. The menu bar itself does not change.")
        }
    }

    private var groupsCard: some View {
        SettingsCard(
            "Groups",
            symbol: "square.grid.2x2",
            footnote: "Each group has its own icon in the menu bar, which shows the group's items in a Shelf. Add items with Group in their menu. Hold ⌘ and drag a group's icon to move it."
        ) {
            if model.settings.groups.isEmpty {
                Text("No groups yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach($model.settings.groups) { $group in
                GroupRow(
                    group: $group,
                    items: group.items.compactMap { inventory.item(for: $0) },
                    images: images,
                    onRemoveItem: { model.removeItemFromGroups($0) },
                    onDelete: { model.deleteGroup(group.id) }
                )
            }
            Button {
                groupName = ""
                groupDraftKey = nil
                isNamingGroup = true
            } label: {
                Label("New Group", systemImage: "plus")
            }
            .menoGlassButtonStyle()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await inventory.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .menoGlassButtonStyle()

            Button {
                savingScene = true
            } label: {
                Label("Save as Scene…", systemImage: "square.stack.3d.up")
            }
            .menoGlassButtonStyle()

            Button {
                model.undoLayoutChange()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .menoGlassButtonStyle()
            .keyboardShortcut("z", modifiers: .command)
            .disabled(mover.undoLayout == nil || mover.isMoving)
            .help(Text("Puts the items back where they were before the last change"))

            Spacer()
            if let date = inventory.lastRefresh {
                Text("Updated \(Formatters.relative(date))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lane(for section: ItemSection) -> some View {
        let items = inventory.items(in: section)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: section.symbol)
                        .foregroundStyle(section.color)
                    Text(section.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(verbatim: "\(items.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background { Capsule().fill(section.color.opacity(0.15)) }
                        .foregroundStyle(section.color)
                }
                Text(section.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if items.isEmpty {
                Text("Drop items here")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                    }
            } else {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        LayoutChip(
                            item: item,
                            image: images.image(for: item),
                            sections: sections,
                            left: index > 0 ? items[index - 1] : nil,
                            right: index + 1 < items.count ? items[index + 1] : nil,
                            draggedKey: $draggedKey,
                            moveToSection: { model.move(item.key, to: $0) },
                            place: { key, placement in model.move(key, placement: placement) },
                            rename: {
                                newName = item.displayName
                                renamingKey = item.key
                                isRenaming = true
                            },
                            showsOnChange: model.showsOnChange(item.key),
                            setShowsOnChange: { model.setShowsOnChange(item.key, $0) },
                            copyLink: { model.copyLink(.open(name: item.key.rawValue, secondary: false)) },
                            addHotkey: {
                                model.hotkeyDraftItem = item.key
                                model.openSettings(.hotkeys)
                            },
                            groups: model.settings.groups,
                            groupID: model.settings.groups.group(containing: item.key)?.id,
                            setGroup: { id in
                                if let id {
                                    model.addItem(item.key, toGroup: id)
                                } else {
                                    model.removeItemFromGroups(item.key)
                                }
                            },
                            newGroup: {
                                groupName = ""
                                groupDraftKey = item.key
                                isNamingGroup = true
                            }
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: items.map(\.key))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .menoGlass(
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            tint: targetedSection == section ? section.color.opacity(0.6) : nil
        )
        .onDrop(of: [.plainText], isTargeted: targetBinding(for: section)) { _ in
            guard let key = draggedKey else { return false }
            draggedKey = nil
            if inventory.item(for: key)?.section != section {
                model.move(key, to: section)
            }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: targetedSection)
    }

    private func targetBinding(for section: ItemSection) -> Binding<Bool> {
        Binding {
            targetedSection == section
        } set: { isTargeted in
            if isTargeted {
                targetedSection = section
            } else if targetedSection == section {
                targetedSection = nil
            }
        }
    }

    private func tip(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var movingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            if let progress = mover.progress, progress.total > 1 {
                Text("Moving item \(min(progress.done + 1, progress.total)) of \(progress.total)…")
                    .font(.system(size: 14, weight: .semibold))
            } else {
                Text("Moving…")
                    .font(.system(size: 14, weight: .semibold))
            }
            Text("Please leave the mouse alone for a moment.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .menoGlassCard(cornerRadius: 22)
    }
}

/// An item in the layout editor. Clicking it shows where it can be moved,
/// and it can be dragged. Dropping another item on it places that item on
/// the side where it was dropped.
private struct LayoutChip: View {
    let item: MenuBarItem
    let image: NSImage
    /// The sections shown in the editor.
    let sections: [ItemSection]
    /// The items next to this one in its section.
    let left: MenuBarItem?
    let right: MenuBarItem?
    /// The item being dragged in the editor.
    @Binding var draggedKey: MenuItemKey?
    let moveToSection: (ItemSection) -> Void
    let place: (MenuItemKey, Placement) -> Void
    let rename: () -> Void
    /// Whether the item is shown for a moment when it changes.
    let showsOnChange: Bool
    let setShowsOnChange: (Bool) -> Void
    let copyLink: () -> Void
    let addHotkey: () -> Void
    /// All groups, and the one the item is in.
    let groups: [ItemGroup]
    let groupID: UUID?
    /// Puts the item in a group, or takes it out with `nil`.
    let setGroup: (UUID?) -> Void
    let newGroup: () -> Void

    @State private var dropEdge: HorizontalEdge?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(menuItemImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text(verbatim: item.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if showsOnChange && item.section != .visible {
                Image(systemName: "bell.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .help(Text("Shown for a moment when it changes"))
            }
            Image(systemName: item.isMovable ? "chevron.down" : "lock.fill")
                .font(.system(size: item.isMovable ? 8 : 9, weight: item.isMovable ? .bold : .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 220)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.12 : 0.07))
        }
        .overlay(alignment: dropEdge == .leading ? .leading : .trailing) {
            if dropEdge != nil {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 3)
                    .offset(x: dropEdge == .leading ? -5 : 5)
            }
        }
        .overlay {
            ChipMouseArea(
                key: item.key,
                label: "\(item.displayName), \(item.section.title)",
                toolTip: item.isMovable ? (item.bundleID ?? item.appName) : String(localized: "macOS keeps this item in place"),
                makeMenu: makeMenu,
                makeDragImage: { ChipMouseView.dragImage(icon: image, name: item.displayName) },
                onHover: { isHovering = $0 },
                onDragStart: { draggedKey = item.key },
                onDragEnd: { draggedKey = nil },
                onDropEdge: { dropEdge = $0 },
                onDrop: { key, edge in
                    place(key, edge == .leading ? .leftOf(item.layoutToken) : .rightOf(item.layoutToken))
                }
            )
        }
    }

    /// Moves to the other sections, and one step left or right. macOS keeps
    /// fixed items at the right end, so they are never passed.
    private var commands: [MoveCommand] {
        func renameCommand(startsGroup: Bool = true) -> MoveCommand {
            MoveCommand(title: String(localized: "Rename…"), symbol: "pencil", startsGroup: startsGroup, action: rename)
        }
        let copyLinkCommand = MoveCommand(title: String(localized: "Copy Link"), symbol: "link", action: copyLink)
        let hotkeyCommand = MoveCommand(title: String(localized: "Add Shortcut…"), symbol: "keyboard", action: addHotkey)
        var groupEntries = groups.map { group in
            MoveCommand(title: group.name, symbol: group.symbol, isChecked: group.id == groupID) {
                setGroup(group.id == groupID ? nil : group.id)
            }
        }
        groupEntries.append(MoveCommand(title: String(localized: "New Group…"), symbol: "plus", startsGroup: true, action: newGroup))
        let groupCommand = MoveCommand(title: String(localized: "Group"), symbol: "square.grid.2x2", children: groupEntries)
        guard item.isMovable else {
            return [
                MoveCommand(title: String(localized: "macOS keeps this item in place"), symbol: "lock.fill", isEnabled: false) {},
                renameCommand(),
                groupCommand,
                hotkeyCommand,
                copyLinkCommand,
            ]
        }
        var result = sections.filter { $0 != item.section }.map { section in
            MoveCommand(title: section.moveTitle, symbol: section.symbol) { moveToSection(section) }
        }
        result.append(MoveCommand(title: String(localized: "Move Left"), symbol: "arrow.left", isEnabled: left?.isMovable == true, startsGroup: true) {
            if let left { place(item.key, .leftOf(left.layoutToken)) }
        })
        result.append(MoveCommand(title: String(localized: "Move Right"), symbol: "arrow.right", isEnabled: right?.isMovable == true) {
            if let right { place(item.key, .rightOf(right.layoutToken)) }
        })
        if item.section != .visible {
            result.append(MoveCommand(
                title: String(localized: "Show When It Changes"),
                symbol: "bell",
                isChecked: showsOnChange,
                startsGroup: true
            ) { setShowsOnChange(!showsOnChange) })
            result.append(renameCommand(startsGroup: false))
        } else {
            result.append(renameCommand())
        }
        result.append(groupCommand)
        result.append(hotkeyCommand)
        result.append(copyLinkCommand)
        return result
    }

    /// The commands as a menu, shown on click and on right-click.
    private func makeMenu() -> NSMenu {
        MoveCommand.menu(from: commands)
    }
}

/// One entry of an item's menu in the layout editor.
private struct MoveCommand: Identifiable {
    let title: String
    let symbol: String
    var isEnabled = true
    var isChecked = false
    /// Whether a separator comes before this entry.
    var startsGroup = false
    /// Entries of a submenu, instead of an action.
    var children: [MoveCommand] = []
    var action: () -> Void = {}

    var id: String { title }

    static func menu(from commands: [MoveCommand]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for command in commands {
            if command.startsGroup, !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let entry: NSMenuItem
            if command.children.isEmpty {
                let handler = MenuActionHandler(command.action)
                entry = NSMenuItem(title: command.title, action: #selector(MenuActionHandler.invoke), keyEquivalent: "")
                entry.target = handler
                entry.representedObject = handler
            } else {
                entry = NSMenuItem(title: command.title, action: nil, keyEquivalent: "")
                entry.submenu = Self.menu(from: command.children)
            }
            entry.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
            entry.isEnabled = command.isEnabled
            entry.state = command.isChecked ? .on : .off
            menu.addItem(entry)
        }
        return menu
    }
}

/// Takes the mouse over an item in the layout editor.
///
/// SwiftUI gestures there lost clicks and drags to the window, which moved
/// instead, so an AppKit view handles them: a click opens the item's menu,
/// a drag starts a drag session, and dropping another item on it reports
/// the side it landed on.
private struct ChipMouseArea: NSViewRepresentable {
    let key: MenuItemKey
    /// What VoiceOver reads for the item.
    let label: String
    let toolTip: String
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
        view.makeMenu = makeMenu
        view.makeDragImage = makeDragImage
        view.onHover = onHover
        view.onDragStart = onDragStart
        view.onDragEnd = onDragEnd
        view.onDropEdge = onDropEdge
        view.onDrop = onDrop
    }
}

private final class ChipMouseView: NSView, NSDraggingSource {
    var key: MenuItemKey?
    var label = ""
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
        guard !isDragging, let start = mouseDownPoint, let key else { return }
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
        guard let dragged = draggedKey(sender), dragged != key else { return false }
        onDrop(dragged, edge(of: sender))
        return true
    }

    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let dragged = draggedKey(sender), dragged != key else {
            onDropEdge(nil)
            return []
        }
        onDropEdge(edge(of: sender))
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


/// A group in the layout editor: its icon, name and items.
private struct GroupRow: View {
    @Binding var group: ItemGroup
    let items: [MenuBarItem]
    @ObservedObject var images: ItemImageCache
    let onRemoveItem: (MenuItemKey) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(ItemGroup.symbols, id: \.self) { symbol in
                        Button {
                            group.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                        }
                    }
                } label: {
                    Image(systemName: group.symbol)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(Text("Icon"))
                TextField("Name", text: $group.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text("Delete Group"))
            }
            if items.isEmpty {
                Text("Empty. Choose Group in an item's menu to add it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 5) {
                            Image(menuItemImage: images.image(for: item))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                            Text(verbatim: item.displayName)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Button {
                                onRemoveItem(item.key)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(Text("Remove from Group"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(Color.primary.opacity(0.07)) }
                    }
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }
}
