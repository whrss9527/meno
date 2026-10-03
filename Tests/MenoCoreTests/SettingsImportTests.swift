import XCTest
@testable import MenoCore

final class SettingsImportTests: XCTestCase {
    private let combo = KeyCombo(keyCode: 0x01, modifiers: [.control, .option])

    func testImportCountsWhatTheFileBrings() throws {
        var settings = MenoSettings()
        settings.scenes = [
            LayoutScene(name: "Work", layout: SceneLayout(), hotkey: combo),
            LayoutScene(name: "Home", layout: SceneLayout()),
        ]
        settings.rules = [AutomationRule(name: "Battery", conditions: [.onBattery], action: .zen)]
        settings.hotkeys[.quickOpen] = KeyCombo(keyCode: 0x02, modifiers: [.control, .option])
        settings.itemHotkeys = [ItemHotkey(itemKey: MenuItemKey(owner: "a", token: "solo"), combo: combo)]
        settings.groups = [ItemGroup(name: "Tools", hotkey: combo), ItemGroup(name: "Other")]

        let imported = try SettingsImport(data: settings.encoded())
        XCTAssertEqual(imported.settings.scenes.count, 2)
        XCTAssertEqual(imported.settings.rules.count, 1)
        // The action, the item, one group and one scene.
        XCTAssertEqual(imported.settings.shortcuts.count, 4)
        XCTAssertFalse(imported.turnedOffCommands)
        XCTAssertTrue(imported.settings.onboardingCompleted)
    }

    func testImportTurnsOffRulesThatRunCommands() throws {
        var settings = MenoSettings()
        settings.rules = [
            AutomationRule(name: "Battery", conditions: [.onBattery], action: .zen),
            AutomationRule(name: "Docker", conditions: [.commandSucceeds(command: "docker-up")], action: .revealAll),
        ]
        let imported = try SettingsImport(data: settings.encoded())
        XCTAssertTrue(imported.turnedOffCommands)
        XCTAssertEqual(imported.settings.rules.map(\.isEnabled), [true, false])
    }

    func testImportRefusesOtherFiles() throws {
        XCTAssertThrowsError(try SettingsImport(data: Data("{}".utf8))) { error in
            XCTAssertEqual(error as? MenoSettings.ImportError, .notSettings)
        }
        let share = try ShareFile(createdBy: "0.12.4", scenes: [], rules: []).encoded()
        XCTAssertThrowsError(try SettingsImport(data: share)) { error in
            XCTAssertEqual(error as? MenoSettings.ImportError, .shareFile)
        }
    }

    func testBackupName() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        // 2026-10-03 14:25:01 UTC.
        let date = Date(timeIntervalSince1970: 1_791_037_501)
        XCTAssertEqual(SettingsImport.backupName(at: date, timeZone: utc), "settings.before-import-20261003-142501.json")
    }
}
