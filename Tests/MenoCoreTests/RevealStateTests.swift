import XCTest
@testable import MenoCore

final class RevealStateTests: XCTestCase {
    func testNestedLayoutsRestoreEachInitialVisibility() {
        for initial in [SectionVisibility.collapsed, .revealed, .revealedAll] {
            var state = RevealState(visibility: initial)
            XCTAssertTrue(state.beginLayoutSession())
            state.reveal(all: true)
            XCTAssertFalse(state.beginLayoutSession())
            XCTAssertEqual(state.holds, 1)
            XCTAssertEqual(state.zenLifts, 1)
            XCTAssertNil(state.endLayoutSession())
            XCTAssertEqual(state.endLayoutSession(), .restore(initial))
            XCTAssertEqual(state.holds, 0)
            XCTAssertEqual(state.zenLifts, 0)
            XCTAssertNil(state.endLayoutSession())
        }
    }

    func testDeferredCollapseOverridesLayoutSnapshot() {
        var state = RevealState(visibility: .revealed)
        XCTAssertTrue(state.beginLayoutSession())
        state.reveal(all: true)
        XCTAssertFalse(state.collapse())
        XCTAssertEqual(state.visibility, .revealedAll)
        XCTAssertEqual(state.endLayoutSession(), .restore(.collapsed))
        XCTAssertTrue(state.collapse())
        XCTAssertEqual(state.visibility, .collapsed)
    }

    func testActivationFinishingAfterLayoutRestoresCollapsed() {
        var state = RevealState()
        XCTAssertTrue(state.beginLayoutSession())
        state.reveal(all: true)
        state.beginActivation()
        XCTAssertEqual(state.endLayoutSession(), .held)
        XCTAssertEqual(state.endActivation(), .collapsed)
        XCTAssertEqual(state.holds, 0)
        XCTAssertEqual(state.zenLifts, 0)
    }

    func testOverlappingActivationsKeepFirstSnapshotAndRuleHold() {
        var state = RevealState()
        state.beginActivation()
        state.reveal(all: false)
        state.beginActivation()
        XCTAssertNil(state.endActivation())
        XCTAssertEqual(state.endActivation(), .collapsed)
        state.hold()
        XCTAssertNil(state.endActivation())
        XCTAssertEqual(state.holds, 1)
        state.beginActivation()
        XCTAssertNil(state.endActivation())
        XCTAssertEqual(state.holds, 1)
        state.release()
        state.release()
        XCTAssertEqual(state.holds, 0)
    }

    func testZenVisibilityAndTemporaryLift() {
        var state = RevealState(visibility: .revealedAll)
        XCTAssertEqual(state.barState(zenActive: true), BarState(hiddenCollapsed: true, stashCollapsed: true, zen: true))
        state.beginActivation()
        XCTAssertEqual(state.barState(zenActive: true), BarState())
        _ = state.endActivation()
        XCTAssertTrue(state.barState(zenActive: true).zen)
        state.reveal(all: false)
        XCTAssertEqual(state.visibility, .revealedAll)
    }
}
