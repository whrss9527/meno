import MenoCore
import SwiftUI

struct AboutPane: View {
    @EnvironmentObject private var model: AppModel
    /// Other copies of Meno on this Mac, such as "Meno 2" next to "Meno".
    @State private var otherCopies: [URL] = []

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                Text(verbatim: "Meno")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Version \(AppInfo.version) (\(AppInfo.build))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("A calm menu bar, made with glass.")
                    .font(.system(size: 14))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .menoGlassCard(cornerRadius: 24)

            if !otherCopies.isEmpty {
                Banner(
                    symbol: "square.on.square",
                    tint: .orange,
                    title: "Another copy of Meno",
                    message: "Also at \(otherCopyPaths). Keep one: each copy needs its own permissions, and a login item may open the other one.",
                    actionTitle: "Show in Finder",
                    action: { NSWorkspace.shared.activateFileViewerSelecting(otherCopies) }
                )
            }

            LazyVGrid(columns: columns, spacing: 12) {
                Feature(symbol: "eye.slash", title: "Hidden and Stash", text: "Two levels of hiding, revealed by click, hover, scroll or hotkey.")
                Feature(symbol: "rectangle.topthird.inset.filled", title: "Shelf", text: "A glass bar for items that do not fit next to the notch.")
                Feature(symbol: "magnifyingglass", title: "Quick Open", text: "Find and open any item from the keyboard, pinyin included.")
                Feature(symbol: "wand.and.stars", title: "Rules and Scenes", text: "The menu bar adapts to apps, displays, power and time.")
                Feature(symbol: "leaf", title: "Zen", text: "One shortcut clears the menu bar for recordings and talks.")
                Feature(symbol: "chart.bar.xaxis", title: "Insights", text: "Private usage stats with suggestions for a tidier bar.")
                Feature(symbol: "square.grid.2x2", title: "Groups", text: "Items that belong together, behind one icon of their own.")
                Feature(symbol: "bell", title: "Show When It Changes", text: "Hidden items appear for a moment when something happens.")
            }

            SettingsCard("This Mac", symbol: "desktopcomputer") {
                infoRow("macOS", AppInfo.osVersionString)
                infoRow(String(localized: "Hiding engine"), model.statusBar.engine == .stepped ? String(localized: "Stepped") : String(localized: "Wide divider"))
                infoRow(String(localized: "Liquid Glass"), AppInfo.hasLiquidGlass ? String(localized: "Available") : String(localized: "Not available, using frosted glass"))
            }

            UpdateCard(updates: model.updates)

            HStack(spacing: 10) {
                CheckForUpdatesButton(updates: model.updates)
                Link(destination: AppInfo.repositoryURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .menoGlassButtonStyle()
                Link(destination: AppInfo.repositoryURL.appendingPathComponent("issues")) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
                .menoGlassButtonStyle()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Diagnostics.report(for: model), forType: .string)
                    model.toasts.show(String(localized: "Diagnostic report copied. Paste it into an issue or a message."), symbol: "doc.on.clipboard")
                } label: {
                    Label("Copy Diagnostic Report", systemImage: "doc.on.clipboard")
                }
                .menoGlassButtonStyle()
                .help(Text("Copies the macOS version, permissions and the menu bar items Meno sees, to help find problems."))
            }
        }
        .onAppear { otherCopies = SingleInstance.otherCopies }
    }

    private var otherCopyPaths: String {
        otherCopies.map(\.path).joined(separator: ", ")
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .font(.system(size: 12, weight: .medium))
                .textSelection(.enabled)
        }
    }
}

/// Offers a newer release and shows how installing it goes.
private struct UpdateCard: View {
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        if let release = updates.available, let version = release.version {
            SettingsCard("Update Available", symbol: "arrow.down.circle") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Meno \(version.description) is available.")
                            .font(.system(size: 13, weight: .semibold))
                        note
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    switch updates.phase {
                    case .downloading, .installing:
                        ProgressView()
                            .controlSize(.small)
                        Group {
                            if updates.phase == .downloading {
                                Text("Downloading…")
                            } else {
                                Text("Installing…")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    case .idle, .checking:
                        Button("Release Notes") {
                            NSWorkspace.shared.open(release.htmlURL)
                        }
                        .menoGlassButtonStyle()
                        if updates.canInstall {
                            Button("Install and Relaunch") {
                                Task { await updates.install() }
                            }
                            .menoGlassButtonStyle(prominent: true)
                            .disabled(updates.phase != .idle)
                        } else {
                            Button("Download") {
                                NSWorkspace.shared.open(release.htmlURL)
                            }
                            .menoGlassButtonStyle(prominent: true)
                        }
                    }
                }
            }
        }
    }

    private var note: Text {
        if let blocker = UpdateInstaller.blocker {
            return Text(verbatim: blocker.localizedDescription)
        }
        guard updates.canInstall else {
            return Text(verbatim: UpdateInstaller.Failure.noArchive.localizedDescription)
        }
        if CodeSigning.isAdHoc {
            return Text("Meno quits and opens again. macOS then asks you to allow Meno in Accessibility again.")
        }
        return Text("Meno quits and opens again.")
    }
}

private struct CheckForUpdatesButton: View {
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        Button {
            Task { await updates.check(userInitiated: true) }
        } label: {
            Label("Check for Updates", systemImage: "arrow.down.circle")
        }
        .menoGlassButtonStyle()
        .disabled(updates.phase != .idle)
    }
}

private struct Feature: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .menoGlassCard(cornerRadius: 16)
    }
}
