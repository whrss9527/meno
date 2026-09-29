import MenoCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionCenter
    let finish: (_ openLayout: Bool) -> Void
    @EnvironmentObject private var model: AppModel

    @State private var page = 0
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: welcome
                case 1: sections
                case 2: access
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 40)
            .transition(.opacity)
            .id(page)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color.primary.opacity(0.18))
                            .frame(width: index == page ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) { page -= 1 }
                    }
                    .menoGlassButtonStyle()
                }
                if page < pageCount - 1 {
                    Button("Continue") {
                        withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
                    }
                    .menoGlassButtonStyle(prominent: true)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { finish(false) }
                        .menoGlassButtonStyle()
                    Button("Arrange My Menu Bar") { finish(true) }
                        .menoGlassButtonStyle(prominent: true)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .animation(.easeInOut(duration: 0.2), value: page)
        }
        .frame(width: 680, height: 540)
        .background {
            ZStack {
                VisualEffectBackground(material: .underWindowBackground)
                AuroraBackground(intensity: 1.3)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            Text("Welcome to Meno")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Meno keeps your menu bar calm. Hide the icons you rarely need, bring them back in a click, and keep everything reachable from the keyboard.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    pill("eye.slash", "Hide")
                    pill("rectangle.topthird.inset.filled", "Shelf")
                    pill("magnifyingglass", "Quick Open")
                    pill("wand.and.stars", "Rules")
                    pill("leaf", "Zen")
                }
            }
            .padding(.top, 6)
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Three sections")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Meno adds a few small dividers to your menu bar. Everything left of a divider belongs to that section.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            MenuBarDiagram()
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ItemSection.allCases, id: \.self) { section in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: section.symbol)
                            .foregroundStyle(section.color)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: section.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(verbatim: section.explanation)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Hold ⌘ and drag icons across the dividers, or use Meno's Layout pane.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A little access")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("macOS asks you to approve these. Meno works locally and sends nothing about you anywhere.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            accessRow(
                title: "Accessibility",
                detail: "Required to read, open and arrange menu bar items.",
                symbol: "hand.raised.fill",
                granted: permissions.accessibility,
                action: { permissions.requestAccessibility() }
            )
            accessRow(
                title: "Screen Recording",
                detail: "Optional. Shows the real icons of hidden items on macOS 14 to 26.",
                symbol: "rectangle.dashed.badge.record",
                granted: permissions.screenRecording,
                action: { permissions.requestScreenRecording() }
            )
            if permissions.screenRecordingNeedsRelaunch {
                Text("Relaunch Meno later to use Screen Recording.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("You're all set")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            tip("cursorarrow.click", "Click the Meno icon to show or hide items.")
            tip("option", "⌥-click it to include the Stash.")
            tip("contextualmenu.and.cursorarrow", "Right-click it for Quick Open, Zen, Scenes and Settings.")
            tip("keyboard", "Set up shortcuts in Settings › Hotkeys, and open any item with Quick Open.")
            tip("rectangle.3.group", "Arrange items by dragging them in Settings › Layout.")
            tip("square.grid.2x2", "Put items that belong together into a group with an icon of its own, from an item's menu in Settings › Layout.")
            // New versions can be installed from within Meno once it knows of them.
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .menoGlass(in: Circle())
                Toggle(isOn: $model.settings.general.checksForUpdates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for updates once a day")
                            .font(.system(size: 13))
                        Text("Meno asks GitHub whether there is a newer release. Nothing about you or your Mac is sent.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func pill(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .menoGlass(in: Capsule())
    }

    private func tip(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .menoGlass(in: Circle())
            Text(text)
                .font(.system(size: 13))
        }
    }

    private func accessRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        symbol: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(granted ? Color.green : Color.accentColor)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button("Grant…", action: action)
                    .menoGlassButtonStyle(prominent: true)
            }
        }
        .padding(14)
        .menoGlassCard(cornerRadius: 16)
    }
}

/// A small drawing of a menu bar with Meno's dividers.
private struct MenuBarDiagram: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "applelogo")
            Text("Finder").font(.system(size: 12, weight: .semibold))
            Spacer()
            group(["music.note", "cloud"], color: ItemSection.stash.color)
            Image(systemName: "chevron.left.2").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            group(["paperplane", "bolt.horizontal", "globe"], color: ItemSection.hidden.color)
            Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            group(["wifi", "battery.75"], color: ItemSection.visible.color)
            Image(nsImage: MenoIconRenderer.menoGlyph(revealed: true))
            Text(verbatim: "9:41").font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .menoGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func group(_ symbols: [String], color: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background { Capsule().fill(color.opacity(0.18)) }
    }
}
