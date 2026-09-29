import MenoCore
import SwiftUI

/// A group in the layout editor: its icon, name and items.
///
/// Changes go through `update`, which finds the group by its ID when the
/// change is made, so a shortcut recorded while another group is deleted
/// still lands in the right group.
struct GroupRow: View {
    let group: ItemGroup
    let update: ((inout ItemGroup) -> Void) -> Void
    let items: [MenuBarItem]
    @ObservedObject var images: ItemImageCache
    /// Whether an item is being dragged over the group.
    let isTargeted: Bool
    let onRemoveItem: (MenuItemKey) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(ItemGroup.symbols, id: \.self) { symbol in
                        Button {
                            update { $0.symbol = symbol }
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
                TextField("Name", text: Binding(get: { group.name }, set: { name in update { $0.name = name } }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                ShortcutRecorder(combo: Binding(get: { group.hotkey }, set: { combo in update { $0.hotkey = combo } }))
                    .help(Text("A shortcut that shows the group"))
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text("Delete Group"))
            }
            if items.isEmpty {
                Text("Empty. Drag items here, or choose Group in an item's menu.")
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
                        .contextMenu {
                            Button("Move Left") { move(item.key, by: -1) }
                                .disabled(items.first?.key == item.key)
                            Button("Move Right") { move(item.key, by: 1) }
                                .disabled(items.last?.key == item.key)
                            Divider()
                            Button("Remove from Group") { onRemoveItem(item.key) }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isTargeted ? 0.8 : 0), lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    /// Swaps an item with its shown neighbour, which changes where it
    /// appears in the group's Shelf. Items of apps that are not running
    /// keep their place.
    private func move(_ key: MenuItemKey, by offset: Int) {
        guard let shown = items.firstIndex(where: { $0.key == key }), items.indices.contains(shown + offset) else { return }
        let neighbour = items[shown + offset].key
        update { group in
            guard let from = group.items.firstIndex(of: key), let to = group.items.firstIndex(of: neighbour) else { return }
            group.items.swapAt(from, to)
        }
    }
}
