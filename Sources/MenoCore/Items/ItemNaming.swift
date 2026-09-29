import Foundation

/// How scanned menu bar items are named, and which ones are real items.
public enum ItemNaming {
    /// Whether an element belongs to one of Apple's processes and has no name.
    ///
    /// Apple's menu bar items always have a name. Control Center on macOS 26
    /// also reports a row of unnamed elements that are not menu bar icons, so
    /// these are left out. Other apps often leave their items unnamed, so
    /// their items are kept.
    public static func isUnnamedSystemElement(owner: String, texts: [String?]) -> Bool {
        owner.hasPrefix("com.apple.") && texts.allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The name at the start of a description such as "Wi‑Fi, connected, 3 bars".
    ///
    /// Apple's items put their state after the name, so the full description
    /// keeps changing. The name alone stays the same.
    public static func leadingName(of text: String) -> String {
        let separators = CharacterSet(charactersIn: ",，、;；")
        let name = text.components(separatedBy: separators).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? text : name
    }
}
