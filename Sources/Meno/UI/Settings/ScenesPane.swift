import MenoCore
import SwiftUI

struct ScenesPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var inventory: ItemInventory
    @ObservedObject var mover: ItemMover

    @State private var newName = ""
    @State private var newSymbol = "briefcase"
    @State private var renaming: LayoutScene?
    @State private var renameText = ""

    static let symbols = [
        "briefcase", "house", "cup.and.saucer", "gamecontroller", "airplane", "graduationcap",
        "display.2", "laptopcomputer", "moon.stars", "sun.max", "music.note", "paintbrush",
        "hammer", "leaf", "bolt", "square.grid.2x2",
    ]

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 14)]

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard("Save the current layout", symbol: "plus.square.on.square", footnote: "A scene remembers the section and order of every movable item. Applying it moves items back with ⌘-drag. Items of apps that are not running are skipped.") {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Button {
                                newSymbol = symbol
                            } label: {
                                Label(symbol, systemImage: symbol)
                            }
                        }
                    } label: {
                        Image(systemName: newSymbol)
                    }
                    .fixedSize()
                    TextField("Scene name, for example Work", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save Scene", action: save)
                        .menoGlassButtonStyle(prominent: true)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                let layout = inventory.currentLayout()
                Text("Right now: \(layout.visible.count) visible, \(layout.hidden.count) hidden, \(layout.stash.count) stashed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if model.settings.scenes.isEmpty {
                Text("No scenes yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(model.settings.scenes) { scene in
                        SceneCard(
                            scene: scene,
                            isActive: model.activeSceneID == scene.id,
                            isBusy: mover.isMoving,
                            onApply: { Task { await model.applyScene(scene) } },
                            onUpdate: { model.updateScene(id: scene.id) },
                            onRename: {
                                renameText = scene.name
                                renaming = scene
                            },
                            onCopyLink: { model.copyLink(.scene(name: scene.name)) },
                            onDelete: { model.deleteScene(id: scene.id) },
                            hotkey: Binding(
                                get: { scene.hotkey },
                                set: { combo in
                                    guard let index = model.settings.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
                                    model.settings.scenes[index].hotkey = combo
                                }
                            )
                        )
                    }
                }
            }
        }
        .alert("Rename Scene", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let scene = renaming,
                   let index = model.settings.scenes.firstIndex(where: { $0.id == scene.id }),
                   !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.settings.scenes[index].name = renameText
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.saveScene(named: name, symbol: newSymbol)
        newName = ""
    }
}

private struct SceneCard: View {
    let scene: LayoutScene
    let isActive: Bool
    let isBusy: Bool
    let onApply: () -> Void
    let onUpdate: () -> Void
    let onRename: () -> Void
    let onCopyLink: () -> Void
    let onDelete: () -> Void
    @Binding var hotkey: KeyCombo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: scene.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background { Circle().fill(Color.accentColor.opacity(0.14)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: scene.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("Updated \(Formatters.relative(scene.updatedAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Update from Current Layout", action: onUpdate)
                    Button("Rename…", action: onRename)
                    Button("Copy Link", action: onCopyLink)
                        .help(Text("A meno:// link that applies this scene, for Shortcuts and launchers"))
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            HStack(spacing: 6) {
                countBadge(scene.layout.visible.count, section: .visible)
                countBadge(scene.layout.hidden.count, section: .hidden)
                countBadge(scene.layout.stash.count, section: .stash)
                Spacer()
                if isActive {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                }
            }
            Button(action: onApply) {
                Text("Apply")
                    .frame(maxWidth: .infinity)
            }
            .menoGlassButtonStyle(prominent: !isActive)
            .disabled(isBusy)
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ShortcutRecorder(combo: $hotkey, purpose: scene.name)
                    .help(Text("A shortcut that applies this scene from anywhere"))
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .menoGlassCard(cornerRadius: 18, tint: isActive ? Color.green.opacity(0.5) : nil)
    }

    private func countBadge(_ count: Int, section: ItemSection) -> some View {
        HStack(spacing: 3) {
            Image(systemName: section.symbol)
            Text(verbatim: "\(count)")
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(section.color)
        .background { Capsule().fill(section.color.opacity(0.13)) }
        .help(Text(section.title))
    }
}
