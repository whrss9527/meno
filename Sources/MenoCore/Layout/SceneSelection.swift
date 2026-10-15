import Foundation

/// Saved shortcuts retain UUID identity across renames. Unknown or deleted
/// scenes are omitted rather than silently selecting another scene by name.
public enum SceneSelection {
    public static func resolve(_ identifiers: [String], in scenes: [LayoutScene]) -> [LayoutScene] {
        identifiers.compactMap { value in
            guard let id = UUID(uuidString: value) else { return nil }
            return scenes.first { $0.id == id }
        }
    }
}
