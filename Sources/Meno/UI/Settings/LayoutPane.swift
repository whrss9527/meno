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

    private var sections: [ItemSection] {
        model.settings.general.stashEnabled ? [.visible, .hidden, .stash] : [.visible, .hidden]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !permissions.accessibility {
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
            SettingsCard("Good to know", symbol: "lightbulb") {
                tip("cursorarrow.click", "Click an item to choose where it goes: another section, or one step to the left or right.")
                tip("hand.draw", "Or drag it onto a section, or onto another item. A line shows on which side it will land.")
                tip("command", "You can also hold ⌘ and drag icons directly in the menu bar. Meno's dividers mark the sections: the single chevron starts the Hidden section, the double chevron the Stash.")
                tip("cursorarrow.motionlines", "While Meno moves an item it briefly takes over the pointer. It puts the pointer back when it is done.")
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
                            place: { key, placement in model.move(key, placement: placement) }
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

    @State private var width: CGFloat = 100
    @State private var dropEdge: HorizontalEdge?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text(verbatim: item.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if item.isMovable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .help(Text("macOS keeps this item in place"))
            }
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
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        width = newWidth
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { isHovering = $0 }
        .simultaneousGesture(TapGesture().onEnded { showMenu() })
        .onDrag {
            draggedKey = item.key
            return NSItemProvider(object: item.key.rawValue as NSString)
        } preview: {
            HStack(spacing: 6) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(verbatim: item.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(8)
        }
        .onDrop(
            of: [.plainText],
            delegate: ChipDropDelegate(target: item, width: width, draggedKey: $draggedKey, edge: $dropEdge, place: place)
        )
        .contextMenu {
            ForEach(commands) { command in
                if command.startsGroup {
                    Divider()
                }
                Button {
                    command.action()
                } label: {
                    Label(command.title, systemImage: command.symbol)
                }
                .disabled(!command.isEnabled)
            }
        }
        .help(Text(verbatim: item.bundleID ?? item.appName))
    }

    /// Moves to the other sections, and one step left or right. macOS keeps
    /// fixed items at the right end, so they are never passed.
    private var commands: [MoveCommand] {
        guard item.isMovable else {
            return [MoveCommand(title: String(localized: "macOS keeps this item in place"), symbol: "lock.fill", isEnabled: false) {}]
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
        return result
    }

    /// Shows the commands at the pointer, like a context menu.
    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for command in commands {
            if command.startsGroup {
                menu.addItem(.separator())
            }
            let handler = MenuActionHandler(command.action)
            let entry = NSMenuItem(title: command.title, action: #selector(MenuActionHandler.invoke), keyEquivalent: "")
            entry.target = handler
            entry.representedObject = handler
            entry.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
            entry.isEnabled = command.isEnabled
            menu.addItem(entry)
        }
        let location = NSEvent.mouseLocation
        // Opening the menu outside the gesture keeps its tracking loop from
        // running inside SwiftUI's event handling.
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: location, in: nil)
        }
    }
}

/// One entry of an item's menu in the layout editor.
private struct MoveCommand: Identifiable {
    let title: String
    let symbol: String
    var isEnabled = true
    /// Whether a separator comes before this entry.
    var startsGroup = false
    let action: () -> Void

    var id: String { title }
}

/// Shows on which side of an item a dragged item will land, and puts it there.
private struct ChipDropDelegate: DropDelegate {
    let target: MenuBarItem
    let width: CGFloat
    @Binding var draggedKey: MenuItemKey?
    @Binding var edge: HorizontalEdge?
    let place: (MenuItemKey, Placement) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggedKey else { return false }
        return draggedKey != target.key
    }

    func dropEntered(info: DropInfo) {
        edge = side(of: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        edge = side(of: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        edge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        edge = nil
        guard let key = draggedKey, key != target.key else { return false }
        draggedKey = nil
        let token = target.layoutToken
        place(key, side(of: info) == .leading ? .leftOf(token) : .rightOf(token))
        return true
    }

    private func side(of info: DropInfo) -> HorizontalEdge {
        info.location.x < width / 2 ? .leading : .trailing
    }
}
