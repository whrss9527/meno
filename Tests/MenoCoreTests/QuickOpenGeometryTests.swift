import Foundation
import XCTest
@testable import MenoCore

final class QuickOpenGeometryTests: XCTestCase {
    func testLargeBottomDockKeepsThePaletteAboveTheReservedArea() {
        let visible = CGRect(x: 0, y: 80, width: 800, height: 496)
        let frame = QuickOpenGeometry.frame(preferredSize: CGSize(width: 648, height: 524), in: visible)
        XCTAssertTrue(visible.contains(frame))
    }

    func testCompactWorkspaceBoundsBothDimensions() {
        let visible = CGRect(x: 140, y: 120, width: 520, height: 360)
        let frame = QuickOpenGeometry.frame(preferredSize: CGSize(width: 648, height: 524), in: visible)
        XCTAssertLessThanOrEqual(frame.width, 520)
        XCTAssertLessThanOrEqual(frame.height, 360)
        XCTAssertTrue(visible.contains(frame))
    }

    func testSecondaryDisplayWithNegativeOriginStaysVisible() {
        let visible = CGRect(x: -1280, y: 80, width: 1280, height: 616)
        let frame = QuickOpenGeometry.frame(preferredSize: CGSize(width: 648, height: 524), in: visible)
        XCTAssertTrue(visible.contains(frame))
    }

    func testUnrestrictedWorkspaceKeepsTheExistingPosition() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let frame = QuickOpenGeometry.frame(preferredSize: CGSize(width: 648, height: 300), in: screen)
        XCTAssertEqual(frame, CGRect(x: 476, y: 420, width: 648, height: 300))
    }

    func testContentBudgetLeavesSpaceForWindowShadowPadding() {
        XCTAssertEqual(QuickOpenGeometry.contentSize(in: CGSize(width: 520, height: 360)), CGSize(width: 472, height: 312))
        XCTAssertEqual(QuickOpenGeometry.contentSize(in: CGSize(width: 1440, height: 800)).width, 600)
    }
}
