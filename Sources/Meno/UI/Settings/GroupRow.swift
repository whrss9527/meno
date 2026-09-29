import MenoCore
import SwiftUI

/// A group in the layout editor: its icon, name and items.
struct GroupRow: View {
    @Binding var group: ItemGroup
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
}
