import MenoCore
import SwiftUI

struct ShelfView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shelf: ShelfController
    @ObservedObject var inventory: ItemInventory
    @ObservedObject var images: ItemImageCache

    private var settings: ShelfSettings { model.settings.shelf }

    var body: some View {
        // Wraps into more rows instead of running off the screen.
        let row = WrappingRow(maxWidth: shelf.maxContentWidth, spacing: 8, lineSpacing: 6)
        GlassGroup(spacing: 10) {
            row {
                if let groupID = shelf.groupID {
                    groupContent(groupID)
                } else {
                    sectionContent
                }
                toolButtons
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .menoGlass(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: settings.tint?.color,
                clear: settings.material == .clear
            )
        }
        .padding(14)
        .fixedSize()
    }

    /// The items of one group, in the group's order.
    @ViewBuilder
    private func groupContent(_ id: UUID) -> some View {
        let group = model.settings.groups.first { $0.id == id }
        let items = (group?.items ?? []).compactMap { inventory.item(for: $0) }.filter { $0.kind != .marker }
        if items.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: group?.symbol ?? "square.grid.2x2")
                    .foregroundStyle(.secondary)
                Text("Nothing in this group yet. Add items from their menu in the layout editor.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        } else {
            ForEach(items) { item in
                ShelfItemButton(item: item, image: images.image(for: item), settings: settings, shelf: shelf)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        let crowded = shelf.crowdedItems
        let hidden = shelf.openableItems(in: .hidden)
        let stash = shelf.includesStash && model.settings.general.stashEnabled ? shelf.openableItems(in: .stash) : []
        if crowded.isEmpty && hidden.isEmpty && stash.isEmpty {
            emptyState
        } else {
            ForEach(crowded) { item in
                ShelfItemButton(item: item, image: images.image(for: item), settings: settings, shelf: shelf)
            }
            if !crowded.isEmpty && !hidden.isEmpty {
                separator.help(Text("Items on the left do not fit into the menu bar"))
            }
            ForEach(hidden) { item in
                ShelfItemButton(item: item, image: images.image(for: item), settings: settings, shelf: shelf)
            }
            if !stash.isEmpty {
                separator.help(Text("Stash"))
                ForEach(stash) { item in
                    ShelfItemButton(item: item, image: images.image(for: item), settings: settings, shelf: shelf)
                }
            }
        }
    }

    private var separator: some View {
        Capsule()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 1.5, height: CGFloat(settings.iconSize) + 6)
            .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
            Text("Nothing is hidden")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
    }

    private var toolButtons: some View {
        HStack(spacing: 2) {
            ShelfToolButton(symbol: "magnifyingglass", help: "Quick Open") {
                shelf.hide()
                model.quickOpen.show()
            }
            ShelfToolButton(symbol: "rectangle.3.group", help: "Arrange Menu Bar") {
                shelf.hide()
                model.openSettings(.layout)
            }
        }
        .padding(.leading, 4)
    }
}

private struct ShelfItemButton: View {
    let item: MenuBarItem
    let image: NSImage
    let settings: ShelfSettings
    @ObservedObject var shelf: ShelfController

    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(settings.iconSize)
        VStack(spacing: 3) {
            Image(menuItemImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: image.isTemplate ? size : size + 4, height: image.isTemplate ? size : size + 4)
                .foregroundStyle(.primary)
            if settings.showsLabels {
                Text(item.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .frame(maxWidth: 76)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.12 : 0))
        }
        .overlay {
            if shelf.keyboardSelection == item.key {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            shelf.hoveredKey = hovering ? item.key : nil
        }
        .onTapGesture {
            let secondary = NSEvent.modifierFlags.contains(.control)
            shelf.open(item, secondary: secondary)
        }
        .contextMenu {
            Button("Open") { shelf.open(item, secondary: false) }
            Button("Open Secondary Menu") { shelf.open(item, secondary: true) }
            Divider()
            if item.section != .visible {
                Button("Keep Visible") {
                    shelf.hide()
                    shelf.model.move(item.key, to: .visible)
                }
            }
            if item.section != .hidden {
                Button("Move to Hidden") {
                    shelf.hide()
                    shelf.model.move(item.key, to: .hidden)
                }
            }
            if item.section != .stash, shelf.model.settings.general.stashEnabled {
                Button("Move to Stash") {
                    shelf.hide()
                    shelf.model.move(item.key, to: .stash)
                }
            }
            if let group = shelf.model.settings.groups.group(containing: item.key) {
                Button("Remove from “\(group.name)”") {
                    shelf.model.removeItemFromGroups(item.key)
                }
            }
            if item.section != .visible {
                Divider()
                Toggle("Show When It Changes", isOn: Binding(
                    get: { shelf.model.showsOnChange(item.key) },
                    set: { shelf.model.setShowsOnChange(item.key, $0) }
                ))
            }
        }
        .help(Text(verbatim: item.displayName))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.displayName))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { shelf.open(item, secondary: false) }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct ShelfToolButton: View {
    let symbol: String
    let help: LocalizedStringKey
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .background {
                    Circle().fill(Color.primary.opacity(isHovering ? 0.12 : 0.05))
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(Text(help))
    }
}

/// Lays views out left to right in rows no wider than `maxWidth`, like
/// words in a paragraph.
private struct WrappingRow: Layout {
    var maxWidth: CGFloat
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func arrange(_ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
