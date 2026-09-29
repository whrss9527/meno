import XCTest
@testable import MenoCore

final class HostedItemsTests: XCTestCase {
    private func element(_ owner: String, _ minX: Double, _ width: Double, identifier: String? = nil, y: Double = 0) -> HostedItems.Element {
        HostedItems.Element(owner: owner, identifier: identifier, minX: minX, maxX: minX + width, minY: y, maxY: y + 24)
    }

    func testControlCenterStandInIsADuplicate() {
        let elements = [
            element("com.example.sync", 1000, 30),
            element("com.apple.controlcenter", 1001, 28),
            element("com.apple.controlcenter", 1200, 30, identifier: "com.apple.menuextra.wifi"),
        ]
        XCTAssertEqual(HostedItems.duplicates(in: elements), [1])
    }

    func testAppleItemsAreNeverDuplicates() {
        // A stale frame of an app item must not remove the Wi‑Fi item.
        let elements = [
            element("com.example.sync", 1200, 30),
            element("com.apple.controlcenter", 1200, 30, identifier: "com.apple.menuextra.wifi"),
        ]
        XCTAssertTrue(HostedItems.duplicates(in: elements).isEmpty)
    }

    func testNeighboursAndOtherDisplaysAreKept() {
        let elements = [
            element("com.example.sync", 1000, 30),
            // Touches the app item but covers less than half of it.
            element("com.apple.controlcenter", 1020, 30),
            // Same x on a display stacked above.
            element("com.apple.controlcenter", 1000, 30, y: -1080),
            // Elements without width say nothing about positions.
            element("com.apple.controlcenter", 1000, 0),
        ]
        XCTAssertTrue(HostedItems.duplicates(in: elements).isEmpty)
    }

    func testOnlyHostsAreRemoved() {
        let elements = [
            element("com.example.one", 1000, 30),
            element("com.example.two", 1000, 30),
        ]
        XCTAssertTrue(HostedItems.duplicates(in: elements).isEmpty)
    }
}
