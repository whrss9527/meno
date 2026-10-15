import Foundation

/// Shared execution policy for the intent adapter: awaiting a real layout
/// operation is different from accepting a request. Ownership, cancellation
/// and edits to the selected layout remain observable across that suspension.
@MainActor
public enum SavedSceneAction {
    public enum Failure: Error, Equatable { case missingScene, notOwner, notApplied }

    public static func apply(
        id: String,
        scenes: @escaping () -> [LayoutScene],
        isOwner: @escaping () -> Bool,
        operation: @MainActor (LayoutScene, @escaping () -> Bool) async -> Bool
    ) async throws -> Bool {
        try Task.checkCancellation()
        guard isOwner() else { throw Failure.notOwner }
        guard let selected = SceneSelection.resolve([id], in: scenes()).first else { throw Failure.missingScene }
        let stillSelected = { scenes().contains { $0.id == selected.id && $0.layout == selected.layout } }
        let applied = await operation(selected, { !Task.isCancelled && isOwner() && stillSelected() })
        try Task.checkCancellation()
        guard isOwner() else { throw Failure.notOwner }
        guard stillSelected() else { throw Failure.missingScene }
        guard applied else { throw Failure.notApplied }
        return true
    }
}
