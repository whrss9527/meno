import MenoCore
import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard("Startup", symbol: "power") {
                ToggleRow(
                    "Launch Meno at login",
                    isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
                )
            }

            SettingsCard("Revealing hidden items", symbol: "eye") {
                ToggleRow(
                    "Click an empty part of the menu bar",
                    subtitle: "Clicking again hides the items.",
                    isOn: $model.settings.reveal.onEmptyAreaClick
                )
                ToggleRow("Hover over an empty part of the menu bar", isOn: $model.settings.reveal.onHover)
                if model.settings.reveal.onHover {
                    SliderRow("Hover delay", value: $model.settings.reveal.hoverDelay, in: 0...1.5, step: 0.05, format: Formatters.seconds)
                }
                ToggleRow(
                    "Scroll or swipe over the menu bar",
                    subtitle: "Swipe down to show, swipe up to hide.",
                    isOn: $model.settings.reveal.onScroll
                )
                Divider().opacity(0.4)
                SettingRow("Show hidden items", subtitle: "The Shelf keeps items reachable when the menu bar is full, for example next to the camera housing.") {
                    EnumPicker(selection: $model.settings.general.revealStyle, title: \.title)
                }
                SettingRow("Clear the app menus", subtitle: "Makes room by hiding the menus of the frontmost app while items are shown.") {
                    EnumPicker(selection: $model.settings.general.appMenuHiding, title: \.title)
                }
            }

            SettingsCard("Hiding again", symbol: "eye.slash") {
                ToggleRow("Hide automatically", isOn: $model.settings.reveal.autoRehide)
                if model.settings.reveal.autoRehide {
                    SliderRow("After", value: $model.settings.reveal.rehideDelay, in: 2...60, step: 1, format: Formatters.seconds)
                }
                ToggleRow("When you switch to another app or click elsewhere", isOn: $model.settings.reveal.rehideOnFocusChange)
                ToggleRow("When the pointer leaves the menu bar", isOn: $model.settings.reveal.rehideOnMouseExit)
            }

            SettingsCard("Sections", symbol: "rectangle.split.3x1") {
                ToggleRow(
                    "Use the Stash",
                    subtitle: "A second hidden section for items you rarely need. They never appear in the menu bar, only in the Shelf, Quick Open or with ⌥-click.",
                    isOn: $model.settings.general.stashEnabled
                )
                ToggleRow("Show how many items are hidden next to the Meno icon", isOn: $model.settings.general.showsHiddenCount)
                SettingRow("When a new item appears") {
                    EnumPicker(selection: $model.settings.general.newItemPolicy, title: \.title)
                }
            }

            SettingsCard("Zen", symbol: "leaf", footnote: "Zen clears the menu bar for screenshots, recordings and presentations. Rules can turn it on for you, for example while Keynote is in front.") {
                ToggleRow("Also hide the items in the Visible section", isOn: $model.settings.zen.hidesVisibleItems)
                ToggleRow("Ignore hover, scrolling and clicks while Zen is on", isOn: $model.settings.zen.blocksReveal)
                HStack {
                    Spacer()
                    Button(model.isZenActive ? "Turn Zen Off" : "Turn Zen On") {
                        model.setZen(!model.isZenActive)
                    }
                    .menoGlassButtonStyle(prominent: !model.isZenActive)
                }
            }

            SettingsCard("Advanced", symbol: "wrench.and.screwdriver") {
                SettingRow("Hiding engine", subtitle: LocalizedStringKey(model.statusBar.engine.explanation)) {
                    EnumPicker(selection: $model.settings.general.hidingEngine, title: \.title)
                }
                ToggleRow(
                    "Record usage statistics",
                    subtitle: "Stored only on this Mac. Used for Insights and to rank Quick Open results.",
                    isOn: $model.settings.general.usageTracking
                )
                Divider().opacity(0.4)
                HStack(spacing: 10) {
                    Button("Export Settings…") { model.exportSettings() }
                        .menoGlassButtonStyle()
                    Button("Import Settings…") { model.importSettings() }
                        .menoGlassButtonStyle()
                    Spacer()
                    Button("Reset All Settings…", role: .destructive) { confirmingReset = true }
                        .menoGlassButtonStyle()
                }
            }
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { model.resetSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scenes, rules, markers and shortcuts are removed. The arrangement of your menu bar stays as it is.")
        }
    }
}
