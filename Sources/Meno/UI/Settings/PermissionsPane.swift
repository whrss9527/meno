import SwiftUI

struct PermissionsPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var permissions: PermissionCenter

    var body: some View {
        VStack(spacing: 16) {
            PermissionCard(
                title: "Accessibility",
                symbol: "hand.raised.fill",
                isGranted: permissions.accessibility,
                isRequired: true,
                explanation: "Lets Meno read the items in the menu bar, open them from the Shelf, Quick Open and hotkeys, and arrange them with ⌘-drag.",
                grant: { permissions.requestAccessibility() },
                openSettings: { permissions.open(.accessibility) }
            )
            if !permissions.accessibility {
                Banner(
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .orange,
                    title: "Already switched on?",
                    message: "After an update, System Settings can still list an earlier build of Meno, which no longer counts. Reset the entry, then turn Meno on when macOS asks.",
                    actionTitle: "Reset and Grant Again",
                    action: { model.resetAccessibility() }
                )
            }
            PermissionCard(
                title: "Screen Recording",
                symbol: "rectangle.dashed.badge.record",
                isGranted: permissions.screenRecording,
                isRequired: false,
                explanation: "Optional. Shows the real artwork of hidden items instead of app icons (macOS 14 to 26). Meno only captures menu bar items, never your screen.",
                grant: { permissions.requestScreenRecording() },
                openSettings: { permissions.open(.screenRecording) }
            )
            if permissions.screenRecordingNeedsRelaunch {
                Banner(
                    symbol: "arrow.clockwise.circle.fill",
                    tint: .blue,
                    title: "Relaunch to finish",
                    message: "macOS applies Screen Recording access after Meno restarts.",
                    actionTitle: "Relaunch Meno",
                    action: { Relauncher.relaunch() }
                )
            }
            SettingsCard("Privacy", symbol: "lock.shield") {
                Text("Meno works on your Mac, with no analytics and no accounts. It only goes online to ask GitHub for the latest release, when you check for updates or once a day if you turned that on. Usage statistics and settings are stored in ~/Library/Application Support/Meno.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !AppInfo.isBundled {
                    Label("Meno is running outside an app bundle, so macOS attributes permissions to the program that started it. Use “make run” for an app bundle.", systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct PermissionCard: View {
    let title: LocalizedStringKey
    let symbol: String
    let isGranted: Bool
    let isRequired: Bool
    let explanation: LocalizedStringKey
    let grant: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isGranted ? Color.green : (isRequired ? Color.orange : Color.accentColor))
                .frame(width: 40, height: 40)
                .background {
                    Circle().fill((isGranted ? Color.green : (isRequired ? Color.orange : Color.accentColor)).opacity(0.14))
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(isRequired ? "Required" : "Optional")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .foregroundStyle(.secondary)
                        .background { Capsule().fill(Color.primary.opacity(0.07)) }
                }
                Text(explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if isGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access…", action: grant)
                            .menoGlassButtonStyle(prominent: true)
                    }
                    Button("Open System Settings", action: openSettings)
                        .menoGlassButtonStyle()
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .menoGlassCard(cornerRadius: 18)
    }
}
