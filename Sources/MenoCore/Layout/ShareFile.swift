import Foundation

/// The scenes and rules in a `.meno` file, for using them on another Mac or
/// giving them to someone. Shortcuts are left out: they are the person's
/// own, and could clash with those already set up where the file goes.
public struct ShareFile: Codable, Equatable, Sendable {
    public static let fileExtension = "meno"
    /// The format this version of Meno writes. A file from a newer version
    /// is read as far as this version understands it.
    public static let currentFormat = 1

    public var format: Int
    /// The version of Meno that wrote the file.
    public var createdBy: String
    @LossyArray public var scenes: [LayoutScene]
    @LossyArray public var rules: [AutomationRule]

    public init(format: Int = ShareFile.currentFormat, createdBy: String, scenes: [LayoutScene], rules: [AutomationRule]) {
        self.format = format
        self.createdBy = createdBy
        self.scenes = scenes
        self.rules = rules
    }

    public enum ReadError: Error, Equatable {
        /// The data is not a `.meno` file, for example Meno's settings.
        case notAShareFile
    }

    /// A file with `scenes` and `rules`, and with the scenes of `available`
    /// that those rules apply. Scenes keep their order in `available`.
    public static func exporting(
        scenes: [LayoutScene],
        rules: [AutomationRule],
        available: [LayoutScene],
        createdBy: String
    ) -> ShareFile {
        var ids = Set(scenes.map(\.id))
        for rule in rules {
            if case .applyScene(let id) = rule.action { ids.insert(id) }
        }
        let known = Set(available.map(\.id))
        let included = available.filter { ids.contains($0.id) } + scenes.filter { !known.contains($0.id) }
        return ShareFile(
            createdBy: createdBy,
            scenes: included.map { scene in
                var scene = scene
                scene.hotkey = nil
                return scene
            },
            rules: rules
        )
    }

    public func encoded() throws -> Data {
        try TolerantJSON.makeEncoder().encode(self)
    }

    /// Reads a file. Scenes and rules this version cannot read, for example
    /// rules with a condition from a newer version, are left out.
    public static func decode(from data: Data) throws -> ShareFile {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              dictionary["format"] as? Int != nil
        else { throw ReadError.notAShareFile }
        return try TolerantJSON.decode(ShareFile.self, from: data, defaults: ShareFile(createdBy: "", scenes: [], rules: []))
    }

    /// Whether a newer version of Meno wrote the file, so some of it may
    /// have been left out.
    public var isFromNewerVersion: Bool {
        format > Self.currentFormat
    }

    /// The scenes a rule of the file applies.
    public func scenes(appliedBy rule: AutomationRule) -> [LayoutScene] {
        guard case .applyScene(let id) = rule.action else { return [] }
        return scenes.filter { $0.id == id }
    }

    /// Copies of the chosen scenes and rules, to add to `existingScenes` and
    /// `existingRules`. They get identifiers of their own, so a file can be
    /// imported twice, and names that are not taken yet. The scenes that
    /// chosen rules apply come along, and those rules apply the copies.
    /// Rules that run commands are off until the person has looked at them.
    public func importing(
        scenes chosenScenes: Set<UUID>,
        rules chosenRules: Set<UUID>,
        existingScenes: [LayoutScene],
        existingRules: [AutomationRule],
        now: Date = Date()
    ) -> ShareImport {
        let rules = self.rules.filter { chosenRules.contains($0.id) }
        var wanted = chosenScenes
        for rule in rules {
            if case .applyScene(let id) = rule.action { wanted.insert(id) }
        }

        var sceneNames = existingScenes.map(\.name)
        var newSceneIDs: [UUID: UUID] = [:]
        var importedScenes: [LayoutScene] = []
        for scene in self.scenes where wanted.contains(scene.id) && newSceneIDs[scene.id] == nil {
            var copy = scene
            copy.id = UUID()
            copy.name = Self.uniqueName(scene.name, among: sceneNames)
            copy.hotkey = nil
            copy.createdAt = now
            copy.updatedAt = now
            sceneNames.append(copy.name)
            newSceneIDs[scene.id] = copy.id
            importedScenes.append(copy)
        }

        var ruleNames = existingRules.map(\.name)
        let copies = rules.map { rule -> AutomationRule in
            var copy = rule
            copy.id = UUID()
            if !rule.name.isEmpty {
                copy.name = Self.uniqueName(rule.name, among: ruleNames)
                ruleNames.append(copy.name)
            }
            if case .applyScene(let id) = rule.action, let newID = newSceneIDs[id] {
                copy.action = .applyScene(id: newID)
            }
            return copy
        }
        let (importedRules, disabled) = copies.disablingCommands()
        return ShareImport(scenes: importedScenes, rules: importedRules, disabledCommands: disabled)
    }

    /// `name`, or with a number added when another one has it already, as
    /// links name scenes regardless of case.
    public static func uniqueName(_ name: String, among taken: [String]) -> String {
        let used = Set(taken.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let base = name.trimmingCharacters(in: .whitespaces)
        guard used.contains(base.lowercased()) else { return name }
        var number = 2
        while used.contains("\(base) \(number)".lowercased()) {
            number += 1
        }
        return "\(base) \(number)"
    }
}

/// What importing from a `.meno` file adds.
public struct ShareImport: Equatable, Sendable {
    public var scenes: [LayoutScene]
    public var rules: [AutomationRule]
    /// Whether rules that run commands were turned off.
    public var disabledCommands: Bool
}
