#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import MenoCore

final class LaneDropTests: XCTestCase {
    /// Three items in the first row and two in the second, 80 pt wide and
    /// 30 pt high, 8 pt apart.
    let frames = [
        CGRect(x: 0, y: 0, width: 80, height: 30),
        CGRect(x: 88, y: 0, width: 80, height: 30),
        CGRect(x: 176, y: 0, width: 80, height: 30),
        CGRect(x: 0, y: 38, width: 80, height: 30),
        CGRect(x: 88, y: 38, width: 80, height: 30),
    ]

    func testGapFollowsTheMiddleOfItems() {
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 10, y: 15), frames: frames), 0)
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 50, y: 15), frames: frames), 1)
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 84, y: 15), frames: frames), 1)
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 230, y: 15), frames: frames), 3)
        // Right of the last item of a row is the end of that row.
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 400, y: 15), frames: frames), 3)
    }

    func testGapPicksTheNearestRow() {
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 10, y: 50), frames: frames), 3)
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 140, y: 50), frames: frames), 5)
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 300, y: 60), frames: frames), 5)
        // Above the items, as over a section's title, or below them.
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 100, y: -40), frames: frames), 1)
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 100, y: 200), frames: frames), 4)
        // Between the rows, the closer one.
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 10, y: 32), frames: frames), 0)
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 10, y: 36), frames: frames), 3)
    }

    func testGapInAnEmptySection() {
        XCTAssertEqual(LaneDrop.gap(at: CGPoint(x: 50, y: 50), frames: []), 0)
        XCTAssertEqual(LaneDrop.target(at: CGPoint(x: 50, y: 50), frames: [], movable: [], draggedIndex: nil), 0)
    }

    func testNothingLandsRightOfFixedItems() {
        // Two items, then Control Center and the clock.
        let movable = [true, true, false, false]
        XCTAssertEqual(LaneDrop.allowedGap(4, movable: movable), 2)
        XCTAssertEqual(LaneDrop.allowedGap(3, movable: movable), 2)
        XCTAssertEqual(LaneDrop.allowedGap(2, movable: movable), 2)
        XCTAssertEqual(LaneDrop.allowedGap(1, movable: movable), 1)
        XCTAssertEqual(LaneDrop.allowedGap(0, movable: movable), 0)
        XCTAssertEqual(LaneDrop.allowedGap(9, movable: movable), 2)
        XCTAssertEqual(LaneDrop.allowedGap(1, movable: [false]), 0)
    }

    func testDroppingNextToItselfLeavesTheItem() {
        XCTAssertFalse(LaneDrop.moves(into: 2, from: 2))
        XCTAssertFalse(LaneDrop.moves(into: 3, from: 2))
        XCTAssertTrue(LaneDrop.moves(into: 1, from: 2))
        XCTAssertTrue(LaneDrop.moves(into: 4, from: 2))
        XCTAssertTrue(LaneDrop.moves(into: 0, from: nil))
    }

    func testTarget() {
        let movable = Array(repeating: true, count: frames.count)
        // The second item, dragged over the right half of the third, lands
        // after it; over its own place it stays.
        XCTAssertEqual(LaneDrop.target(at: CGPoint(x: 230, y: 15), frames: frames, movable: movable, draggedIndex: 1), 3)
        XCTAssertNil(LaneDrop.target(at: CGPoint(x: 130, y: 15), frames: frames, movable: movable, draggedIndex: 1))
        XCTAssertNil(LaneDrop.target(at: CGPoint(x: 50, y: 15), frames: frames, movable: movable, draggedIndex: 1))
        // An item from another section can land anywhere.
        XCTAssertEqual(LaneDrop.target(at: CGPoint(x: 130, y: 15), frames: frames, movable: movable, draggedIndex: nil), 2)
        // The last item cannot pass a fixed item before it.
        let fixedAtEnd = [true, true, true, false, false]
        XCTAssertNil(LaneDrop.target(at: CGPoint(x: 140, y: 50), frames: frames, movable: fixedAtEnd, draggedIndex: 2))
        XCTAssertEqual(LaneDrop.target(at: CGPoint(x: 140, y: 50), frames: frames, movable: fixedAtEnd, draggedIndex: 0), 3)
    }
}
