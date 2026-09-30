/// The language Meno's interface uses. Stored as `AppleLanguages` in Meno's
/// own defaults domain, which macOS reads when the app starts, so a change
/// applies after a relaunch. It stays on this Mac: it is not part of
/// `MenoSettings`, so exporting, sharing and resetting settings leave it be.
public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system
    case english
    case simplifiedChinese
    case traditionalChinese

    /// The defaults key macOS reads the preferred languages from.
    public static let defaultsKey = "AppleLanguages"

    /// Reads the `AppleLanguages` value of Meno's own domain. No value, or
    /// one Meno has no localization for, means following the system.
    public init(appleLanguages value: Any?) {
        guard let languages = value as? [String], let first = languages.first else {
            self = .system
            return
        }
        self = Self.language(for: first) ?? .system
    }

    /// The value to store as `AppleLanguages`, or `nil` to remove it and
    /// follow the system.
    public var appleLanguages: [String]? {
        switch self {
        case .system: return nil
        case .english: return ["en"]
        case .simplifiedChinese: return ["zh-Hans"]
        case .traditionalChinese: return ["zh-Hant"]
        }
    }

    /// The language's name in that language, so it can be found whatever
    /// language the interface is in. `nil` for following the system.
    public var nativeName: String? {
        switch self {
        case .system: return nil
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }

    private static func language(for identifier: String) -> InterfaceLanguage? {
        let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
        guard let code = parts.first else { return nil }
        switch code {
        case "en":
            return .english
        case "zh":
            let rest = parts.dropFirst()
            if rest.contains("hant") { return .traditionalChinese }
            if rest.contains("hans") { return .simplifiedChinese }
            if rest.contains(where: { ["tw", "hk", "mo"].contains($0) }) { return .traditionalChinese }
            return .simplifiedChinese
        default:
            return nil
        }
    }
}
