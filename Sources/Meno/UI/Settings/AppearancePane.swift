import MenoCore
import SwiftUI

struct AppearancePane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var spacing: SpacingController

    @State private var draftSpacing = IconSpacing()
    @State private var confirmingRelaunch = false

    private let iconColumns = [GridItem(.adaptive(minimum: 88), spacing: 10)]

    var body: some View {
        VStack(spacing: 16) {
            iconCard
            dividerCard
            shelfCard
            tintCard
            spacingCard
        }
        .onAppear {
            draftSpacing = model.settings.spacing.isDefault ? SpacingController.storedSpacing() : model.settings.spacing
        }
    }

    // MARK: Icon

    private var iconCard: some View {
        SettingsCard("Meno icon", symbol: "menubar.rectangle") {
            ToggleRow(
                "Show the Meno icon in the menu bar",
                subtitle: "Without it, click, hover or scroll over an empty part of the menu bar, or use a hotkey. Right-click an empty part for Meno's menu, and open Meno again for Settings.",
                isOn: Binding(get: { model.settings.appearance.showsMenoIcon }, set: { model.setShowsMenoIcon($0) })
            )
            LazyVGrid(columns: iconColumns, spacing: 10) {
                ForEach(MenoIcon.allCases, id: \.self) { icon in
                    let selected = model.settings.appearance.icon == icon
                    Button {
                        model.settings.appearance.icon = icon
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                let symbol = model.settings.appearance.customIconSymbol
                                Image(nsImage: MenoIconRenderer.toggleImage(for: icon, customSymbol: symbol, revealed: false))
                                Image(nsImage: MenoIconRenderer.toggleImage(for: icon, customSymbol: symbol, revealed: true))
                                    .opacity(0.55)
                            }
                            .foregroundStyle(.primary)
                            .frame(height: 22)
                            Text(verbatim: icon.title)
                                .font(.system(size: 11))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(!model.settings.appearance.showsMenoIcon)
            .opacity(model.settings.appearance.showsMenoIcon ? 1 : 0.45)
            if model.settings.appearance.icon == .custom, model.settings.appearance.showsMenoIcon {
                CustomIconPicker(symbol: $model.settings.appearance.customIconSymbol)
            }
        }
    }

    private var dividerCard: some View {
        SettingsCard("Dividers", symbol: "chevron.left.2") {
            ToggleRow(
                "Show the dividers while items are revealed",
                subtitle: "Dividers mark where each section starts. Drag them with ⌘ to change what is hidden.",
                isOn: $model.settings.appearance.showsDividers
            )
            SettingRow("Style") {
                HStack(spacing: 10) {
                    Image(nsImage: MenoIconRenderer.dividerImage(model.settings.appearance.dividerGlyph, double: false))
                    Image(nsImage: MenoIconRenderer.dividerImage(model.settings.appearance.dividerGlyph, double: true))
                    EnumPicker(selection: $model.settings.appearance.dividerGlyph, title: \.title, width: 200, segmented: true)
                }
            }
        }
    }

    // MARK: Shelf

    private var shelfCard: some View {
        SettingsCard("Shelf", symbol: "rectangle.topthird.inset.filled") {
            SettingRow("Glass", subtitle: AppInfo.hasLiquidGlass ? nil : "Clear glass needs macOS 26 or later.") {
                EnumPicker(selection: $model.settings.shelf.material, title: \.title, width: 180, segmented: true)
            }
            SettingRow("Tint") {
                HStack(spacing: 8) {
                    Toggle("Tint", isOn: Binding(
                        get: { model.settings.shelf.tint != nil },
                        set: { model.settings.shelf.tint = $0 ? RGBAColor(red: 0.36, green: 0.47, blue: 1, alpha: 0.5) : nil }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    if model.settings.shelf.tint != nil {
                        ColorPicker("Tint color", selection: Binding(
                            get: { model.settings.shelf.tint?.color ?? .blue },
                            set: { model.settings.shelf.tint = RGBAColor(nsColor: NSColor($0)) }
                        ), supportsOpacity: true)
                        .labelsHidden()
                    }
                }
            }
            SliderRow("Icon size", value: $model.settings.shelf.iconSize, in: 14...30, step: 1) { value in
                "\(Int(value)) pt"
            }
            ToggleRow("Show names under the icons", isOn: $model.settings.shelf.showsLabels)
            ToggleRow("Include the Stash", isOn: $model.settings.shelf.includesStash)
            ToggleRow("Close after opening an item", isOn: $model.settings.shelf.closesAfterAction)
            SettingRow("Position") {
                EnumPicker(selection: $model.settings.shelf.placement, title: \.title)
            }
            HStack {
                Spacer()
                Button("Preview Shelf") {
                    model.shelf.show(includeStash: false, trigger: .menu)
                }
                .menoGlassButtonStyle()
            }
        }
    }

    // MARK: Tint

    private var tintCard: some View {
        SettingsCard(
            "Menu bar tint",
            symbol: "paintbrush",
            badge: .experimental,
            footnote: "The tint sits behind the menu bar. It is most visible with a transparent menu bar, as on macOS 26 and later."
        ) {
            ToggleRow("Tint the menu bar", isOn: $model.settings.tint.enabled)
            if model.settings.tint.enabled {
                SettingRow(
                    "Colors",
                    subtitle: model.settings.tint.colorSource == .wallpaper
                        ? "The colors of the wallpaper under the menu bar, which keep it as easy to read as the wallpaper. A moving wallpaper gets your own colors."
                        : nil
                ) {
                    EnumPicker(selection: $model.settings.tint.colorSource, title: \.title, width: 240, segmented: true)
                }
                SettingRow("Fill") {
                    HStack(spacing: 8) {
                        if model.settings.tint.colorSource == .custom {
                            ColorPicker("Fill", selection: $model.settings.tint.color.colorBinding, supportsOpacity: true)
                                .labelsHidden()
                            if model.settings.tint.fill == .gradient {
                                ColorPicker("Gradient end color", selection: $model.settings.tint.secondaryColor.colorBinding, supportsOpacity: true)
                                    .labelsHidden()
                            }
                        }
                        EnumPicker(selection: $model.settings.tint.fill, title: \.title, width: 160, segmented: true)
                    }
                }
                if model.settings.tint.colorSource == .wallpaper {
                    SliderRow("Strength", value: $model.settings.tint.wallpaperOpacity, in: 0.1...1, step: 0.05) { value in
                        value.formatted(.percent.precision(.fractionLength(0)))
                    }
                }
                if model.settings.tint.colorSource == .custom {
                    ToggleRow("Other colors in Dark Mode", isOn: $model.settings.tint.usesDarkColors)
                }
                if model.settings.tint.colorSource == .custom, model.settings.tint.usesDarkColors {
                    SettingRow("Fill in Dark Mode") {
                        HStack(spacing: 8) {
                            ColorPicker("Fill in Dark Mode", selection: $model.settings.tint.darkColor.colorBinding, supportsOpacity: true)
                                .labelsHidden()
                            if model.settings.tint.fill == .gradient {
                                ColorPicker("Gradient end color in Dark Mode", selection: $model.settings.tint.darkSecondaryColor.colorBinding, supportsOpacity: true)
                                    .labelsHidden()
                            }
                        }
                    }
                }
                SettingRow("Shape") {
                    EnumPicker(selection: $model.settings.tint.shape, title: \.title, width: 240, segmented: true)
                }
                ToggleRow("Border", isOn: $model.settings.tint.border)
                if model.settings.tint.border {
                    SettingRow("Border color") {
                        ColorPicker("Border color", selection: $model.settings.tint.borderColor.colorBinding, supportsOpacity: true)
                            .labelsHidden()
                    }
                    SliderRow("Border width", value: $model.settings.tint.borderWidth, in: 0.5...3, step: 0.5) { value in
                        String(format: "%.1f pt", value)
                    }
                }
                ToggleRow("Shadow", isOn: $model.settings.tint.shadow)
            }
        }
    }

    // MARK: Spacing

    private var spacingCard: some View {
        SettingsCard(
            "Icon spacing",
            symbol: "arrow.left.and.right",
            badge: .beta,
            footnote: "macOS applies the spacing when an app starts, so apps with menu bar items are quit and reopened. Save your work in them first."
        ) {
            SliderRow("Space between icons", value: spacingBinding(\.spacing, default: IconSpacing.defaultSpacing), in: 0...24, step: 1) { value in
                "\(Int(value)) pt"
            }
            SliderRow("Highlight padding", value: spacingBinding(\.padding, default: IconSpacing.defaultPadding), in: 0...24, step: 1) { value in
                "\(Int(value)) pt"
            }
            HStack(spacing: 10) {
                Button("Use System Default") {
                    draftSpacing = IconSpacing()
                }
                .menoGlassButtonStyle()
                Spacer()
                if spacing.isApplying {
                    ProgressView().controlSize(.small)
                }
                Button("Save Only") {
                    Task { await spacing.apply(draftSpacing, relaunchApps: false) }
                }
                .menoGlassButtonStyle()
                .disabled(spacing.isApplying)
                Button("Apply & Relaunch Apps…") {
                    confirmingRelaunch = true
                }
                .menoGlassButtonStyle(prominent: true)
                .disabled(spacing.isApplying)
            }
        }
        .confirmationDialog("Relaunch apps to apply the new spacing?", isPresented: $confirmingRelaunch) {
            Button("Relaunch Apps") {
                Task { await spacing.apply(draftSpacing, relaunchApps: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: spacing.affectedApps.compactMap(\.localizedName).joined(separator: ", "))
        }
    }

    private func spacingBinding(_ keyPath: WritableKeyPath<IconSpacing, Int?>, default value: Int) -> Binding<Double> {
        Binding(
            get: { Double(draftSpacing[keyPath: keyPath] ?? value) },
            set: { draftSpacing[keyPath: keyPath] = Int($0.rounded()) }
        )
    }
}

/// Picks the SF Symbol of the custom Meno icon, from a few suggestions or
/// by name.
private struct CustomIconPicker: View {
    @Binding var symbol: String
    @State private var name = ""

    static let suggestions = [
        "star", "heart", "bolt", "leaf", "moon", "sun.max", "sparkle", "flame", "drop", "cloud",
        "circle.grid.2x2", "square.grid.2x2", "line.3.horizontal", "ellipsis", "command", "eye",
        "tray", "archivebox", "shippingbox", "rectangle.stack", "hare", "tortoise", "cat", "bird",
    ]

    private let columns = [GridItem(.adaptive(minimum: 34), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.suggestions.filter(MenoIconRenderer.symbolExists), id: \.self) { suggestion in
                    let selected = suggestion == symbol
                    Button {
                        symbol = suggestion
                        name = suggestion
                    } label: {
                        Image(systemName: suggestion)
                            .font(.system(size: 14))
                            .frame(width: 30, height: 26)
                            .background {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.2)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: suggestion))
                    .accessibilityLabel(Text(verbatim: suggestion))
                }
            }
            SettingRow("SF Symbol name", subtitle: isKnown ? "Any symbol from the SF Symbols app. While items are shown, its filled variant is used when there is one." : "macOS has no symbol with this name.") {
                TextField("SF Symbol name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit(apply)
                    .onChange(of: name) { apply() }
            }
        }
        .onAppear { name = symbol }
    }

    private var isKnown: Bool {
        MenoIconRenderer.symbolExists(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func apply() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MenoIconRenderer.symbolExists(trimmed), trimmed != symbol else { return }
        symbol = trimmed
    }
}
