import MenoCore
import SwiftUI

// Localized names, symbols and colors for model values.

extension ItemSection {
    var title: String {
        switch self {
        case .visible: return String(localized: "Visible")
        case .hidden: return String(localized: "Hidden")
        case .stash: return String(localized: "Stash")
        }
    }

    var explanation: String {
        switch self {
        case .visible: return String(localized: "Always shown in the menu bar.")
        case .hidden: return String(localized: "Shown when you click the Meno icon, hover, scroll or use a hotkey.")
        case .stash: return String(localized: "Never shown in the menu bar. Reach these items from the Shelf, Quick Open or with ⌥-click.")
        }
    }

    /// The command that moves an item into this section.
    var moveTitle: String {
        switch self {
        case .visible: return String(localized: "Move to Visible")
        case .hidden: return String(localized: "Move to Hidden")
        case .stash: return String(localized: "Move to Stash")
        }
    }

    var symbol: String {
        switch self {
        case .visible: return "eye"
        case .hidden: return "eye.slash"
        case .stash: return "archivebox"
        }
    }

    var color: Color {
        switch self {
        case .visible: return .green
        case .hidden: return .orange
        case .stash: return .purple
        }
    }
}

extension Image {
    /// Artwork of a menu bar item. Single-color glyphs take the text color.
    init(menuItemImage image: NSImage) {
        self = Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
    }
}

extension RevealStyle {
    var title: String {
        switch self {
        case .menuBar: return String(localized: "In the menu bar")
        case .shelf: return String(localized: "In the Shelf")
        case .automatic: return String(localized: "Automatically")
        }
    }
}

extension AppMenuHiding {
    var title: String {
        switch self {
        case .never: return String(localized: "Never")
        case .whenNeeded: return String(localized: "When items need the room")
        case .always: return String(localized: "Always")
        }
    }
}

extension NewItemPolicy {
    var title: String {
        switch self {
        case .ignore: return String(localized: "Leave it where it is")
        case .notify: return String(localized: "Ask me")
        case .hide: return String(localized: "Hide it")
        case .stash: return String(localized: "Put it in the Stash")
        }
    }
}

extension HidingEngine {
    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .wide: return String(localized: "Wide divider")
        case .stepped: return String(localized: "Stepped")
        }
    }
}

extension ResolvedHidingEngine {
    var explanation: String {
        switch self {
        case .wide:
            return String(localized: "One divider grows past the screen edge and pushes hidden items out of view. Best on macOS 14 to 26.")
        case .stepped:
            return String(localized: "The divider and a few helper spacers grow in small steps, each below the width limit of the macOS 27 menu bar. Pushed items move into the system overflow.")
        }
    }
}

extension MenoIcon {
    var title: String {
        switch self {
        case .meno: return "Meno"
        case .chevron: return String(localized: "Chevron")
        case .dots: return String(localized: "Dots")
        case .eye: return String(localized: "Eye")
        case .sparkles: return String(localized: "Sparkles")
        case .stack: return String(localized: "Stack")
        case .circle: return String(localized: "Circle")
        case .custom: return String(localized: "Custom")
        }
    }
}

extension DividerGlyph {
    var title: String {
        switch self {
        case .chevron: return String(localized: "Chevron")
        case .line: return String(localized: "Line")
        case .dot: return String(localized: "Dot")
        }
    }
}

extension GlassMaterial {
    var title: String {
        switch self {
        case .regular: return String(localized: "Regular")
        case .clear: return String(localized: "Clear")
        }
    }
}

extension ShelfPlacement {
    var title: String {
        switch self {
        case .underIcon: return String(localized: "Below the Meno icon")
        case .center: return String(localized: "Centered")
        case .pointer: return String(localized: "At the pointer")
        }
    }
}

extension TintFill {
    var title: String {
        switch self {
        case .solid: return String(localized: "Solid")
        case .gradient: return String(localized: "Gradient")
        }
    }
}

extension TintShape {
    var title: String {
        switch self {
        case .full: return String(localized: "Full width")
        case .rounded: return String(localized: "Floating")
        case .split: return String(localized: "Split")
        }
    }
}

extension MarkerKind {
    var title: String {
        switch self {
        case .space: return String(localized: "Space")
        case .line: return String(localized: "Line")
        case .dot: return String(localized: "Dot")
        case .symbol: return String(localized: "Symbol")
        case .text: return String(localized: "Text")
        }
    }

    var symbol: String {
        switch self {
        case .space: return "arrow.left.and.right"
        case .line: return "line.diagonal"
        case .dot: return "circle.fill"
        case .symbol: return "star"
        case .text: return "textformat"
        }
    }
}

extension MenuMarker {
    var displayName: String {
        switch kind {
        case .text: return text.isEmpty ? String(localized: "Label") : text
        case .symbol: return String(localized: "Symbol: \(symbol)")
        default: return kind.title
        }
    }
}

extension HotkeyAction {
    var title: String {
        switch self {
        case .toggleHidden: return String(localized: "Show or hide hidden items")
        case .toggleStash: return String(localized: "Show or hide everything, including the Stash")
        case .quickOpen: return String(localized: "Quick Open")
        case .toggleShelf: return String(localized: "Show or hide the Shelf")
        case .toggleZen: return String(localized: "Turn Zen on or off")
        case .arrangeMenuBar: return String(localized: "Arrange the menu bar")
        case .openSettings: return String(localized: "Open Settings")
        }
    }

    var symbol: String {
        switch self {
        case .toggleHidden: return "eye"
        case .toggleStash: return "archivebox"
        case .quickOpen: return "magnifyingglass"
        case .toggleShelf: return "rectangle.topthird.inset.filled"
        case .toggleZen: return "leaf"
        case .arrangeMenuBar: return "rectangle.3.group"
        case .openSettings: return "gearshape"
        }
    }
}

extension ClickKind {
    var title: String {
        switch self {
        case .primary: return String(localized: "Click")
        case .secondary: return String(localized: "Secondary click")
        }
    }
}

extension RuleCondition.Kind {
    var title: String {
        switch self {
        case .appFrontmost: return String(localized: "An app is in front")
        case .appRunning: return String(localized: "An app is running")
        case .onBattery: return String(localized: "Running on battery")
        case .onPower: return String(localized: "Connected to power")
        case .batteryBelow: return String(localized: "Battery is below")
        case .lowPowerMode: return String(localized: "Low Power Mode is on")
        case .externalDisplay: return String(localized: "An external display is connected")
        case .noExternalDisplay: return String(localized: "No external display")
        case .displayConnected: return String(localized: "A specific display is connected")
        case .timeWindow: return String(localized: "Time of day")
        case .offline: return String(localized: "The Mac is offline")
        case .microphoneInUse: return String(localized: "A microphone is in use")
        case .cameraInUse: return String(localized: "A camera is in use")
        case .commandSucceeds: return String(localized: "A command succeeds")
        case .network: return String(localized: "Connected to a network")
        }
    }

    var symbol: String {
        switch self {
        case .appFrontmost: return "macwindow"
        case .appRunning: return "app.badge"
        case .onBattery: return "battery.50"
        case .onPower: return "powerplug"
        case .batteryBelow: return "battery.25"
        case .lowPowerMode: return "tortoise"
        case .externalDisplay: return "display.2"
        case .noExternalDisplay: return "laptopcomputer"
        case .displayConnected: return "display"
        case .timeWindow: return "clock"
        case .offline: return "wifi.slash"
        case .microphoneInUse: return "mic"
        case .cameraInUse: return "video"
        case .commandSucceeds: return "terminal"
        case .network: return "network"
        }
    }
}

extension RuleAction.Kind {
    var title: String {
        switch self {
        case .revealHidden: return String(localized: "Show hidden items")
        case .revealAll: return String(localized: "Show everything")
        case .collapse: return String(localized: "Hide items")
        case .zen: return String(localized: "Turn on Zen")
        case .applyScene: return String(localized: "Apply a scene")
        case .showItem: return String(localized: "Keep an item visible")
        case .hideItem: return String(localized: "Hide an item")
        case .stashItem: return String(localized: "Stash an item")
        }
    }

    var symbol: String {
        switch self {
        case .revealHidden: return "eye"
        case .revealAll: return "eye.circle"
        case .collapse: return "eye.slash"
        case .zen: return "leaf"
        case .applyScene: return "square.stack.3d.up"
        case .showItem: return "arrow.up.right.circle"
        case .hideItem: return "arrow.down.left.circle"
        case .stashItem: return "archivebox"
        }
    }
}

extension RevealTrigger {
    var title: String {
        switch self {
        case .click: return String(localized: "Meno icon")
        case .emptyArea: return String(localized: "Empty menu bar")
        case .hover: return String(localized: "Hover")
        case .scroll: return String(localized: "Scroll")
        case .hotkey: return String(localized: "Hotkey")
        case .menu: return String(localized: "Menu")
        case .activation: return String(localized: "Opening items")
        case .rule: return String(localized: "Rules")
        case .layout: return String(localized: "Layout")
        case .launch: return String(localized: "Launch")
        case .timer: return String(localized: "Timer")
        case .focus: return String(localized: "App switch")
        case .pointerExit: return String(localized: "Pointer")
        case .zen: return "Zen"
        case .change: return String(localized: "Item changed")
        case .link: return String(localized: "Link")
        case .drag: return String(localized: "Dragging onto the menu bar")
        }
    }
}

extension HoverModifier {
    var title: String {
        switch self {
        case .none: return String(localized: "No key needed")
        case .option: return String(localized: "Hold ⌥ Option")
        case .control: return String(localized: "Hold ⌃ Control")
        case .command: return String(localized: "Hold ⌘ Command")
        }
    }
}

enum Formatters {
    static func seconds(_ value: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = value < 1 ? 2 : (value < 10 ? 1 : 0)
        return formatter.string(from: Measurement(value: value, unit: UnitDuration.seconds))
    }

    static func time(minuteOfDay: Int) -> String {
        var components = DateComponents()
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    /// For example "15 minutes" or "1 hour".
    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: seconds) ?? "\(Int(seconds / 60))"
    }
}
