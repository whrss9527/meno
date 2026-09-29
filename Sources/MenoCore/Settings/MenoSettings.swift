import Foundation

/// Every user preference Meno persists.
///
/// Settings are stored as JSON. Decoding goes through ``TolerantJSON`` so
/// files written by older versions (with missing keys) still load and fall
/// back to the defaults declared here.
public struct MenoSettings: Codable, Equatable, Sendable {
    public var general = GeneralSettings()
    public var reveal = RevealSettings()
    public var appearance = AppearanceSettings()
    public var shelf = ShelfSettings()
    public var zen = ZenSettings()
    public var tint = MenuBarTint()
    public var spacing = IconSpacing()
    public var hotkeys = HotkeyBindings()
    public var itemHotkeys: [ItemHotkey] = []
    /// Names given to items in Meno, by item key.
    public var itemNames: [String: String] = [:]
    /// SF Symbols chosen to stand for items in Meno, by item key.
    public var itemSymbols: [String: String] = [:]
    /// Keys of hidden items that are shown for a moment when their icon or
    /// text changes.
    public var revealOnChange: [String] = []
    @LossyArray public var markers: [MenuMarker] = []
    @LossyArray public var groups: [ItemGroup] = []
    public var scenes: [LayoutScene] = []
    @LossyArray public var rules: [AutomationRule] = []
    /// Stops all rules for a while without turning each one off.
    public var rulesPaused = false
    public var onboardingCompleted = false

    public init() {}

    /// The rules as they apply now: while rules are paused, none is on.
    public var effectiveRules: [AutomationRule] {
        guard rulesPaused else { return rules }
        return rules.map { rule in
            var paused = rule
            paused.isEnabled = false
            return paused
        }
    }

    /// Whether hidden items can be shown without the Meno icon: by clicking,
    /// hovering or scrolling over the menu bar, or with a hotkey.
    public var canRevealWithoutIcon: Bool {
        reveal.onEmptyAreaClick || reveal.onHover || reveal.onScroll
            || hotkeys[.toggleHidden] != nil || hotkeys[.toggleShelf] != nil
    }

    /// Decodes settings, filling in defaults for anything missing.
    public static func decode(from data: Data) throws -> MenoSettings {
        try TolerantJSON.decode(MenoSettings.self, from: data, defaults: MenoSettings())
    }

    /// Encodes settings as pretty-printed JSON with stable key order.
    public func encoded() throws -> Data {
        try TolerantJSON.makeEncoder().encode(self)
    }
}

// MARK: - General

public struct GeneralSettings: Codable, Equatable, Sendable {
    /// Whether the Stash section (and its divider) exists.
    public var stashEnabled = true
    /// How hidden items are presented when revealed.
    public var revealStyle: RevealStyle = .automatic
    /// Whether to clear the app menus when revealed items need the room.
    public var appMenuHiding: AppMenuHiding = .whenNeeded
    /// What to do when an item Meno has never seen appears.
    public var newItemPolicy: NewItemPolicy = .notify
    /// How Meno pushes hidden items out of the menu bar.
    public var hidingEngine: HidingEngine = .automatic
    /// Records how often items are used (stored locally only).
    public var usageTracking = true
    /// Shows the number of hidden items next to the Meno icon.
    public var showsHiddenCount = false
    /// Looks for a newer release on GitHub once a day.
    public var checksForUpdates = false

    public init() {}
}

/// How revealed items are presented.
public enum RevealStyle: String, Codable, CaseIterable, Sendable {
    /// Expand the hidden section in place.
    case menuBar
    /// Show the items in the glass Shelf below the menu bar.
    case shelf
    /// Expand in place, but use the Shelf when the items would not fit
    /// (for example next to the camera housing on notched displays).
    case automatic
}

/// Whether the frontmost app's menus are cleared while items are revealed.
public enum AppMenuHiding: String, Codable, CaseIterable, Sendable {
    case never
    case whenNeeded
    case always
}

/// What happens to an item that appears for the first time.
public enum NewItemPolicy: String, Codable, CaseIterable, Sendable {
    /// Leave it where macOS placed it.
    case ignore
    /// Leave it and show a notification with quick actions.
    case notify
    /// Move it into the Hidden section.
    case hide
    /// Move it into the Stash.
    case stash
}

/// The technique used to push items out of the menu bar.
public enum HidingEngine: String, Codable, CaseIterable, Sendable {
    /// Pick the right engine for the running macOS version.
    case automatic
    /// Grow a single divider far beyond the screen width (macOS 14 – 26).
    case wide
    /// Grow the divider and helper spacers in small steps, each below the
    /// per-item width limit introduced in macOS 27.
    case stepped

    public func resolved(osMajorVersion: Int) -> ResolvedHidingEngine {
        switch self {
        case .wide: return .wide
        case .stepped: return .stepped
        case .automatic:
            return osMajorVersion >= CollapseMetrics.firstSteppedMajorVersion ? .stepped : .wide
        }
    }
}

public enum ResolvedHidingEngine: String, Sendable {
    case wide
    case stepped
}

// MARK: - Reveal

public struct RevealSettings: Codable, Equatable, Sendable {
    /// Reveal when the pointer rests on an empty part of the menu bar.
    public var onHover = false
    /// Seconds the pointer must rest before revealing.
    public var hoverDelay: Double = 0.25
    /// A key that has to be held for hovering to reveal, so passing over
    /// the menu bar does not.
    public var hoverModifier: HoverModifier = .none
    /// Reveal while a file or other content is dragged onto the menu bar,
    /// so it can be dropped on a hidden item.
    public var onDrag = true
    /// Toggle when an empty part of the menu bar is clicked.
    public var onEmptyAreaClick = true
    /// Reveal or collapse with a scroll or two-finger swipe over the menu bar.
    public var onScroll = false
    /// Collapse again automatically.
    public var autoRehide = true
    /// Seconds before collapsing again.
    public var rehideDelay: Double = 10
    /// Collapse as soon as another app becomes active.
    public var rehideOnFocusChange = true
    /// Collapse when the pointer leaves the menu bar.
    public var rehideOnMouseExit = false

    public init() {}
}

/// A modifier key that has to be held for hovering to reveal.
public enum HoverModifier: String, Codable, CaseIterable, Sendable {
    case none
    case option
    case control
    case command

    /// Whether the key is among the held modifiers. Always true for `none`.
    public func isHeld(in modifiers: KeyModifiers) -> Bool {
        switch self {
        case .none: return true
        case .option: return modifiers.contains(.option)
        case .control: return modifiers.contains(.control)
        case .command: return modifiers.contains(.command)
        }
    }
}

// MARK: - Appearance

public struct AppearanceSettings: Codable, Equatable, Sendable {
    /// Whether the Meno icon is in the menu bar. Without it, hidden items
    /// are shown from the empty part of the menu bar or with a hotkey.
    public var showsMenoIcon = true
    public var icon: MenoIcon = .meno
    /// Show the section dividers while items are revealed.
    public var showsDividers = true
    public var dividerGlyph: DividerGlyph = .chevron

    public init() {}
}

/// The artwork of the Meno icon in the menu bar.
public enum MenoIcon: String, Codable, CaseIterable, Sendable {
    case meno
    case chevron
    case dots
    case eye
    case sparkles
    case stack
    case circle

    /// SF Symbols for the collapsed and revealed state, or `nil` when the
    /// artwork is drawn by Meno itself.
    public var symbolNames: (collapsed: String, revealed: String)? {
        switch self {
        case .meno: return nil
        case .chevron: return ("chevron.left", "chevron.right")
        case .dots: return ("ellipsis.circle", "ellipsis.circle.fill")
        case .eye: return ("eye.slash", "eye")
        case .sparkles: return ("sparkles", "wand.and.stars")
        case .stack: return ("square.stack.3d.up", "square.stack.3d.up.fill")
        case .circle: return ("circle", "circle.fill")
        }
    }
}

/// The glyph drawn for section dividers.
public enum DividerGlyph: String, Codable, CaseIterable, Sendable {
    case chevron
    case line
    case dot
}

// MARK: - Shelf

public struct ShelfSettings: Codable, Equatable, Sendable {
    public var material: GlassMaterial = .regular
    /// Optional tint mixed into the glass.
    public var tint: RGBAColor? = nil
    /// Point size of item artwork.
    public var iconSize: Double = 18
    public var showsLabels = false
    /// Show Stash items after the hidden ones.
    public var includesStash = true
    public var placement: ShelfPlacement = .underIcon
    /// Close the Shelf after an item was opened.
    public var closesAfterAction = true

    public init() {}
}

public enum GlassMaterial: String, Codable, CaseIterable, Sendable {
    case regular
    case clear
}

public enum ShelfPlacement: String, Codable, CaseIterable, Sendable {
    /// Right-aligned below the Meno icon.
    case underIcon
    /// Centered below the menu bar.
    case center
    /// Below the pointer.
    case pointer
}

// MARK: - Zen

/// Zen clears every app icon from the menu bar, leaving only system status
/// items. It is meant for screenshots, recordings and presentations.
public struct ZenSettings: Codable, Equatable, Sendable {
    /// Also hide the items in the Visible section.
    public var hidesVisibleItems = true
    /// Ignore hover, scroll and click reveals while Zen is on.
    public var blocksReveal = true

    public init() {}
}

// MARK: - Menu bar tint

/// A tint painted behind the menu bar (experimental).
public struct MenuBarTint: Codable, Equatable, Sendable {
    public var enabled = false
    public var fill: TintFill = .gradient
    public var color = RGBAColor(red: 0.36, green: 0.47, blue: 1.0, alpha: 0.32)
    public var secondaryColor = RGBAColor(red: 0.80, green: 0.36, blue: 0.96, alpha: 0.32)
    /// Use other colors while the Mac is in Dark Mode.
    public var usesDarkColors = false
    public var darkColor = RGBAColor(red: 0.16, green: 0.22, blue: 0.62, alpha: 0.45)
    public var darkSecondaryColor = RGBAColor(red: 0.45, green: 0.16, blue: 0.62, alpha: 0.45)
    public var shape: TintShape = .full
    public var border = false
    public var borderColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.35)
    public var borderWidth: Double = 1
    public var shadow = false

    public init() {}
}

extension MenuBarTint {
    /// The fill colors for the current appearance.
    public func colors(dark: Bool) -> (primary: RGBAColor, secondary: RGBAColor) {
        dark && usesDarkColors ? (darkColor, darkSecondaryColor) : (color, secondaryColor)
    }
}

public enum TintFill: String, Codable, CaseIterable, Sendable {
    case solid
    case gradient
}

public enum TintShape: String, Codable, CaseIterable, Sendable {
    /// Edge to edge.
    case full
    /// One floating rounded bar.
    case rounded
    /// Separate rounded islands behind the app menus and the status items.
    case split
}

/// A color stored as sRGB components in 0…1.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

// MARK: - Icon spacing

/// System-wide spacing between menu bar icons.
///
/// These map to the `NSStatusItemSpacing` and `NSStatusItemSelectionPadding`
/// preferences. `nil` means the macOS default.
public struct IconSpacing: Codable, Equatable, Sendable {
    public var spacing: Int? = nil
    public var padding: Int? = nil

    public static let range = 0...24
    public static let defaultSpacing = 16
    public static let defaultPadding = 16

    public init() {}

    public var isDefault: Bool { spacing == nil && padding == nil }
}

// MARK: - Markers

/// A decorative item Meno adds to the menu bar: blank space, a thin line,
/// a dot, an SF Symbol or a short text label. Markers can be dragged
/// anywhere with ⌘-drag to group other items.
public struct MenuMarker: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: MarkerKind
    /// Width in points for `.space`.
    public var width: Double
    /// Label for `.text`.
    public var text: String
    /// Symbol name for `.symbol`.
    public var symbol: String

    public init(
        id: UUID = UUID(),
        kind: MarkerKind = .space,
        width: Double = 12,
        text: String = "",
        symbol: String = "star.fill"
    ) {
        self.id = id
        self.kind = kind
        self.width = width
        self.text = text
        self.symbol = symbol
    }

    /// The autosave name of the backing status item.
    public var autosaveName: String { "meno.marker.\(id.uuidString)" }
}

public enum MarkerKind: String, Codable, CaseIterable, Sendable {
    case space
    case line
    case dot
    case symbol
    case text
}
