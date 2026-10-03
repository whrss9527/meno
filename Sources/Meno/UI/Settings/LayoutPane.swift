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
    @State private var targetedGroup: UUID?
    @State private var isNamingGroup = false
    @State private var groupDraftKey: MenuItemKey?
    @State private var groupName = ""
    /// Finds items by name; the others fade so the layout stays in view.
    @State private var filter = ""
    @FocusState private var filterIsFocused: Bool

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
                tip("cursorarrow.motionlines", "Meno moves items without the pointer where it can. On macOS 27, or when that does not work, it briefly takes over the pointer and puts it back when it is done.")
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
        .alert("Save Layout as Scene", isPresented: $savingScene) {
            TextField("Name", text: $sceneName)
            Button("Save") {
                let name = sceneName.trimmingCharacters(in: .whitespacesAndNewlines)
                model.saveScene(named: name.isEmpty ? String(localized: "My Layout") : name, symbol: "square.grid.2x2")
                sceneName = ""
            }
            Button("Cancel", role: .cancel) { sceneName = "" }
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
            footnote: "Each group has its own icon in the menu bar, which shows the group's items in a Shelf. Add items by dragging them onto a group, or with Group in their menu. Hold ⌘ and drag a group's icon to move it."
        ) {
            if model.settings.groups.isEmpty {
                Text("No groups yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(model.settings.groups) { group in
                let id = group.id
                GroupRow(
                    group: group,
                    update: { change in model.updateGroup(id, change) },
                    items: group.items.compactMap { inventory.item(for: $0) },
                    images: images,
                    isTargeted: targetedGroup == id,
                    onRemoveItem: { model.removeItemFromGroups($0) },
                    onDelete: { model.deleteGroup(id) }
                )
                .onDrop(of: [.plainText], isTargeted: Binding {
                    targetedGroup == id
                } set: { isTargeted in
                    if isTargeted {
                        targetedGroup = id
                    } else if targetedGroup == id {
                        targetedGroup = nil
                    }
                }) { _ in
                    guard let key = draggedKey else { return false }
                    draggedKey = nil
                    model.addItem(key, toGroup: id)
                    return true
                }
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
            // A scene saved halfway through a move would be half of each.
            .disabled(mover.isMoving)

            Button {
                model.undoLayoutChange()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .menoGlassButtonStyle()
            .keyboardShortcut("z", modifiers: .command)
            .disabled(mover.undoStack.isEmpty || mover.isMoving)
            .help(Text("Puts the items back where they were before the last change. Undo again to go further back."))

            Spacer()
            if let date = inventory.lastRefresh {
                Text("Updated \(Formatters.relative(date))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find an item", text: $filter)
                    .textFieldStyle(.plain)
                    .focused($filterIsFocused)
                    .frame(width: 130)
                    .onExitCommand { filter = "" }
                if !filter.isEmpty {
                    Button {
                        filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear Search"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(Color.primary.opacity(0.07))
            }
            .background {
                // ⌘F puts the cursor in the search field.
                Button("") { filterIsFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .focusable(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Whether an item matches the search, which every item does while the
    /// search is empty.
    private func matchesFilter(_ item: MenuBarItem) -> Bool {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || FuzzyMatcher.bestScore(query, fields: item.searchFields) != nil
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
                            isBusy: mover.isMoving,
                            isMoving: mover.movingKey == item.key,
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
                            symbol: model.settings.itemSymbols[item.key.rawValue],
                            setSymbol: { model.setSymbol($0, for: item.key) },
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
                            },
                            temporaryUntil: model.temporary.returnDate(of: item.key),
                            showForAWhile: { model.temporary.show(item.key, for: $0) },
                            putBack: { model.temporary.putBack(item.key) }
                        )
                        .opacity(matchesFilter(item) ? 1 : 0.25)
                        // VoiceOver skips the items the search leaves out.
                        .accessibilityHidden(!matchesFilter(item))
                        .overlay {
                            if !filter.isEmpty, matchesFilter(item) {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                    .allowsHitTesting(false)
                            }
                        }
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
            // Dropped where it already is, the item goes back to its place.
            guard let key = draggedKey, !mover.isMoving, inventory.item(for: key)?.section != section else { return false }
            draggedKey = nil
            model.move(key, to: section)
            return true
        }
        .animation(.easeOut(duration: 0.15), value: targetedSection)
    }

    private func targetBinding(for section: ItemSection) -> Binding<Bool> {
        Binding {
            targetedSection == section
        } set: { isTargeted in
            // Only a section the dragged item would move to lights up.
            let isOwnSection = draggedKey.flatMap { inventory.item(for: $0)?.section } == section
            if isTargeted, !isOwnSection, !mover.isMoving {
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
}
