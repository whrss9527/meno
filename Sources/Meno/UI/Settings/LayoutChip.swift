import AppKit
import MenoCore
import SwiftUI

/// An item in the layout editor. Clicking it shows where it can be moved,
/// and it can be dragged. Dropping another item on it places that item on
/// the side where it was dropped.
struct LayoutChip: View {
    let item: MenuBarItem
    let image: NSImage
    /// The sections shown in the editor.
    let sections: [ItemSection]
    /// The items next to this one in its section.
    let left: MenuBarItem?
    let right: MenuBarItem?
    /// The item being dragged in the editor.
    @Binding var draggedKey: MenuItemKey?
    /// Whether Meno is moving items, when nothing else can be dragged.
    let isBusy: Bool
    /// Whether Meno is moving this item right now.
    let isMoving: Bool
    let moveToSection: (ItemSection) -> Void
    let place: (MenuItemKey, Placement) -> Void
    let rename: () -> Void
    /// Whether the item is shown for a moment when it changes.
    let showsOnChange: Bool
    let setShowsOnChange: (Bool) -> Void
    let copyLink: () -> Void
    let addHotkey: () -> Void
    /// The symbol picked for the item, if any.
    let symbol: String?
    let setSymbol: (String?) -> Void
    /// All groups, and the one the item is in.
    let groups: [ItemGroup]
    let groupID: UUID?
    /// Puts the item in a group, or takes it out with `nil`.
    let setGroup: (UUID?) -> Void
    let newGroup: () -> Void
    /// When the item goes back, while it is shown for a while.
    let temporaryUntil: Date?
    let showForAWhile: (TimeInterval) -> Void
    let putBack: () -> Void

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
            if let temporaryUntil {
                Image(systemName: "timer")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .help(Text("Goes back at \(temporaryUntil.formatted(date: .omitted, time: .shortened))"))
            }
            if let group = groups.first(where: { $0.id == groupID }) {
                Image(systemName: group.symbol)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .help(Text("In the group “\(group.name)”"))
            }
            if isMoving {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: item.isMovable ? "chevron.down" : "lock.fill")
                    .font(.system(size: item.isMovable ? 8 : 9, weight: item.isMovable ? .bold : .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 220)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.12 : 0.07))
        }
        // The item being dragged stays where it is, faded, until it lands.
        .opacity(draggedKey == item.key ? 0.4 : 1)
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
                label: accessibilityLabel,
                toolTip: item.isMovable ? (item.bundleID ?? item.appName) : String(localized: "macOS keeps this item in place"),
                canDrag: item.isMovable && !isBusy,
                accepts: { accepts($0, on: $1) },
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

    /// Whether dropping `dragged` on a side of this item would move it: not
    /// next to where it already is, and not right of an item macOS keeps at
    /// the right end.
    private func accepts(_ dragged: MenuItemKey, on edge: HorizontalEdge) -> Bool {
        guard !isBusy else { return false }
        switch edge {
        case .leading: return left?.key != dragged
        case .trailing: return item.isMovable && right?.key != dragged
        }
    }

    /// The item's name and section, and when it goes back if it is shown for
    /// a while.
    private var accessibilityLabel: String {
        var label = "\(item.displayName), \(item.section.title)"
        if let temporaryUntil {
            label += ", " + String(localized: "Goes back at \(temporaryUntil.formatted(date: .omitted, time: .shortened))")
        }
        return label
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
        var symbolEntries = Self.symbolChoices.map { name in
            MoveCommand(title: "", symbol: name, isChecked: name == symbol) { setSymbol(name) }
        }
        symbolEntries.append(MoveCommand(title: String(localized: "Use Its Own Icon"), symbol: "arrow.uturn.backward", isEnabled: symbol != nil, startsGroup: true) {
            setSymbol(nil)
        })
        let symbolCommand = MoveCommand(title: String(localized: "Icon"), symbol: "star.square", children: symbolEntries)
        guard item.isMovable else {
            return [
                MoveCommand(title: String(localized: "macOS keeps this item in place"), symbol: "lock.fill", isEnabled: false) {},
                renameCommand(),
                symbolCommand,
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
        // A marker only has a place; it cannot be opened, change or join a
        // group.
        if item.kind == .marker {
            return result
        }
        if item.section != .visible {
            result.append(MoveCommand(
                title: String(localized: "Show for a While"),
                symbol: "timer",
                startsGroup: true,
                children: TemporaryPlacement.durations.map { duration in
                    MoveCommand(title: Formatters.duration(duration), symbol: "clock") { showForAWhile(duration) }
                }
            ))
        } else if temporaryUntil != nil {
            result.append(MoveCommand(title: String(localized: "Put Back Now"), symbol: "arrow.uturn.backward", startsGroup: true, action: putBack))
        }
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
        result.append(symbolCommand)
        result.append(groupCommand)
        result.append(hotkeyCommand)
        result.append(copyLinkCommand)
        return result
    }

    /// The commands as a menu, shown on click and on right-click.
    /// Symbols offered to stand for an item.
    static let symbolChoices = [
        "star", "heart", "bolt", "bell", "timer", "calendar", "clock", "cloud", "globe", "network",
        "wifi", "lock", "key", "shield", "battery.100", "externaldrive", "printer", "keyboard",
        "mic", "camera", "music.note", "headphones", "gamecontroller", "paintbrush", "hammer",
        "wrench.and.screwdriver", "gearshape", "doc", "folder", "tray.full", "envelope",
        "bubble.left", "person.crop.circle", "chart.bar", "leaf", "cup.and.saucer",
    ]

    private func makeMenu() -> NSMenu {
        MoveCommand.menu(from: commands)
    }
}

/// One entry of an item's menu in the layout editor.
struct MoveCommand: Identifiable {
    let title: String
    let symbol: String
    var isEnabled = true
    var isChecked = false
    /// Whether a separator comes before this entry.
    var startsGroup = false
    /// Entries of a submenu, instead of an action.
    var children: [MoveCommand] = []
    var action: () -> Void = {}

    var id: String { title + symbol }

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
