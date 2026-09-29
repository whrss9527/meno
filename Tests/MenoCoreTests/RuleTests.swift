import XCTest
@testable import MenoCore

final class RuleTests: XCTestCase {
    func testConditions() {
        let context = RuleContext(
            frontmostBundleID: "com.apple.Keynote",
            runningBundleIDs: ["com.apple.Keynote", "us.zoom.xos"],
            isOnBattery: true,
            batteryLevel: 15,
            externalDisplayCount: 1,
            minuteOfDay: 23 * 60,
            isOnline: false
        )
        XCTAssertTrue(RuleCondition.appFrontmost(bundleID: "com.apple.Keynote").isSatisfied(by: context))
        XCTAssertFalse(RuleCondition.appFrontmost(bundleID: "us.zoom.xos").isSatisfied(by: context))
        XCTAssertTrue(RuleCondition.appRunning(bundleID: "us.zoom.xos").isSatisfied(by: context))
        XCTAssertTrue(RuleCondition.onBattery.isSatisfied(by: context))
        XCTAssertFalse(RuleCondition.onPower.isSatisfied(by: context))
        XCTAssertTrue(RuleCondition.batteryBelow(percent: 20).isSatisfied(by: context))
        XCTAssertFalse(RuleCondition.batteryBelow(percent: 10).isSatisfied(by: context))
        XCTAssertTrue(RuleCondition.externalDisplay.isSatisfied(by: context))
        XCTAssertFalse(RuleCondition.noExternalDisplay.isSatisfied(by: context))
        XCTAssertTrue(RuleCondition.offline.isSatisfied(by: context))
        XCTAssertFalse(RuleCondition.batteryBelow(percent: 50).isSatisfied(by: RuleContext(batteryLevel: nil)))
    }

    func testTimeWindows() {
        func at(_ hour: Int, _ minute: Int = 0) -> RuleContext { RuleContext(minuteOfDay: hour * 60 + minute) }
        let office = RuleCondition.timeWindow(startMinute: 9 * 60, endMinute: 18 * 60)
        XCTAssertTrue(office.isSatisfied(by: at(9)))
        XCTAssertTrue(office.isSatisfied(by: at(17, 59)))
        XCTAssertFalse(office.isSatisfied(by: at(18)))
        XCTAssertFalse(office.isSatisfied(by: at(8, 59)))

        let night = RuleCondition.timeWindow(startMinute: 22 * 60, endMinute: 7 * 60)
        XCTAssertTrue(night.isSatisfied(by: at(23)))
        XCTAssertTrue(night.isSatisfied(by: at(3)))
        XCTAssertFalse(night.isSatisfied(by: at(12)))
        XCTAssertTrue(RuleCondition.timeWindow(startMinute: 5, endMinute: 5).isSatisfied(by: at(12)))
    }

    func testRuleMatchingNeedsAllConditions() {
        let rule = AutomationRule(name: "r", conditions: [.onBattery, .externalDisplay], action: .revealHidden)
        XCTAssertTrue(rule.matches(RuleContext(isOnBattery: true, externalDisplayCount: 2)))
        XCTAssertFalse(rule.matches(RuleContext(isOnBattery: true)))
        var disabled = rule
        disabled.isEnabled = false
        XCTAssertFalse(disabled.matches(RuleContext(isOnBattery: true, externalDisplayCount: 2)))
        XCTAssertFalse(AutomationRule(name: "empty", conditions: [], action: .collapse).matches(RuleContext()))
    }

    func testEvaluatorReportsEdges() {
        let present = AutomationRule(name: "Present", conditions: [.appFrontmost(bundleID: "k")], action: .zen)
        let battery = AutomationRule(name: "Battery", conditions: [.onBattery], action: .revealHidden)
        var evaluator = RuleEvaluator()

        XCTAssertEqual(evaluator.update(rules: [present, battery], context: RuleContext(frontmostBundleID: "k")), [.activated(present)])
        XCTAssertEqual(evaluator.update(rules: [present, battery], context: RuleContext(frontmostBundleID: "k")), [])
        XCTAssertEqual(
            evaluator.update(rules: [present, battery], context: RuleContext(frontmostBundleID: "x", isOnBattery: true)),
            [.deactivated(present), .activated(battery)]
        )
        XCTAssertEqual(evaluator.activeRuleIDs, [battery.id])
        evaluator.reset()
        XCTAssertEqual(evaluator.update(rules: [battery], context: RuleContext(isOnBattery: true)), [.activated(battery)])
    }

    func testActionHelpers() {
        let key = MenuItemKey(owner: "a", token: "solo")
        XCTAssertEqual(RuleAction.showItem(key: key).targetSection, .visible)
        XCTAssertEqual(RuleAction.stashItem(key: key).itemKey, key)
        XCTAssertNil(RuleAction.zen.itemKey)
        XCTAssertTrue(RuleAction.Kind.hideItem.needsItem)
        XCTAssertFalse(RuleAction.Kind.collapse.needsItem)
        for kind in RuleCondition.Kind.allCases {
            XCTAssertEqual(kind.defaultCondition.kind, kind)
        }
    }
}
