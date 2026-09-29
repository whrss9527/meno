import MenoCore
import SwiftUI

struct HotkeysPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var inventory: ItemInventory

    @State private var newItemKey: MenuItemKey = .placeholder
    @State private var newCombo: KeyCombo?
    @State private var newClick: ClickKind = .primary

    var body: some View {
        content
            .onAppear(perform: takeDraftItem)
            .onChange(of: model.hotkeyDraftItem) { _, _ in takeDraftItem() }
    }

    /// Picks the item chosen in the layout editor for a new shortcut.
    private func takeDraftItem() {
        guard let key = model.hotkeyDraftItem else { return }
        newItemKey = key
        model.hotkeyDraftItem = nil
    }

    private var content: some View {
        VStack(spacing: 16) {
            SettingsCard("Global shortcuts", symbol: "command", footnote: "Shortcuts work in every app. Press Delete while recording to remove one, or Escape to cancel.") {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    SettingRow(LocalizedStringKey(action.title)) {
                        ShortcutRecorder(combo: Binding(
                            get: { model.settings.hotkeys[action] },
                            set: { model.settings.hotkeys[action] = $0 }
                        ))
                    }
                }
                if !conflicts.isEmpty {
                    Label("Some shortcuts are used more than once. Only one of them will work.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                if !model.refusedHotkeys.isEmpty {
                    Label("macOS did not accept the shortcuts shown in orange. Another app may already use them.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }

            SettingsCard("Item shortcuts", symbol: "keyboard", footnote: "Open a specific menu bar item from anywhere, even while it is hidden.") {
                if model.settings.itemHotkeys.isEmpty {
                    Text("No item shortcuts yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                ForEach($model.settings.itemHotkeys) { $binding in
                    HStack(spacing: 10) {
                        itemLabel(binding.itemKey)
                        Spacer()
                        EnumPicker(selection: $binding.click, title: \.title, width: 150)
                        ShortcutRecorder(combo: Binding(
                            get: { binding.combo },
                            set: { combo in
                                if let combo {
                                    binding.combo = combo
                                } else {
                                    let id = binding.id
                                    model.settings.itemHotkeys.removeAll { $0.id == id }
                                }
                            }
                        ))
                        Button {
                            model.settings.itemHotkeys.removeAll { $0.id == binding.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Remove"))
                    }
                }
                Divider().opacity(0.4)
                HStack(spacing: 10) {
                    ItemPicker(selection: $newItemKey, items: inventory.items.filter { $0.kind != .marker })
                    EnumPicker(selection: $newClick, title: \.title, width: 150)
                    ShortcutRecorder(combo: $newCombo)
                    Spacer()
                    Button("Add") {
                        guard let combo = newCombo, newItemKey != .placeholder else { return }
                        model.settings.itemHotkeys.append(ItemHotkey(itemKey: newItemKey, combo: combo, click: newClick))
                        newCombo = nil
                        newItemKey = .placeholder
                    }
                    .menoGlassButtonStyle(prominent: true)
                    .disabled(newCombo == nil || newItemKey == .placeholder)
                }
            }
        }
    }

    private var conflicts: Set<KeyCombo> {
        model.settings.hotkeys.conflicts(with: model.settings.itemHotkeys, groupHotkeys: model.settings.groups.compactMap(\.hotkey))
    }

    private func itemLabel(_ key: MenuItemKey) -> some View {
        let item = inventory.item(for: key)
        return HStack(spacing: 8) {
            if let item {
                Image(menuItemImage: model.images.image(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: item?.displayName ?? model.settings.itemNames[key.rawValue] ?? AppDirectory.name(for: key.owner))
                .font(.system(size: 13))
                .lineLimit(1)
        }
    }
}
