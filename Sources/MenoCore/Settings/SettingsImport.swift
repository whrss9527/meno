import Foundation

/// A settings file someone picked to import: checked, and ready to replace
/// the current settings once they confirm.
public struct SettingsImport: Sendable {
    /// The settings from the file, as they would replace the current ones.
    public let settings: MenoSettings
    /// Whether rules that run a command were turned off, so that a file
    /// cannot run anything before the person has looked at it.
    public let turnedOffCommands: Bool

    /// Reads a settings file. Throws ``MenoSettings/ImportError`` for a file
    /// that holds no settings, or scenes and rules to share instead.
    public init(data: Data) throws {
        var settings = try MenoSettings.decodeImport(from: data)
        settings.onboardingCompleted = true
        let (rules, turnedOff) = settings.rules.disablingCommands()
        settings.rules = rules
        self.settings = settings
        turnedOffCommands = turnedOff
    }

    /// The name of the copy of the current settings kept when importing at
    /// `date`, such as `settings.before-import-20261003-142501.json`.
    public static func backupName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "settings.before-import-\(formatter.string(from: date)).json"
    }
}

extension MenoSettings {
    /// Every shortcut: those of Meno's own actions, of items, of groups and
    /// of scenes.
    public var shortcuts: [KeyCombo] {
        HotkeyAction.allCases.compactMap { hotkeys[$0] }
            + itemHotkeys.map(\.combo)
            + groups.compactMap(\.hotkey)
            + scenes.compactMap(\.hotkey)
    }
}
