import MenoCore
import SwiftUI

/// Drag-and-drop editor for the menu bar layout.
struct LayoutPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var inventory: ItemInventory
    @ObservedObject var images: ItemImageCache
    @ObservedObject var mover: ItemMover
    @ObservedObject var permissions: PermissionCenter

    @State private var targetedSection: ItemSection?
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
                tip("hand.draw", "Drag an item to another section, or next to another item to change the order.")
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
            .disabled(inventory.isRefreshing)

            Button {
                savingScene = true
            } label: {
                Label("Save as Scene…", systemImage: "square.stack.3d.up")
            }
            .menoGlassButtonStyle()

            Spacer()
            if inventory.isRefreshing {
                ProgressView().controlSize(.small)
            } else if let date = inventory.lastRefresh {
                Text("Updated \(Formatters.relative(date))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lane(for section: ItemSection) -> some View {
        let items = inventory.items(in: section)
        return VStack(alignment: .leading, spacing: 12) {
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
                Spacer(minLength: 12)
                Text(section.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 330, alignment: .trailing)
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
                    ForEach(items) { item in
                        LayoutChip(item: item, image: images.image(for: item)) { key, placement in
                            model.move(key, placement: placement)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .menoGlass(
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            tint: targetedSection == section ? section.color.opacity(0.6) : nil
        )
        .dropDestination(for: String.self) { keys, _ in
            guard let raw = keys.first, let key = MenuItemKey(rawValue: raw) else { return false }
            if inventory.item(for: key)?.section != section {
                model.move(key, to: section)
            }
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                targetedSection = section
            } else if targetedSection == section {
                targetedSection = nil
            }
        }
        .animation(.easeOut(duration: 0.15), value: targetedSection)
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

/// A draggable item in the layout editor. Dropping another item on it
/// places that item to its left or right, depending on the drop position.
private struct LayoutChip: View {
    let item: MenuBarItem
    let image: NSImage
    let onDrop: (MenuItemKey, Placement) -> Void

    @State private var width: CGFloat = 100
    @State private var dropEdge: HorizontalEdge?

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text(verbatim: item.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if !item.isMovable {
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
                .fill(Color.primary.opacity(0.07))
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
        .draggable(item.key.rawValue) {
            HStack(spacing: 6) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(verbatim: item.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(8)
        }
        .dropDestination(for: String.self) { keys, location in
            dropEdge = nil
            guard let raw = keys.first, let key = MenuItemKey(rawValue: raw), key != item.key else { return false }
            let token: LayoutToken = item.isMovable ? .item(item.key) : .anchor("pinned:\(item.key.rawValue)")
            onDrop(key, location.x < width / 2 ? .leftOf(token) : .rightOf(token))
            return true
        } isTargeted: { isTargeted in
            dropEdge = isTargeted ? .trailing : nil
        }
        .help(Text(verbatim: item.bundleID ?? item.appName))
    }
}
