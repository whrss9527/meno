import AppIntents
import Foundation
import MenoCore

struct MenoSceneEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Saved Scene"))
    static let defaultQuery = MenoSceneQuery()
    let id: String
    let name: String

    init(_ scene: LayoutScene) { id = scene.id.uuidString; name = scene.name }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct MenoSceneQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MenoSceneEntity] {
        try Task.checkCancellation()
        return SceneSelection.resolve(identifiers, in: try MenoIntentSupport.scenes()).map(MenoSceneEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [MenoSceneEntity] {
        try Task.checkCancellation()
        return try MenoIntentSupport.scenes().map(MenoSceneEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [MenoSceneEntity] {
        try Task.checkCancellation()
        return try MenoIntentSupport.scenes().filter {
            string.isEmpty || $0.name.localizedStandardContains(string)
        }.map(MenoSceneEntity.init)
    }
}

@MainActor
enum MenoIntentSupport {
    static let runtime = OwnedIntentRuntime<AppModel>()

    static func model() async throws -> AppModel {
        do { return try await runtime.model() }
        catch is CancellationError { throw CancellationError() }
        catch OwnedIntentRuntime<AppModel>.Failure.secondaryInstance { throw MenoIntentError.secondaryInstance }
        catch { throw MenoIntentError.notRunning }
    }

    /// Entity lookup must also work before a foreground action starts the app.
    /// Read-only decoding avoids Storage.loadSettings' recovery/backup writes.
    static func scenes() throws -> [LayoutScene] {
        if let model = runtime.available { return model.settings.scenes }
        let url = Storage.defaultDirectory.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try MenoSettings.decode(from: Data(contentsOf: url)).scenes }
        catch { throw MenoIntentError.settingsUnavailable }
    }
}

enum MenoIntentError: LocalizedError {
    case secondaryInstance, notRunning, settingsUnavailable, accessibility, missingScene, sceneFailed
    var errorDescription: String? {
        switch self {
        case .secondaryInstance: return String(localized: "Another copy of Meno owns the menu bar. Run this shortcut with that copy.")
        case .notRunning: return String(localized: "Meno is not ready. Open Meno and try again.")
        case .settingsUnavailable: return String(localized: "Saved scenes could not be read. Open Meno to check your settings.")
        case .accessibility: return String(localized: "Allow Meno in Accessibility before running this action.")
        case .missingScene: return String(localized: "This saved scene no longer exists. Choose another scene.")
        case .sceneFailed: return String(localized: "Meno could not apply the scene. Check its permissions and menu bar items.")
        }
    }
}

struct SetMenoZenIntent: AppIntent {
    static let title = LocalizedStringResource("Set Zen Mode")
    static let description = IntentDescription(LocalizedStringResource("Turn Meno's Zen mode on or off and return its current state."))
    static var openAppWhenRun: Bool { true }
    @Parameter(title: LocalizedStringResource("Enabled")) var enabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let model = try await MenoIntentSupport.model()
        guard MenoIntentSupport.runtime.owns(model) else { throw MenoIntentError.notRunning }
        model.permissions.refresh()
        if enabled && !model.permissions.accessibility { throw MenoIntentError.accessibility }
        try Task.checkCancellation()
        guard MenoIntentSupport.runtime.owns(model) else { throw MenoIntentError.notRunning }
        model.setZen(enabled)
        return .result(value: model.isZenActive)
    }
}

struct ApplyMenoSceneIntent: AppIntent {
    static let title = LocalizedStringResource("Apply Saved Scene")
    static let description = IntentDescription(LocalizedStringResource("Apply a saved Meno menu bar layout."))
    static var openAppWhenRun: Bool { true }
    @Parameter(title: LocalizedStringResource("Scene")) var scene: MenoSceneEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let model = try await MenoIntentSupport.model()
        guard MenoIntentSupport.runtime.owns(model) else { throw MenoIntentError.notRunning }
        model.permissions.refresh()
        guard model.permissions.accessibility else { throw MenoIntentError.accessibility }
        do {
            let applied = try await SavedSceneAction.apply(id: scene.id, scenes: { model.settings.scenes },
                isOwner: { MenoIntentSupport.runtime.owns(model) }, operation: { selected, proceeds in
                    await model.applyScene(selected, proceeds: proceeds)
                })
            return .result(value: applied)
        } catch SavedSceneAction.Failure.missingScene { throw MenoIntentError.missingScene }
        catch SavedSceneAction.Failure.notOwner { throw MenoIntentError.notRunning }
        catch SavedSceneAction.Failure.notApplied { throw MenoIntentError.sceneFailed }
    }
}

struct MenoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetMenoZenIntent(), phrases: ["Set Zen mode in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Set Zen Mode"), systemImageName: "leaf")
        AppShortcut(intent: ApplyMenoSceneIntent(), phrases: ["Apply a saved scene in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Apply Saved Scene"), systemImageName: "square.grid.2x2")
    }
}
