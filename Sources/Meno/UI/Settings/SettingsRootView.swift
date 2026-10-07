import MenoCore
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var controller: SettingsWindowController
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $controller.pane)
                .frame(width: 222)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PaneHeader(pane: controller.pane)
                    if model.settings.usesNewerSchema {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Settings from a newer Meno")
                                .font(.headline)
                            Text("This settings file uses a newer format. Some features may be unavailable. Unrecognized fields are kept when you save.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .menoGlassCard(cornerRadius: 14)
                    }
                    content
                }
                .padding(.horizontal, 26)
                .padding(.top, 30)
                .padding(.bottom, 36)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollContentBackground(.hidden)
            // Over whichever pane is open and wherever it is scrolled to.
            .overlay(alignment: .bottom) {
                MovingCard(mover: model.mover)
            }
        }
        .background {
            ZStack {
                VisualEffectBackground(material: .underWindowBackground)
                AuroraBackground()
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 820, idealWidth: 940, minHeight: 560, idealHeight: 660)
        // A .meno file dropped anywhere on the window shows what it holds.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == ShareFile.fileExtension }) else { return false }
            model.openShareFile(url)
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.pane {
        case .general: GeneralPane()
        case .layout: LayoutPane(inventory: model.inventory, images: model.images, mover: model.mover, permissions: model.permissions)
        case .appearance: AppearancePane(spacing: model.spacing)
        case .hotkeys: HotkeysPane(inventory: model.inventory)
        case .rules: RulesPane(automation: model.automation, inventory: model.inventory)
        case .scenes: ScenesPane(inventory: model.inventory, mover: model.mover)
        case .markers: MarkersPane()
        case .insights: InsightsPane(inventory: model.inventory, images: model.images)
        case .permissions: PermissionsPane(permissions: model.permissions)
        case .about: AboutPane()
        }
    }
}

/// Says that Meno is moving items, while it is.
private struct MovingCard: View {
    @ObservedObject var mover: ItemMover

    var body: some View {
        if mover.isMoving {
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
            .padding(.bottom, 28)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Meno")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Menu bar, calmed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)

            ForEach(Array(SettingsPane.allCases.enumerated()), id: \.element) { index, pane in
                SidebarButton(pane: pane, isSelected: pane == selection, shortcut: index < 9 ? index + 1 : nil) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selection = pane
                    }
                }
            }
            Spacer(minLength: 12)
            SidebarStatus(permissions: model.permissions, inventory: model.inventory) {
                selection = .permissions
            }
        }
        .padding(.top, 44)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .menoGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(10)
    }
}

private struct SidebarButton: View {
    let pane: SettingsPane
    let isSelected: Bool
    /// The number of its ⌘-shortcut.
    let shortcut: Int?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(isHovering ? 0.07 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // The selection already shows where you are; a focus ring on another
        // row looked like a second selection. ⌘1–⌘9 switch panes instead.
        .focusEffectDisabled()
        .keyboardShortcut(shortcut.map { KeyboardShortcut(KeyEquivalent(Character(String($0))), modifiers: .command) })
        .onHover { isHovering = $0 }
    }
}

private struct SidebarStatus: View {
    @ObservedObject var permissions: PermissionCenter
    @ObservedObject var inventory: ItemInventory
    let openPermissions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if permissions.accessibility {
                Label {
                    Text("\(inventory.items.count) items · \(inventory.items(in: .hidden).count + inventory.items(in: .stash).count) tucked away")
                        .font(.system(size: 11))
                } icon: {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                }
                .foregroundStyle(.secondary)
            } else {
                Button(action: openPermissions) {
                    Label {
                        Text("Accessibility access needed")
                            .font(.system(size: 11, weight: .medium))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
    }
}

struct PaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: pane.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .menoGlass(in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(pane.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(pane.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }
}
