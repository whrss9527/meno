import XCTest
@testable import MenoCore

final class HidingCheckTests: XCTestCase {
    func testItemsOffTheScreenVerifyHiding() {
        var check = HidingCheck()
        XCTAssertEqual(check.verdict, .unknown)
        XCTAssertFalse(check.record(onScreen: 0, of: 5))
        XCTAssertEqual(check.verdict, .verified)
    }

    func testOneScanIsNotEnoughToFail() {
        var check = HidingCheck()
        XCTAssertFalse(check.record(onScreen: 2, of: 5))
        XCTAssertEqual(check.verdict, .unknown)
        // Off the screen in the next scan: the first was caught mid-change.
        XCTAssertFalse(check.record(onScreen: 0, of: 5))
        XCTAssertFalse(check.record(onScreen: 1, of: 5))
        XCTAssertEqual(check.verdict, .verified)
    }

    func testTwoScansInARowFailOnce() {
        var check = HidingCheck()
        XCTAssertFalse(check.record(onScreen: 3, of: 5))
        XCTAssertTrue(check.record(onScreen: 3, of: 5))
        XCTAssertEqual(check.verdict, .failed)
        // Reported once, not with every scan after.
        XCTAssertFalse(check.record(onScreen: 3, of: 5))
        check.reset()
        XCTAssertEqual(check.verdict, .unknown)
    }

    func testNothingToHideTellsNothing() {
        var check = HidingCheck()
        XCTAssertFalse(check.record(onScreen: 0, of: 0))
        XCTAssertFalse(check.record(onScreen: 0, of: 0))
        XCTAssertEqual(check.verdict, .unknown)
    }

    func testFallbackOnlyWhileMenoPicksTheEngine() {
        XCTAssertEqual(HidingEngine.automatic.fallback(after: .wide), .stepped)
        XCTAssertEqual(HidingEngine.automatic.fallback(after: .stepped), .wide)
        XCTAssertNil(HidingEngine.wide.fallback(after: .wide))
        XCTAssertNil(HidingEngine.stepped.fallback(after: .stepped))
    }
}
