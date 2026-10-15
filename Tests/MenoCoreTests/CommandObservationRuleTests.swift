import XCTest
@testable import MenoCore

final class CommandObservationRuleTests: XCTestCase {
    private let command = "fixture command"
    private func state(_ succeeds: Bool?, battery: Bool = true) -> RuleContext {
        RuleContext(isOnBattery: battery, succeededCommands: succeeds == true ? [command] : [],
                    knownCommands: succeeds == nil ? [] : [command])
    }

    func testUnknownCannotActivateOrDeactivateByItself() {
        let rule = AutomationRule(name: "Fixture", conditions: [.commandSucceeds(command: command)], action: .zen)
        var evaluator = RuleEvaluator()
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(nil)), [])
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(true)), [.activated(rule)])
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(nil)), [])
        XCTAssertEqual(evaluator.activeRuleIDs, [rule.id])
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(false)), [.deactivated(rule)])
    }

    func testKnownConditionsShortCircuitUnknownInAllAndAnyRules() {
        let all = AutomationRule(name: "All", conditions: [.onBattery, .commandSucceeds(command: command)], action: .zen)
        var evaluator = RuleEvaluator()
        XCTAssertEqual(evaluator.update(rules: [all], context: state(true)), [.activated(all)])
        XCTAssertEqual(evaluator.update(rules: [all], context: state(nil, battery: false)), [.deactivated(all)])
        var any = all
        any.requiresAll = false
        XCTAssertEqual(evaluator.update(rules: [any], context: state(nil)), [.activated(any)])
        XCTAssertEqual(evaluator.update(rules: [any], context: state(nil, battery: false)), [])
        XCTAssertEqual(evaluator.update(rules: [any], context: state(false, battery: false)), [.deactivated(any)])
    }

    func testPausingStillEndsAnActiveUnknownRuleImmediately() {
        var rule = AutomationRule(name: "Fixture", conditions: [.commandSucceeds(command: command)], action: .zen)
        var evaluator = RuleEvaluator()
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(true)), [.activated(rule)])
        rule.isEnabled = false
        rule.minimumDuration = 30
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(nil)), [.deactivated(rule)])
    }

    func testUnknownTimeCannotCompleteAnActivationOrDeactivationDelay() {
        var rule = AutomationRule(name: "Fixture", conditions: [.commandSucceeds(command: command)], action: .zen)
        rule.minimumDuration = 10
        var evaluator = RuleEvaluator()
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(true), now: start), [])
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(nil), now: start + 8), [])
        XCTAssertTrue(evaluator.changedSince.isEmpty)
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(true), now: start + 20), [])
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(true), now: start + 30), [.activated(rule)])
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(false), now: start + 31), [])
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(nil), now: start + 39), [])
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(false), now: start + 50), [])
        XCTAssertEqual(evaluator.update(rules: [rule], context: state(false), now: start + 60), [.deactivated(rule)])
    }

    func testLegacyBooleanSnapshotsAndIncompleteConditionsRemainCompatible() {
        var evaluator = RuleEvaluator()
        let rule = AutomationRule(name: "Legacy", conditions: [.commandSucceeds(command: command)], action: .zen)
        XCTAssertEqual(evaluator.update(rules: [rule], context: RuleContext(succeededCommands: [command])), [.activated(rule)])
        XCTAssertEqual(evaluator.update(rules: [rule], context: RuleContext()), [.deactivated(rule)])
        let empty = AutomationRule(name: "Incomplete", conditions: [.commandSucceeds(command: "  ")], action: .zen)
        XCTAssertFalse(empty.matches(state(nil)))
        XCTAssertEqual(evaluator.update(rules: [empty], context: state(nil)), [])
    }
}
