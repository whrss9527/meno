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

    func testPowerAndCaptureConditions() {
        let idle = RuleContext()
        XCTAssertFalse(RuleCondition.lowPowerMode.isSatisfied(by: idle))
        XCTAssertFalse(RuleCondition.microphoneInUse.isSatisfied(by: idle))
        XCTAssertFalse(RuleCondition.cameraInUse.isSatisfied(by: idle))

        let call = RuleContext(isLowPowerMode: true, microphoneInUse: true, cameraInUse: false)
        XCTAssertTrue(RuleCondition.lowPowerMode.isSatisfied(by: call))
        XCTAssertTrue(RuleCondition.microphoneInUse.isSatisfied(by: call))
        XCTAssertFalse(RuleCondition.cameraInUse.isSatisfied(by: call))

        for kind in RuleCondition.Kind.allCases {
            XCTAssertEqual(kind.defaultCondition.kind, kind)
        }
    }

    func testSpecificDisplay() {
        let office = RuleCondition.displayConnected(name: "LG UltraFine")
        XCTAssertTrue(office.isSatisfied(by: RuleContext(externalDisplayCount: 1, displayNames: ["Built-in Retina Display", "LG UltraFine"])))
        XCTAssertFalse(office.isSatisfied(by: RuleContext(displayNames: ["Built-in Retina Display"])))
        XCTAssertFalse(RuleCondition.displayConnected(name: "").isSatisfied(by: RuleContext(displayNames: [""])))
    }

    func testAnyOfTheConditions() {
        var rule = AutomationRule(name: "Calls", conditions: [.appFrontmost(bundleID: "us.zoom.xos"), .microphoneInUse], action: .zen)
        let zoomOnly = RuleContext(frontmostBundleID: "us.zoom.xos")
        XCTAssertFalse(rule.matches(zoomOnly))
        rule.requiresAll = false
        XCTAssertTrue(rule.matches(zoomOnly))
        XCTAssertTrue(rule.matches(RuleContext(microphoneInUse: true)))
        XCTAssertFalse(rule.matches(RuleContext()))
        rule.isEnabled = false
        XCTAssertFalse(rule.matches(zoomOnly))
    }

    func testRulesFromOlderVersionsStillLoad() throws {
        // A rule saved before "any of these" existed.
        let json = #"{"rules":[{"id":"6F1C2A7E-2B1D-4C8A-9E3F-1A2B3C4D5E6F","name":"Battery","isEnabled":true,"conditions":[{"onBattery":{}}],"action":{"zen":{}},"revertsWhenInactive":false}]}"#
        let settings = try MenoSettings.decode(from: Data(json.utf8))
        let rule = try XCTUnwrap(settings.rules.first)
        XCTAssertEqual(rule.name, "Battery")
        XCTAssertTrue(rule.requiresAll)
        XCTAssertFalse(rule.revertsWhenInactive)
        XCTAssertEqual(rule.conditions, [.onBattery])

        var any = rule
        any.requiresAll = false
        var saved = MenoSettings()
        saved.rules = [any]
        XCTAssertEqual(try MenoSettings.decode(from: saved.encoded()).rules, [any])
    }

    func testPausedRulesDoNotApply() {
        var settings = MenoSettings()
        settings.rules = [
            AutomationRule(name: "Battery", conditions: [.onBattery], action: .zen),
            AutomationRule(name: "VPN", conditions: [.commandSucceeds(command: "vpn-up")], action: .revealAll),
        ]
        XCTAssertEqual(settings.effectiveRules, settings.rules)
        var evaluator = RuleEvaluator()
        let context = RuleContext(isOnBattery: true, succeededCommands: ["vpn-up"])
        XCTAssertEqual(evaluator.update(rules: settings.effectiveRules, context: context).count, 2)

        settings.rulesPaused = true
        XCTAssertTrue(settings.effectiveRules.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(settings.effectiveRules.commands.isEmpty)
        // Pausing deactivates what was active, which undoes it.
        let transitions = evaluator.update(rules: settings.effectiveRules, context: context)
        XCTAssertEqual(transitions.count, 2)
        XCTAssertTrue(transitions.allSatisfy { if case .deactivated = $0 { return true } else { return false } })
        // The rules themselves stay on.
        XCTAssertTrue(settings.rules.allSatisfy(\.isEnabled))
        XCTAssertFalse(try MenoSettings.decode(from: MenoSettings().encoded()).rulesPaused)
    }

    func testForgottenRuleActivatesAgain() {
        let rule = AutomationRule(name: "Battery", conditions: [.onBattery], action: .zen)
        var evaluator = RuleEvaluator()
        let battery = RuleContext(isOnBattery: true)
        XCTAssertEqual(evaluator.update(rules: [rule], context: battery), [.activated(rule)])
        XCTAssertEqual(evaluator.update(rules: [rule], context: battery), [])
        var edited = rule
        edited.action = .collapse
        evaluator.forget(rule.id)
        XCTAssertEqual(evaluator.update(rules: [edited], context: battery), [.activated(edited)])
        XCTAssertEqual(evaluator.activeRuleIDs, [rule.id])
    }

    func testCommandCondition() {
        let vpn = RuleCondition.commandSucceeds(command: "scutil --nc list | grep -q Connected")
        XCTAssertFalse(vpn.isSatisfied(by: RuleContext()))
        XCTAssertTrue(vpn.isSatisfied(by: RuleContext(succeededCommands: ["scutil --nc list | grep -q Connected"])))
        XCTAssertEqual(vpn.command, "scutil --nc list | grep -q Connected")
        XCTAssertNil(RuleCondition.commandSucceeds(command: "  ").command)
        XCTAssertNil(RuleCondition.onBattery.command)
    }

    func testCommandsOfEnabledRules() {
        let rules = [
            AutomationRule(name: "VPN", conditions: [.commandSucceeds(command: "vpn-up")], action: .revealAll),
            AutomationRule(name: "Off", isEnabled: false, conditions: [.commandSucceeds(command: "off")], action: .zen),
            AutomationRule(name: "Both", conditions: [.onBattery, .commandSucceeds(command: "vpn-up"), .commandSucceeds(command: " ")], action: .collapse),
            AutomationRule(name: "Plain", conditions: [.onBattery], action: .collapse),
        ]
        XCTAssertEqual(rules.commands, ["vpn-up"])
        XCTAssertTrue(rules[0].runsCommands)
        XCTAssertFalse(rules[3].runsCommands)

        let (disabled, changed) = rules.disablingCommands()
        XCTAssertTrue(changed)
        XCTAssertEqual(disabled.map(\.isEnabled), [false, false, false, true])
        XCTAssertTrue(disabled.commands.isEmpty)
        XCTAssertFalse(disabled.disablingCommands().changed)
    }

    func testNewConditionsSurviveSaving() throws {
        var settings = MenoSettings()
        settings.rules = [
            AutomationRule(name: "Calls", conditions: [.microphoneInUse, .cameraInUse], action: .zen),
            AutomationRule(name: "Saver", conditions: [.lowPowerMode], action: .collapse),
            AutomationRule(name: "Office", conditions: [.displayConnected(name: "LG UltraFine")], action: .revealAll),
            AutomationRule(name: "VPN", conditions: [.commandSucceeds(command: "test -e ~/.vpn")], action: .revealAll),
        ]
        let decoded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertEqual(decoded.rules, settings.rules)
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
