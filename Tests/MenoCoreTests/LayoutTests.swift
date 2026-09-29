import XCTest
@testable import MenoCore

private func key(_ name: String) -> MenuItemKey { MenuItemKey(owner: name, token: "solo") }
private func item(_ name: String) -> LayoutToken { .item(key(name)) }

final class SectionResolverTests: XCTestCase {
    let dividers = DividerLayout(
        hidden: HorizontalSpan(x: 800, width: 20),
        stash: HorizontalSpan(x: 500, width: 20)
    )

    func testSections() {
        XCTAssertEqual(SectionResolver.section(of: HorizontalSpan(x: 900, width: 22), dividers: dividers), .visible)
        XCTAssertEqual(SectionResolver.section(of: HorizontalSpan(x: 600, width: 22), dividers: dividers), .hidden)
        XCTAssertEqual(SectionResolver.section(of: HorizontalSpan(x: 300, width: 22), dividers: dividers), .stash)
    }

    func testCollapsedDividersKeepOrder() {
        // Hidden divider grown to 10 000 pt: everything left of it is far off screen.
        let collapsed = DividerLayout(
            hidden: HorizontalSpan(minX: -9_200, maxX: 800),
            stash: HorizontalSpan(minX: -19_400, maxX: -9_400)
        )
        XCTAssertEqual(SectionResolver.section(of: HorizontalSpan(x: 850, width: 22), dividers: collapsed), .visible)
        XCTAssertEqual(SectionResolver.section(of: HorizontalSpan(x: -9_300, width: 22), dividers: collapsed), .hidden)
        XCTAssertEqual(SectionResolver.section(of: HorizontalSpan(x: -19_500, width: 22), dividers: collapsed), .stash)
    }

    func testInconsistentDividersFallBackToHidden() {
        let swapped = DividerLayout(hidden: HorizontalSpan(x: 500, width: 20), stash: HorizontalSpan(x: 800, width: 20))
        XCTAssertFalse(swapped.isConsistent)
        XCTAssertEqual(SectionResolver.section(of: HorizontalSpan(x: 300, width: 22), dividers: swapped), .hidden)
        XCTAssertEqual(SectionResolver.section(of: HorizontalSpan(x: 900, width: 22), dividers: swapped), .visible)
    }

    func testBatchResolution() {
        let result = SectionResolver.sections(of: ["a": HorizontalSpan(x: 900, width: 10), "b": HorizontalSpan(x: 100, width: 10)], dividers: dividers)
        XCTAssertEqual(result, ["a": .visible, "b": .stash])
    }
}

final class LayoutPlannerTests: XCTestCase {
    func testNoMovesWhenOrdered() throws {
        let order = [item("a"), LayoutPlanner.hiddenDivider, item("b")]
        XCTAssertEqual(try LayoutPlanner.plan(current: order, target: order), [])
    }

    func testMoveAcrossDivider() throws {
        let current = [item("a"), item("b"), LayoutPlanner.hiddenDivider, item("c")]
        let target = [item("a"), LayoutPlanner.hiddenDivider, item("b"), item("c")]
        let steps = try LayoutPlanner.plan(current: current, target: target)
        XCTAssertEqual(steps, [MoveStep(item: key("b"), placement: .rightOf(LayoutPlanner.hiddenDivider))])
        XCTAssertEqual(LayoutPlanner.apply(steps, to: current), target)
    }

    func testFirstItemMovesLeftOfFirstKeptToken() throws {
        let current = [LayoutPlanner.hiddenDivider, item("a"), item("b")]
        let target = [item("b"), LayoutPlanner.hiddenDivider, item("a")]
        let steps = try LayoutPlanner.plan(current: current, target: target)
        XCTAssertEqual(steps, [MoveStep(item: key("b"), placement: .leftOf(LayoutPlanner.hiddenDivider))])
        XCTAssertEqual(LayoutPlanner.apply(steps, to: current), target)
    }

    func testIgnoresUnknownAndUntargetedTokens() throws {
        let current = [item("x"), item("a"), LayoutPlanner.hiddenDivider, item("b"), item("y")]
        let target = [item("b"), item("ghost"), LayoutPlanner.hiddenDivider, item("a")]
        let steps = try LayoutPlanner.plan(current: current, target: target)
        let result = LayoutPlanner.apply(steps, to: current)
        let relevant = result.filter { [item("a"), item("b"), LayoutPlanner.hiddenDivider].contains($0) }
        XCTAssertEqual(relevant, [item("b"), LayoutPlanner.hiddenDivider, item("a")])
        // Both items sit on the wrong side of the anchored divider.
        XCTAssertEqual(steps.count, 2)
        XCTAssertTrue(result.contains(item("x")) && result.contains(item("y")))
    }

    func testAnchorsOutOfOrderThrows() {
        let current = [LayoutPlanner.stashDivider, LayoutPlanner.hiddenDivider]
        let target = [LayoutPlanner.hiddenDivider, LayoutPlanner.stashDivider]
        XCTAssertThrowsError(try LayoutPlanner.plan(current: current, target: target)) { error in
            XCTAssertEqual(error as? LayoutPlanner.PlanError, .anchorsOutOfOrder)
        }
    }

    func testRandomPermutationsReachTarget() throws {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<300 {
            let names = (0..<Int.random(in: 2...14, using: &generator)).map { "i\($0)" }
            var current = names.map(item)
            current.insert(LayoutPlanner.stashDivider, at: Int.random(in: 0...current.count, using: &generator))
            let stashIndex = current.firstIndex(of: LayoutPlanner.stashDivider)!
            current.insert(LayoutPlanner.hiddenDivider, at: Int.random(in: (stashIndex + 1)...current.count, using: &generator))

            var shuffled = names.map(item).shuffled(using: &generator)
            let cut1 = Int.random(in: 0...shuffled.count, using: &generator)
            shuffled.insert(LayoutPlanner.stashDivider, at: cut1)
            let cut2 = Int.random(in: (cut1 + 1)...shuffled.count, using: &generator)
            shuffled.insert(LayoutPlanner.hiddenDivider, at: cut2)
            let target = shuffled

            let steps = try LayoutPlanner.plan(current: current, target: target)
            XCTAssertEqual(LayoutPlanner.apply(steps, to: current), target)
            XCTAssertLessThanOrEqual(steps.count, names.count)
        }
    }

    func testTargetOrderForScene() {
        let layout = SceneLayout(visible: [key("v")], hidden: [key("h")], stash: [key("s")])
        XCTAssertEqual(
            LayoutPlanner.targetOrder(for: layout, includesStash: true),
            [item("s"), LayoutPlanner.stashDivider, item("h"), LayoutPlanner.hiddenDivider, item("v")]
        )
        XCTAssertEqual(
            LayoutPlanner.targetOrder(for: layout, includesStash: false),
            [item("s"), item("h"), LayoutPlanner.hiddenDivider, item("v")]
        )
    }

    func testPlacementForSection() {
        XCTAssertEqual(LayoutPlanner.placement(for: .visible, includesStash: true), .rightOf(LayoutPlanner.hiddenDivider))
        XCTAssertEqual(LayoutPlanner.placement(for: .hidden, includesStash: true), .leftOf(LayoutPlanner.hiddenDivider))
        XCTAssertEqual(LayoutPlanner.placement(for: .stash, includesStash: true), .leftOf(LayoutPlanner.stashDivider))
        XCTAssertEqual(LayoutPlanner.placement(for: .stash, includesStash: false), .leftOf(LayoutPlanner.hiddenDivider))
    }

    func testSceneLayoutHelpers() {
        var layout = SceneLayout(visible: [key("v")], hidden: [key("h")])
        layout[.stash] = [key("s")]
        XCTAssertEqual(layout.section(of: key("s")), .stash)
        XCTAssertNil(layout.section(of: key("zzz")))
        XCTAssertEqual(layout.itemCount, 3)
        XCTAssertEqual(layout.leftToRight, [key("s"), key("h"), key("v")])
    }
}

final class CollapseMetricsTests: XCTestCase {
    func testWideLength() {
        XCTAssertEqual(CollapseMetrics.wideLength(screenWidths: [1512]), 3_024)
        XCTAssertEqual(CollapseMetrics.wideLength(screenWidths: [800]), 2_400)
        XCTAssertEqual(CollapseMetrics.wideLength(screenWidths: [6_016]), 10_000)
        XCTAssertEqual(CollapseMetrics.wideLength(screenWidths: []), 2_880)
    }

    func testSteppedUnitStaysBelowHalfTheNarrowestScreen() {
        // 1728 pt notched display: 864 is half; with 16 pt padding the largest safe length is 847.
        XCTAssertEqual(CollapseMetrics.steppedUnit(screenWidths: [1728]), 847)
        XCTAssertEqual(CollapseMetrics.steppedUnit(screenWidths: [2560, 1512]), 739)
        for width in [1280.0, 1440, 1512, 1728, 2560, 3008] {
            let unit = CollapseMetrics.steppedUnit(screenWidths: [width])
            XCTAssertLessThan(unit + CollapseMetrics.itemPadding, width / 2)
        }
    }

    func testSpacerCountCoversWidestScreen() {
        for widths in [[1512.0], [1728], [1512, 2560], [1280, 3840], [1440, 5120]] {
            let unit = CollapseMetrics.steppedUnit(screenWidths: widths)
            let spacers = CollapseMetrics.steppedSpacerCount(screenWidths: widths)
            XCTAssertGreaterThanOrEqual(spacers, 1)
            XCTAssertLessThanOrEqual(spacers, 6)
            if spacers < 6 {
                XCTAssertGreaterThanOrEqual(Double(spacers + 1) * unit, widths.max()!)
            }
        }
    }

    func testRampSteps() {
        XCTAssertEqual(CollapseMetrics.rampSteps(from: 0, to: 100), [40, 80, 100])
        XCTAssertEqual(CollapseMetrics.rampSteps(from: 0, to: 80), [40, 80])
        XCTAssertEqual(CollapseMetrics.rampSteps(from: 300, to: 20), [20])
        XCTAssertEqual(CollapseMetrics.rampSteps(from: 5, to: 5), [5])
    }

    func testPositionsRightOfItem() {
        let positions = CollapseMetrics.positionsRight(of: 1, count: 2)
        XCTAssertEqual(positions.count, 2)
        XCTAssertTrue(positions.allSatisfy { $0 < 1 && $0 > 0 })
        XCTAssertGreaterThan(positions[0], positions[1])
        XCTAssertEqual(CollapseMetrics.positionsRight(of: 300, count: 0), [])
        XCTAssertTrue(CollapseMetrics.positionsRight(of: 0, count: 3).allSatisfy { $0 == 0 })
    }
}

/// A small deterministic generator for reproducible random tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
