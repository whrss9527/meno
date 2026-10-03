import AppKit
import MenoCore
import UniformTypeIdentifiers

extension UTType {
    /// A `.meno` file of scenes and rules, as Info.plist declares it.
    static let menoShare = UTType(exportedAs: "io.github.whrss9527.meno.share", conformingTo: .json)
}

/// A `.meno` file that was opened, before anything of it is imported.
struct PendingShare: Identifiable {
    let id = UUID()
    let file: ShareFile
    /// The file's name without its extension.
    let name: String
}

/// A settings file picked to import, waiting to be confirmed.
struct PendingSettingsImport: Identifiable {
    let id = UUID()
    let fileName: String
    let file: SettingsImport
}

extension AppModel {
    /// Writes the chosen scenes and rules, with the scenes those rules apply,
    /// to a `.meno` file the person picks.
    func exportShare(scenes: Set<UUID>, rules: Set<UUID>) {
        let chosenScenes = settings.scenes.filter { scenes.contains($0.id) }
        let file = ShareFile.exporting(
            scenes: chosenScenes,
            rules: settings.rules.filter { rules.contains($0.id) },
            available: settings.scenes,
            createdBy: AppInfo.version
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.menoShare]
        let name = chosenScenes.count == 1 && rules.isEmpty ? chosenScenes[0].name : String(localized: "Meno Scenes")
        // A scene's name can hold characters that file names cannot.
        let fileName = name.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "-")
        panel.nameFieldStringValue = "\(fileName).\(ShareFile.fileExtension)"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try file.encoded().write(to: url, options: .atomic)
            toasts.show(String(localized: "Exported to “\(url.lastPathComponent)”."), symbol: "square.and.arrow.up")
        } catch {
            toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Asks for a `.meno` file and shows what it holds.
    func chooseShareFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.menoShare]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openShareFile(url)
    }

    /// Shows what a `.meno` file holds in Settings, where the person chooses
    /// what to import.
    func openShareFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let file = try? ShareFile.decode(from: data),
              !file.scenes.isEmpty || !file.rules.isEmpty
        else {
            toasts.show(String(localized: "That file does not contain Meno scenes or rules."), symbol: "exclamationmark.triangle.fill")
            return
        }
        pendingShare = PendingShare(file: file, name: url.deletingPathExtension().lastPathComponent)
        openSettings(.scenes)
    }

    func importShare(_ share: PendingShare, scenes: Set<UUID>, rules: Set<UUID>) {
        pendingShare = nil
        let result = share.file.importing(
            scenes: scenes,
            rules: rules,
            existingScenes: settings.scenes,
            existingRules: settings.rules
        )
        guard !result.scenes.isEmpty || !result.rules.isEmpty else { return }
        var updated = settings
        updated.scenes += result.scenes
        updated.rules += result.rules
        settings = updated
        if result.disabledCommands {
            toasts.show(
                String(localized: "Imported from “\(share.name)”. Rules that run commands were turned off; check them before turning them on."),
                symbol: "square.and.arrow.down",
                actions: [ToastCenter.Action(title: String(localized: "Show Rules")) { [weak self] in self?.openSettings(.rules) }],
                duration: 10
            )
        } else {
            toasts.show(String(localized: "Imported from “\(share.name)”."), symbol: "square.and.arrow.down")
        }
    }
}
