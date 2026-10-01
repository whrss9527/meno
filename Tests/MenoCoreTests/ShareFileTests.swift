import XCTest
@testable import MenoCore

final class ShareFileTests: XCTestCase {
    private let slack = MenuItemKey(owner: "com.tinyspeck.slackmacgap", token: "solo")
    private let backup = MenuItemKey(owner: "com.example.backup", token: "solo")
    private let shortcut = KeyCombo(keyCode: 17, modifiers: [.command, .option])

    private func scene(_ name: String) -> LayoutScene {
        LayoutScene(
            name: name,
            symbol: "briefcase",
            layout: SceneLayout(visible: [slack], hidden: [backup]),
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            hotkey: shortcut
        )
    }

    func testExportTakesAlongTheScenesOfRulesAndLeavesOutShortcuts() throws {
        let work = scene("Work")
        let home = scene("Home")
        let rule = AutomationRule(name: "Office", conditions: [.externalDisplay], action: .applyScene(id: home.id))
        let file = ShareFile.exporting(scenes: [work], rules: [rule], available: [work, home], createdBy: "0.11.0")

        XCTAssertEqual(file.scenes.map(\.name), ["Work", "Home"])
        XCTAssertTrue(file.scenes.allSatisfy { $0.hotkey == nil })
        XCTAssertEqual(file.rules, [rule])
        XCTAssertEqual(file.scenes(appliedBy: rule).map(\.id), [home.id])

        let read = try ShareFile.decode(from: file.encoded())
        XCTAssertEqual(read, file)
        XCTAssertFalse(read.isFromNewerVersion)
    }

    func testOtherFilesAreRefused() {
        XCTAssertThrowsError(try ShareFile.decode(from: Data("{\"rules\": []}".utf8))) { error in
            XCTAssertEqual(error as? ShareFile.ReadError, .notAShareFile)
        }
        XCTAssertThrowsError(try ShareFile.decode(from: Data("[1, 2]".utf8)))
        XCTAssertThrowsError(try ShareFile.decode(from: Data("not json".utf8)))
        XCTAssertThrowsError(try ShareFile.decode(from: MenoSettings().encoded()))
    }

    func testFilesFromNewerVersionsAreReadAsFarAsPossible() throws {
        let work = scene("Work")
        let file = ShareFile(format: 2, createdBy: "9.0.0", scenes: [work], rules: [
            AutomationRule(name: "Calls", conditions: [.microphoneInUse], action: .zen),
        ])
        var json = try JSONSerialization.jsonObject(with: file.encoded()) as! [String: Any]
        var rules = json["rules"] as! [[String: Any]]
        var future = rules[0]
        future["conditions"] = [["somethingNew": ["level": 3]]]
        rules.append(future)
        json["rules"] = rules
        json["somethingElse"] = true

        let read = try ShareFile.decode(from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(read.isFromNewerVersion)
        XCTAssertEqual(read.scenes.map(\.name), ["Work"])
        XCTAssertEqual(read.rules.map(\.name), ["Calls"])
    }

    func testImportMakesCopiesWithNamesOfTheirOwn() {
        let work = scene("Work")
        let home = scene("Home")
        let rule = AutomationRule(name: "Office", conditions: [.externalDisplay], action: .applyScene(id: home.id))
        let calls = AutomationRule(name: "Calls", conditions: [.microphoneInUse], action: .zen)
        let file = ShareFile(createdBy: "0.11.0", scenes: [work, home], rules: [rule, calls])
        let now = Date(timeIntervalSince1970: 5_000)

        let result = file.importing(
            scenes: [work.id],
            rules: [rule.id, calls.id],
            existingScenes: [scene("work"), scene("Work 2")],
            existingRules: [calls],
            now: now
        )

        // The scene the rule applies comes along although it was not chosen.
        XCTAssertEqual(result.scenes.map(\.name), ["Work 3", "Home"])
        XCTAssertTrue(result.scenes.allSatisfy { $0.hotkey == nil && $0.createdAt == now && $0.updatedAt == now })
        XCTAssertTrue(Set(result.scenes.map(\.id)).isDisjoint(with: [work.id, home.id]))
        XCTAssertEqual(result.scenes[0].layout, work.layout)

        XCTAssertEqual(result.rules.map(\.name), ["Office", "Calls 2"])
        XCTAssertFalse(result.rules.contains { $0.id == rule.id || $0.id == calls.id })
        XCTAssertEqual(result.rules[0].action, .applyScene(id: result.scenes[1].id))
        XCTAssertFalse(result.disabledCommands)
    }

    func testImportTurnsOffRulesThatRunCommands() {
        let dockerRule = AutomationRule(name: "Docker", conditions: [.commandSucceeds(command: "pgrep -x Docker")], action: .revealAll)
        let unnamed = AutomationRule(name: "", conditions: [.offline], action: .revealHidden)
        let file = ShareFile(createdBy: "0.11.0", scenes: [], rules: [dockerRule, unnamed])

        let result = file.importing(scenes: [], rules: [dockerRule.id, unnamed.id], existingScenes: [], existingRules: [unnamed])
        XCTAssertTrue(result.disabledCommands)
        XCTAssertEqual(result.rules.map(\.isEnabled), [false, true])
        XCTAssertEqual(result.rules.map(\.name), ["Docker", ""])
        XCTAssertTrue(result.scenes.isEmpty)
    }

    func testUniqueNames() {
        XCTAssertEqual(ShareFile.uniqueName("Work", among: []), "Work")
        XCTAssertEqual(ShareFile.uniqueName("Work", among: ["Home"]), "Work")
        XCTAssertEqual(ShareFile.uniqueName("Work", among: ["WORK"]), "Work 2")
        XCTAssertEqual(ShareFile.uniqueName(" Work ", among: ["Work", "work 2"]), "Work 3")
    }
}
