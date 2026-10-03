import XCTest
@testable import MenoCore

final class KnownItemsTests: XCTestCase {
    private func key(_ owner: String, _ token: String) -> MenuItemKey {
        MenuItemKey(owner: owner, token: token)
    }

    /// Known items after a first scan, which announces nothing.
    private func known(after scan: [MenuItemKey]) -> KnownItems {
        var known = KnownItems()
        _ = known.arrivals(in: scan)
        return known
    }

    func testChangingTextOfAnAppsIconsIsNothingNew() {
        let stats = "eu.exelban.Stats"
        var known = known(after: [key(stats, "ax:battery charging"), key(stats, "ax:cpu")])
        XCTAssertEqual(known.arrivals(in: [key(stats, "ax:battery remaining"), key(stats, "ax:cpu")]), [])
        XCTAssertEqual(known.arrivals(in: [key(stats, "ax:battery full"), key(stats, "ax:cpu load")]), [])
        // Nothing of the text is kept, so the list does not grow.
        XCTAssertEqual(known.keys, [])
        XCTAssertEqual(known.itemCounts, [stats: 2])
    }

    func testAnotherIconOfAnAppIsNew() {
        let stats = "eu.exelban.Stats"
        var known = known(after: [key(stats, "ax:battery"), key(stats, "ax:cpu")])
        let gpu = key(stats, "ax:gpu")
        XCTAssertEqual(known.arrivals(in: [gpu, key(stats, "ax:battery"), key(stats, "ax:cpu")]), [gpu])
        // Showing fewer, then as many again, is nothing new.
        XCTAssertEqual(known.arrivals(in: [key(stats, "ax:cpu")]), [])
        XCTAssertEqual(known.arrivals(in: [key(stats, "ax:fan"), key(stats, "ax:battery"), key(stats, "ax:cpu")]), [])
    }

    func testANewAppIsNew() {
        var known = known(after: [key("com.apple.controlcenter", "id:wifi")])
        let first = key("com.example.monitor", "ax:cpu")
        let second = key("com.example.monitor", "ax:memory")
        XCTAssertEqual(known.arrivals(in: [first, second, key("com.apple.controlcenter", "id:wifi")]), [first, second])
        let solo = key("com.example.clock", "solo")
        XCTAssertEqual(known.arrivals(in: [solo]), [solo])
        XCTAssertEqual(known.arrivals(in: [solo, first, second]), [])
    }

    func testAnAppGoingFromOneIconToSeveral() {
        let app = "com.example.vpn"
        var known = known(after: [key(app, "solo")])
        // Its one icon is now named by its text, next to a new one.
        let added = key(app, "ax:status")
        XCTAssertEqual(known.arrivals(in: [added, key(app, "ax:connected")]), [added])
        // Back to one icon: nothing new.
        XCTAssertEqual(known.arrivals(in: [key(app, "solo")]), [])
    }

    func testReadingWhatEarlierVersionsWrote() throws {
        let old = #"["com.example.clock#solo", "eu.exelban.Stats#ax:battery charging", "eu.exelban.Stats#ax:battery full", "com.apple.controlcenter#id:wifi", "eu.exelban.Stats#ax:cpu~2"]"#
        var known = try KnownItems.decode(from: Data(old.utf8))
        XCTAssertEqual(known.keys, ["com.example.clock#solo", "com.apple.controlcenter#id:wifi"])
        XCTAssertEqual(known.itemCounts, ["eu.exelban.Stats": 0])
        // The app is known; how many icons it shows is learned first.
        let stats = "eu.exelban.Stats"
        XCTAssertEqual(known.arrivals(in: [key(stats, "ax:battery"), key(stats, "ax:cpu")]), [])
        XCTAssertEqual(known.itemCounts[stats], 2)
        let gpu = key(stats, "ax:gpu")
        XCTAssertEqual(known.arrivals(in: [gpu, key(stats, "ax:battery"), key(stats, "ax:cpu")]), [gpu])
    }

    func testRoundTrip() throws {
        let known = KnownItems(keys: ["com.example.clock#solo"], itemCounts: ["eu.exelban.Stats": 3])
        let data = try JSONEncoder().encode(known)
        XCTAssertEqual(try KnownItems.decode(from: data), known)
        XCTAssertThrowsError(try KnownItems.decode(from: Data("{".utf8)))
    }
}
