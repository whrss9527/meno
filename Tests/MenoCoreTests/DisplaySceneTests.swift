import XCTest
@testable import MenoCore

final class DisplaySceneTests: XCTestCase {
    private let work = UUID()
    private let home = UUID()
    private let studio = "Studio Display"

    func testSettingAScene() throws {
        let other = AutomationRule(name: "Battery", conditions: [.onBattery], action: .zen)
        let rules = [other].settingDisplayScene(work, for: studio, name: "Work on Studio Display")
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules.first, other)
        let rule = try XCTUnwrap(rules.last)
        XCTAssertEqual(rule.conditions, [.menuBarOnDisplay(name: studio)])
        XCTAssertEqual(rule.action, .applyScene(id: work))
        // The next display's scene takes over; nothing is undone in between.
        XCTAssertFalse(rule.revertsWhenInactive)
        XCTAssertEqual(rules.displayScene(for: studio), work)
        XCTAssertNil(rules.displayScene(for: "Built-in Retina Display"))
        XCTAssertEqual(rules.displaysWithScenes, [studio])
    }

    func testChangingASceneKeepsTheRule() throws {
        let first = [AutomationRule]().settingDisplayScene(work, for: studio, name: "Work")
        let changed = first.settingDisplayScene(home, for: studio, name: "Home")
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(changed.first?.id, first.first?.id)
        XCTAssertEqual(changed.first?.name, "Home")
        XCTAssertEqual(changed.displayScene(for: studio), home)
    }

    func testRemovingAScene() {
        let rules = [AutomationRule]()
            .settingDisplayScene(work, for: studio, name: "Work")
            .settingDisplayScene(home, for: "Built-in Retina Display", name: "Home")
        let removed = rules.settingDisplayScene(nil, for: studio, name: "")
        XCTAssertNil(removed.displayScene(for: studio))
        XCTAssertEqual(removed.displayScene(for: "Built-in Retina Display"), home)
        XCTAssertEqual(removed.displaysWithScenes, ["Built-in Retina Display"])
    }

    func testOtherRulesAboutTheDisplayAreLeftAlone() {
        // More conditions, or another action: not the display's scene.
        let atDesk = AutomationRule(
            name: "Desk",
            conditions: [.menuBarOnDisplay(name: studio), .onPower],
            action: .applyScene(id: work)
        )
        let reveal = AutomationRule(name: "Reveal", conditions: [.menuBarOnDisplay(name: studio)], action: .revealHidden)
        let rules = [atDesk, reveal]
        XCTAssertNil(rules.displayScene(for: studio))
        let set = rules.settingDisplayScene(home, for: studio, name: "Home")
        XCTAssertEqual(set.count, 3)
        XCTAssertEqual(Array(set.prefix(2)), rules)
        XCTAssertEqual(set.settingDisplayScene(nil, for: studio, name: ""), rules)
    }

    func testATurnedOffRuleHasNoScene() {
        var rules = [AutomationRule]().settingDisplayScene(work, for: studio, name: "Work")
        rules[0].isEnabled = false
        XCTAssertNil(rules.displayScene(for: studio))
        // Picking the scene again turns the rule back on.
        XCTAssertEqual(rules.settingDisplayScene(work, for: studio, name: "Work").displayScene(for: studio), work)
    }
}
