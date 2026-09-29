import Foundation

/// A command in a `meno://` link, so that Shortcuts, launchers and scripts
/// can control Meno, for example with `open meno://zen/on`.
///
/// | Link | Does |
/// | --- | --- |
/// | `meno://show`, `meno://show/all` | Shows hidden items (and the Stash) |
/// | `meno://hide` | Hides them again |
/// | `meno://toggle`, `meno://toggle/all` | Shows or hides |
/// | `meno://zen`, `meno://zen/on`, `meno://zen/off` | Toggles or sets Zen |
/// | `meno://scene/Work` | Applies a scene by name |
/// | `meno://open/Wi-Fi`, `meno://open/Wi-Fi?menu=secondary` | Opens a menu bar item by name |
/// | `meno://quick-open`, `meno://shelf` | Opens Quick Open or the Shelf |
/// | `meno://settings`, `meno://settings/rules` | Opens Settings |
public enum LinkCommand: Equatable, Sendable {
    case show(all: Bool)
    case hide
    case toggle(all: Bool)
    /// `nil` toggles.
    case zen(Bool?)
    case scene(name: String)
    /// Opens an item found by name, or by its key when `name` is a key.
    case open(name: String, secondary: Bool)
    case quickOpen
    case shelf
    case settings(pane: String?)

    public static let scheme = "meno"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let arguments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        let first = arguments.first?.lowercased()
        let all = first == "all" || query["all"].map { $0.isEmpty || Self.isTrue($0) } ?? false

        switch host {
        case "show", "reveal":
            self = .show(all: all)
        case "hide", "collapse":
            self = .hide
        case "toggle":
            self = .toggle(all: all)
        case "zen":
            switch first {
            case nil, "toggle": self = .zen(nil)
            case "on": self = .zen(true)
            case "off": self = .zen(false)
            default: return nil
            }
        case "scene":
            guard let name = Self.name(arguments: arguments, query: query) else { return nil }
            self = .scene(name: name)
        case "open", "item":
            guard let name = Self.name(arguments: arguments, query: query, keys: ["name", "key"]) else { return nil }
            let menu = query["menu"]?.lowercased()
            self = .open(name: name, secondary: menu == "secondary" || Self.isTrue(query["secondary"]))
        case "quick-open", "quickopen", "search":
            self = .quickOpen
        case "shelf":
            self = .shelf
        case "settings", "preferences":
            self = .settings(pane: first ?? query["pane"]?.lowercased())
        default:
            return nil
        }
    }

    /// The link for the command.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .show(let all):
            components.host = "show"
            if all { components.path = "/all" }
        case .hide:
            components.host = "hide"
        case .toggle(let all):
            components.host = "toggle"
            if all { components.path = "/all" }
        case .zen(let enabled):
            components.host = "zen"
            if let enabled { components.path = enabled ? "/on" : "/off" }
        case .scene(let name):
            components.host = "scene"
            components.path = "/" + name
        case .open(let name, let secondary):
            components.host = "open"
            var items = [URLQueryItem(name: "name", value: name)]
            if secondary { items.append(URLQueryItem(name: "menu", value: "secondary")) }
            components.queryItems = items
        case .quickOpen:
            components.host = "quick-open"
        case .shelf:
            components.host = "shelf"
        case .settings(let pane):
            components.host = "settings"
            if let pane { components.path = "/" + pane }
        }
        return components.url
    }

    /// The name from the path (which may contain slashes) or the query.
    private static func name(arguments: [String], query: [String: String], keys: [String] = ["name"]) -> String? {
        let fromPath = arguments.joined(separator: "/").trimmingCharacters(in: .whitespaces)
        if !fromPath.isEmpty { return fromPath }
        for key in keys {
            if let value = query[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty { return value }
        }
        return nil
    }

    private static func isTrue(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(value)
    }
}
