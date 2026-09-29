import XCTest
@testable import MenoCore

final class ChangeTrackerTests: XCTestCase {
    private let sync = MenuItemKey(owner: "com.example.sync", token: "solo")
    private let vpn = MenuItemKey(owner: "com.example.vpn", token: "solo")
    private let start = Date(timeIntervalSince1970: 1_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testFirstCheckOnlySetsTheBaseline() {
        var tracker = ChangeTracker()
        XCTAssertEqual(tracker.update([sync: .init(texts: ["Up to date"])], at: at(0)), [])
        XCTAssertEqual(tracker.update([sync: .init(texts: ["Up to date"])], at: at(3)), [])
    }

    func testLastingChangeIsReportedOnce() {
        var tracker = ChangeTracker()
        _ = tracker.update([sync: .init(texts: ["Up to date"])], at: at(0))
        XCTAssertEqual(tracker.update([sync: .init(texts: ["Sync failed"])], at: at(3)), [])
        XCTAssertEqual(tracker.update([sync: .init(texts: ["Sync failed"])], at: at(6)), [sync])
        XCTAssertEqual(tracker.update([sync: .init(texts: ["Sync failed"])], at: at(9)), [])
    }

    func testFlickerIsIgnored() {
        var tracker = ChangeTracker()
        _ = tracker.update([sync: .init(texts: ["Up to date"])], at: at(0))
        XCTAssertEqual(tracker.update([sync: .init(texts: ["Checking"])], at: at(3)), [])
        XCTAssertEqual(tracker.update([sync: .init(texts: ["Up to date"])], at: at(6)), [])
        XCTAssertEqual(tracker.update([sync: .init(texts: ["Up to date"])], at: at(9)), [])
    }

    func testNumbersDoNotCount() {
        XCTAssertEqual(ChangeTracker.Sample(texts: ["Battery 80%"]), ChangeTracker.Sample(texts: ["Battery 79%"]))
        XCTAssertNotEqual(ChangeTracker.Sample(texts: ["Paused"]), ChangeTracker.Sample(texts: ["Syncing"]))
    }

    func testCooldown() {
        var tracker = ChangeTracker(confirmations: 1, cooldown: 30)
        _ = tracker.update([sync: .init(text: "a")], at: at(0))
        XCTAssertEqual(tracker.update([sync: .init(text: "b")], at: at(3)), [sync])
        // Changes within the cooldown become the baseline without a report.
        XCTAssertEqual(tracker.update([sync: .init(text: "c")], at: at(10)), [])
        XCTAssertEqual(tracker.update([sync: .init(text: "c")], at: at(40)), [])
        XCTAssertEqual(tracker.update([sync: .init(text: "d")], at: at(43)), [sync])
    }

    func testChangesWhileAbsorbingAreNotReported() {
        var tracker = ChangeTracker()
        _ = tracker.update([sync: .init(text: "badge")], at: at(0))
        _ = tracker.update([sync: .init(text: "plain")], at: at(3), absorbing: true)
        XCTAssertEqual(tracker.update([sync: .init(text: "plain")], at: at(6)), [])
        XCTAssertEqual(tracker.update([sync: .init(text: "plain")], at: at(9)), [])
    }

    func testArtworkChange() {
        let plain = GlyphSignature(cells: Array(repeating: 3, count: 64) + Array(repeating: 0, count: 192))
        let badged = GlyphSignature(cells: Array(repeating: 3, count: 64) + Array(repeating: 3 | (1 << 2), count: 32) + Array(repeating: 0, count: 160))
        var tracker = ChangeTracker()
        _ = tracker.update([sync: .init(text: "", glyph: plain)], at: at(0))
        // A check without a capture keeps the old artwork as the baseline.
        XCTAssertEqual(tracker.update([sync: .init(text: "", glyph: nil)], at: at(3)), [])
        XCTAssertEqual(tracker.update([sync: .init(text: "", glyph: badged)], at: at(6)), [])
        XCTAssertEqual(tracker.update([sync: .init(text: "", glyph: badged)], at: at(9)), [sync])
    }

    func testItemsAreTrackedSeparatelyAndForgotten() {
        var tracker = ChangeTracker(confirmations: 1)
        _ = tracker.update([sync: .init(text: "a"), vpn: .init(text: "on")], at: at(0))
        XCTAssertEqual(tracker.update([sync: .init(text: "b"), vpn: .init(text: "off")], at: at(3)), [sync, vpn])
        // Unwatched, then watched again: the first check is a new baseline.
        _ = tracker.update([sync: .init(text: "b")], at: at(6))
        XCTAssertEqual(tracker.update([sync: .init(text: "b"), vpn: .init(text: "on")], at: at(9)), [])
    }
}
