import AppKit
import MenoCore
import SwiftUI
import UniformTypeIdentifiers

/// A titled glass card that groups related settings.
struct SettingsCard<Content: View>: View {
    enum Badge {
        case beta
        case experimental

        var title: LocalizedStringKey {
            switch self {
            case .beta: return "Beta"
            case .experimental: return "Experimental"
            }
        }

        var color: Color {
            switch self {
            case .beta: return .blue
            case .experimental: return .orange
            }
        }
    }

    let title: LocalizedStringKey
    let symbol: String
    var badge: Badge?
    var footnote: LocalizedStringKey?
    @ViewBuilder var content: () -> Content

    init(
        _ title: LocalizedStringKey,
        symbol: String,
        badge: Badge? = nil,
        footnote: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.badge = badge
        self.footnote = footnote
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let badge {
                    Text(badge.title)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .foregroundStyle(badge.color)
                        .background {
                            Capsule().fill(badge.color.opacity(0.15))
                        }
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 11) {
                content()
            }
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .menoGlassCard(cornerRadius: 18)
    }
}

private struct SettingTitleKey: EnvironmentKey {
    static let defaultValue: LocalizedStringKey? = nil
}

extension EnvironmentValues {
    /// The title of the setting row a control is in, which names the control
    /// for VoiceOver.
    var settingTitle: LocalizedStringKey? {
        get { self[SettingTitleKey.self] }
        set { self[SettingTitleKey.self] = newValue }
    }
}

/// A label on the left, a control on the right.
struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var control: () -> Control

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
                .environment(\.settingTitle, title)
        }
    }
}

struct ToggleRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        SettingRow(title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String

    init(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        SettingRow(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step) {
                    Text(title)
                }
                .labelsHidden()
                .frame(width: 180)
                .controlSize(.small)
                .accessibilityValue(Text(verbatim: format(value)))
                Text(verbatim: format(value))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
        }
    }
}

/// A picker for any `CaseIterable` enum with a localized title.
struct EnumPicker<Value: Hashable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    @Binding var selection: Value
    let title: (Value) -> String
    var width: CGFloat = 230
    var segmented = false
    @Environment(\.settingTitle) private var settingTitle

    var body: some View {
        if segmented {
            picker.pickerStyle(.segmented)
        } else {
            picker.pickerStyle(.menu)
        }
    }

    private var picker: some View {
        Picker(selection: $selection) {
            ForEach(Array(Value.allCases), id: \.self) { value in
                Text(verbatim: title(value)).tag(value)
            }
        } label: {
            if let settingTitle {
                Text(settingTitle)
            }
        }
        .labelsHidden()
        .frame(width: width)
    }
}

/// A notice with an optional action.
struct Banner: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .menoGlassButtonStyle(prominent: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .menoGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: tint)
    }
}

/// Lays out views in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Looks up app names and icons by bundle identifier.
enum AppDirectory {
    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        if let url = url(for: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    static func icon(for bundleID: String) -> NSImage? {
        guard let url = url(for: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    struct Entry: Hashable {
        let bundleID: String
        let name: String
    }

    /// Apps with a user interface that are running now.
    static func runningApps() -> [Entry] {
        let entries = NSWorkspace.shared.runningApplications.compactMap { app -> Entry? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return nil }
            return Entry(bundleID: id, name: app.localizedName ?? id)
        }
        return Array(Set(entries)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Lets the user pick an app from the file system.
    @MainActor
    static func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}

/// A menu that picks an app by bundle identifier.
struct AppPicker: View {
    @Binding var bundleID: String

    var body: some View {
        Menu {
            ForEach(AppDirectory.runningApps(), id: \.self) { app in
                Button(app.name) {
                    bundleID = app.bundleID
                }
            }
            Divider()
            Button("Choose Another App…") {
                if let id = AppDirectory.chooseApp() {
                    bundleID = id
                }
            }
        } label: {
            HStack(spacing: 6) {
                if !bundleID.isEmpty, let icon = AppDirectory.icon(for: bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(verbatim: bundleID.isEmpty ? String(localized: "Choose App") : AppDirectory.name(for: bundleID))
            }
        }
        .frame(width: 200)
    }
}

/// A menu that picks one of the connected displays by name.
struct DisplayPicker: View {
    @Binding var name: String

    var body: some View {
        Menu {
            ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { display in
                Button(display) { name = display }
            }
        } label: {
            Text(verbatim: name.isEmpty ? String(localized: "Choose Display") : name)
        }
        .frame(width: 200)
    }
}

/// A menu that picks a menu bar item.
struct ItemPicker: View {
    @Binding var selection: MenuItemKey
    let items: [MenuBarItem]
    @Environment(\.settingTitle) private var settingTitle

    var body: some View {
        Picker(settingTitle ?? "Item", selection: $selection) {
            if !items.contains(where: { $0.key == selection }) {
                Text(verbatim: selection == .placeholder ? String(localized: "Choose Item") : selection.owner)
                    .tag(selection)
            }
            ForEach(items) { item in
                Text(verbatim: item.displayName).tag(item.key)
            }
        }
        .labelsHidden()
        .frame(width: 220)
    }
}

extension MenuItemKey {
    /// Stands for "no item chosen yet" in editors.
    static let placeholder = MenuItemKey(owner: "none", token: "none")
}
