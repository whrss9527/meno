import AppKit
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
    @State private var isExporting = false

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
                            onExport: { model.exportShare(scenes: [scene.id], rules: []) },
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

            if !model.settings.scenes.isEmpty {
                SettingsCard(
                    "Scenes for displays",
                    symbol: "display.2",
                    footnote: "macOS shows the same items in the same order on the menu bar of every display, so Meno arranges them for the display you use: whenever its menu bar has the items, its scene applies. Each choice is a rule, which Rules lists as well."
                ) {
                    ForEach(displayNames, id: \.self) { display in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: display)
                                    .font(.system(size: 13))
                                if !connectedDisplays.contains(display) {
                                    Text("Not connected")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Picker("Scene", selection: displayScene(display)) {
                                Text("No Scene").tag(UUID?.none)
                                ForEach(model.settings.scenes) { scene in
                                    Text(verbatim: scene.name).tag(UUID?.some(scene.id))
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }

            SettingsCard(
                "Share scenes and rules",
                symbol: "square.and.arrow.up.on.square",
                footnote: "A .meno file holds scenes and rules, for another Mac or for someone else; shortcuts stay here. Open a .meno file, or drop it on this window, to see what it holds before anything is imported."
            ) {
                HStack(spacing: 10) {
                    Button("Export…") { isExporting = true }
                        .disabled(model.settings.scenes.isEmpty && model.settings.rules.isEmpty)
                    Button("Import…") { model.chooseShareFile() }
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $isExporting) {
            ShareExportSheet(inventory: inventory)
                .environmentObject(model)
        }
        .sheet(item: $model.pendingShare) { share in
            ShareImportSheet(share: share, inventory: inventory)
                .environmentObject(model)
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

    /// The connected displays, by the names rules know them by.
    private var connectedDisplays: [String] {
        var names: [String] = []
        for screen in NSScreen.screens where !names.contains(screen.localizedName) {
            names.append(screen.localizedName)
        }
        return names
    }

    /// The connected displays, then those that are not connected but have a
    /// scene.
    private var displayNames: [String] {
        var names = connectedDisplays
        for name in model.settings.rules.displaysWithScenes where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    /// The scene of a display; one that was deleted counts as none.
    private func displayScene(_ display: String) -> Binding<UUID?> {
        Binding {
            model.settings.rules.displayScene(for: display).flatMap { id in
                model.settings.scenes.contains { $0.id == id } ? id : nil
            }
        } set: { scene in
            model.setDisplayScene(scene, for: display)
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
    let onExport: () -> Void
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
                    Button("Export…", action: onExport)
                        .help(Text("Save this scene to a .meno file, for another Mac or for someone else"))
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

/// Chooses the scenes and rules to write to a `.meno` file.
private struct ShareExportSheet: View {
    @ObservedObject var inventory: ItemInventory
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var scenes: Set<UUID> = []
    @State private var rules: Set<UUID> = []
    @State private var didChoose = false

    var body: some View {
        let required = requiredScenes
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Scenes and Rules")
                .font(.system(size: 15, weight: .semibold))
            Text("The scenes that chosen rules apply go along.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !model.settings.scenes.isEmpty {
                        ShareSectionHeader(title: "Scenes")
                        ForEach(model.settings.scenes) { scene in
                            Toggle(isOn: member(scene.id, of: $scenes, required: required)) {
                                Label { Text(verbatim: scene.name) } icon: { Image(systemName: scene.symbol) }
                            }
                            .disabled(required.contains(scene.id))
                        }
                    }
                    if !model.settings.rules.isEmpty {
                        ShareSectionHeader(title: "Rules")
                        ForEach(model.settings.rules) { rule in
                            Toggle(isOn: member(rule.id, of: $rules)) {
                                ShareRuleLabel(rule: rule, scenes: model.settings.scenes, items: inventory.items)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    let chosen = (scenes: scenes, rules: rules)
                    dismiss()
                    // The save panel comes up once the sheet is gone.
                    DispatchQueue.main.async {
                        model.exportShare(scenes: chosen.scenes, rules: chosen.rules)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(scenes.isEmpty && rules.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            guard !didChoose else { return }
            didChoose = true
            scenes = Set(model.settings.scenes.map(\.id))
            rules = Set(model.settings.rules.map(\.id))
        }
    }

    private var requiredScenes: Set<UUID> {
        Set(model.settings.rules.filter { rules.contains($0.id) }.compactMap { rule in
            if case .applyScene(let id) = rule.action { return id }
            return nil
        })
    }
}

/// Shows what a `.meno` file holds and imports what the person chooses.
private struct ShareImportSheet: View {
    let share: PendingShare
    @ObservedObject var inventory: ItemInventory
    @EnvironmentObject private var model: AppModel
    @State private var scenes: Set<UUID>
    @State private var rules: Set<UUID>

    init(share: PendingShare, inventory: ItemInventory) {
        self.share = share
        self.inventory = inventory
        _scenes = State(initialValue: Set(share.file.scenes.map(\.id)))
        _rules = State(initialValue: Set(share.file.rules.map(\.id)))
    }

    var body: some View {
        let file = share.file
        let required = Set(file.rules.filter { rules.contains($0.id) }.flatMap { file.scenes(appliedBy: $0).map(\.id) })
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from “\(share.name)”")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Made with Meno \(file.createdBy)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if file.isFromNewerVersion {
                Label("A newer version of Meno made this file. What this version cannot read is left out.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !file.scenes.isEmpty {
                        ShareSectionHeader(title: "Scenes")
                        ForEach(file.scenes) { scene in
                            Toggle(isOn: member(scene.id, of: $scenes, required: required)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label { Text(verbatim: scene.name) } icon: { Image(systemName: scene.symbol) }
                                    Text(verbatim: detail(of: scene))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(required.contains(scene.id))
                        }
                    }
                    if !file.rules.isEmpty {
                        ShareSectionHeader(title: "Rules")
                        ForEach(file.rules) { rule in
                            Toggle(isOn: member(rule.id, of: $rules)) {
                                ShareRuleLabel(rule: rule, scenes: file.scenes, items: inventory.items)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)
            HStack {
                Spacer()
                Button("Cancel") { model.pendingShare = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { model.importShare(share, scenes: scenes, rules: rules) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(scenes.isEmpty && rules.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func detail(of scene: LayoutScene) -> String {
        let keys = scene.layout.visible + scene.layout.hidden + scene.layout.stash
        let present = keys.filter { inventory.item(for: $0) != nil }
        var text = String(localized: "Items on this Mac: \(present.count) of \(keys.count)")
        let taken = model.settings.scenes.map(\.name)
        if ShareFile.uniqueName(scene.name, among: taken) != scene.name {
            text += " · " + String(localized: "Imported as “\(ShareFile.uniqueName(scene.name, among: taken))”")
        }
        return text
    }
}

private struct ShareSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

private struct ShareRuleLabel: View {
    let rule: AutomationRule
    let scenes: [LayoutScene]
    let items: [MenuBarItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: rule.name.isEmpty ? String(localized: "Untitled Rule") : rule.name)
            Text(verbatim: RuleDescriber.describe(rule, scenes: scenes, items: items))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if rule.runsCommands {
                Label("Runs a command, so it stays off until you turn it on.", systemImage: "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// Whether `id` is in `set`, as a binding for a checkbox. A required member
/// is always in.
private func member(_ id: UUID, of set: Binding<Set<UUID>>, required: Set<UUID> = []) -> Binding<Bool> {
    Binding(
        get: { required.contains(id) || set.wrappedValue.contains(id) },
        set: { isOn in
            if isOn {
                set.wrappedValue.insert(id)
            } else {
                set.wrappedValue.remove(id)
            }
        }
    )
}
