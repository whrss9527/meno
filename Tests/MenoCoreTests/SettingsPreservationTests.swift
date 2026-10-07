import XCTest
@testable import MenoCore

final class SettingsPreservationTests: XCTestCase {
    private func object(_ settings: MenoSettings) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: settings.encoded()) as? [String: Any])
    }

    func testLegacyFilesAcquireVersionOneAndFutureVersionsAreNotDowngraded() throws {
        let legacy = try MenoSettings.decode(from: Data(#"{"general":{"stashEnabled":false}}"#.utf8))
        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertFalse(legacy.usesNewerSchema)
        XCTAssertEqual(try object(legacy)["schemaVersion"] as? Int, 1)
        let future = try MenoSettings.decode(from: Data(#"{"schemaVersion":7,"general":{"stashEnabled":false}}"#.utf8))
        XCTAssertTrue(future.usesNewerSchema)
        XCTAssertEqual(try object(future)["schemaVersion"] as? Int, 7)
    }

    func testSectionsWithOnlyUnknownKeysStillKeepTheirDefaults() throws {
        let data = Data(#"{"general":{"futureOption":true},"hotkeys":{"futurePanel":{"color":"blue"}}}"#.utf8)
        let settings = try MenoSettings.decode(from: data)
        XCTAssertEqual(settings.general, GeneralSettings())
        XCTAssertEqual(settings.hotkeys, HotkeyBindings())
        let saved = try object(settings)
        XCTAssertEqual((saved["general"] as? [String: Any])?["futureOption"] as? Bool, true)
        XCTAssertEqual(((saved["hotkeys"] as? [String: Any])?["futurePanel"] as? [String: Any])?["color"] as? String, "blue")
    }

    func testUnknownFieldsKeepNullBooleansAndLargeNumbersThroughKnownEditsAndReload() throws {
        let data = Data(#"{"schemaVersion":2,"future":{"flag":true,"none":null,"integer":18446744073709551615,"array":[false,"text",2.125]},"general":{"stashEnabled":false,"futureOption":{"enabled":true}},"shelf":{"iconSize":22,"futureSize":64}}"#.utf8)
        var settings = try MenoSettings.decode(from: data)
        settings.general.stashEnabled = true
        settings.shelf.iconSize = 28
        let decoder = TolerantJSON.makeDecoder()
        let original = try decoder.decode(SettingsJSON.self, from: data)
        let saved = try decoder.decode(SettingsJSON.self, from: settings.encoded())
        guard case .object(let old) = original, case .object(let new) = saved else { return XCTFail() }
        XCTAssertEqual(new["future"], old["future"])
        let general = try XCTUnwrap(try object(settings)["general"] as? [String: Any])
        XCTAssertEqual(general["stashEnabled"] as? Bool, true)
        XCTAssertEqual((general["futureOption"] as? [String: Any])?["enabled"] as? Bool, true)
        let reloaded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertEqual(try reloaded.encoded(), try settings.encoded())
    }

    func testFieldsFollowRecordIdentityAcrossReorderingAndDoNotRestoreDeletedRecordsOrNames() throws {
        var settings = MenoSettings()
        settings.scenes = [LayoutScene(name: "First", layout: SceneLayout()), LayoutScene(name: "Second", layout: SceneLayout())]
        settings.itemNames = ["com.example#solo": "Old name"]
        var raw = try object(settings)
        var scenes = try XCTUnwrap(raw["scenes"] as? [[String: Any]])
        scenes[0]["futureColor"] = "red"
        scenes[1]["futureColor"] = "blue"
        scenes[1]["id"] = settings.scenes[1].id.uuidString.lowercased()
        raw["scenes"] = scenes
        var loaded = try MenoSettings.decode(from: JSONSerialization.data(withJSONObject: raw))
        loaded.scenes.reverse()
        loaded.scenes[0].name = "Renamed"
        loaded.itemNames = [:]
        let reordered = try XCTUnwrap(try object(loaded)["scenes"] as? [[String: Any]])
        XCTAssertEqual(reordered.map { $0["futureColor"] as? String }, ["blue", "red"])
        XCTAssertEqual(reordered[0]["name"] as? String, "Renamed")
        XCTAssertEqual((try object(loaded)["itemNames"] as? [String: String])?.count, 0)
        loaded.scenes.removeLast()
        let removed = try XCTUnwrap(try object(loaded)["scenes"] as? [[String: Any]])
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed[0]["futureColor"] as? String, "blue")
    }

    func testUnsupportedRulesStayInertAndTheirOriginalJSONSurvivesSaving() throws {
        var settings = MenoSettings()
        settings.rules = [AutomationRule(name: "Known", conditions: [.offline], action: .revealHidden)]
        var raw = try object(settings)
        var rules = try XCTUnwrap(raw["rules"] as? [[String: Any]])
        var future = rules[0]
        future["id"] = UUID().uuidString
        future["name"] = "Future"
        future["conditions"] = [["futureCondition": ["flag": true]]]
        rules.insert(future, at: 0)
        raw["rules"] = rules
        var loaded = try MenoSettings.decode(from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(loaded.effectiveRules.map(\.name), ["Known"])
        loaded.rules = []
        let saved = try XCTUnwrap(try object(loaded)["rules"] as? [[String: Any]])
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0]["name"] as? String, "Future")
        XCTAssertEqual(NSDictionary(dictionary: saved[0]), NSDictionary(dictionary: future))
        XCTAssertTrue(try MenoSettings.decode(from: loaded.encoded()).effectiveRules.isEmpty)
    }
}
