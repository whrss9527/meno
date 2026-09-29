import XCTest
@testable import MenoCore

final class SectionKeeperTests: XCTestCase {
    private let dropbox = MenuItemKey(owner: "com.getdropbox.dropbox", token: "solo")
    private let vpn = MenuItemKey(owner: "com.example.vpn", token: "solo")
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func seen(_ key: MenuItemKey, _ section: ItemSection?, process: Int32 = 100) -> SectionKeeper.Observation {
        SectionKeeper.Observation(key: key, section: section, process: process)
    }

    func testRemembersWhereItemsAreAtFirst() {
        var keeper = SectionKeeper()
        let misplaced = keeper.observe([seen(dropbox, .hidden), seen(vpn, .visible)], at: now, includesStash: true)
        XCTAssertEqual(misplaced, [])
        XCTAssertEqual(keeper.memory[dropbox.rawValue]?.section, .hidden)
        XCTAssertEqual(keeper.memory[vpn.rawValue]?.section, .visible)
        XCTAssertTrue(keeper.hasUnsavedChanges)
    }

    func testMovingAnItemInTheMenuBarIsRemembered() {
        var keeper = SectionKeeper()
        _ = keeper.observe([seen(dropbox, .hidden)], at: now, includesStash: true)
        let misplaced = keeper.observe([seen(dropbox, .visible)], at: now, includesStash: true)
        XCTAssertEqual(misplaced, [])
        XCTAssertEqual(keeper.memory[dropbox.rawValue]?.section, .visible)
    }

    func testAnItemThatComesBackElsewhereBelongsWhereItWasLeft() {
        var keeper = SectionKeeper()
        _ = keeper.observe([seen(dropbox, .hidden), seen(vpn, .visible)], at: now, includesStash: true)
        // Dropbox quits, then comes back at the left end, in the Stash.
        _ = keeper.observe([seen(vpn, .visible)], at: now, includesStash: true)
        let misplaced = keeper.observe([seen(dropbox, .stash, process: 200), seen(vpn, .visible)], at: now, includesStash: true)
        XCTAssertEqual(misplaced, [SectionKeeper.Misplacement(key: dropbox, found: .stash, belongs: .hidden)])
        XCTAssertEqual(keeper.memory[dropbox.rawValue]?.section, .hidden)

        // Put back: seen in Hidden while still there, which confirms it.
        keeper.didPutBack(dropbox)
        XCTAssertEqual(keeper.observe([seen(dropbox, .hidden, process: 200)], at: now, includesStash: true), [])
        XCTAssertEqual(keeper.memory[dropbox.rawValue]?.section, .hidden)
    }

    func testAnAppThatRestartedBetweenTwoScansCountsAsNew() {
        var keeper = SectionKeeper()
        _ = keeper.observe([seen(dropbox, .hidden, process: 100)], at: now, includesStash: true)
        let misplaced = keeper.observe([seen(dropbox, .visible, process: 101)], at: now, includesStash: true)
        XCTAssertEqual(misplaced, [SectionKeeper.Misplacement(key: dropbox, found: .visible, belongs: .hidden)])
    }

    func testAnItemThatComesBackInPlaceNeedsNothing() {
        var keeper = SectionKeeper()
        _ = keeper.observe([seen(dropbox, .hidden)], at: now, includesStash: true)
        _ = keeper.observe([], at: now, includesStash: true)
        XCTAssertEqual(keeper.observe([seen(dropbox, .hidden, process: 300)], at: now, includesStash: true), [])
    }

    func testAnItemThatShowsUpInAnAppThatWasThereCountsWhereItIs() {
        // A key can change with an item's text; the item was not moved.
        let syncing = MenuItemKey(owner: "com.example.sync", token: "ax:syncing")
        let idle = MenuItemKey(owner: "com.example.sync", token: "ax:up to date")
        var keeper = SectionKeeper(memory: [syncing.rawValue: .init(section: .visible, seen: now)])
        _ = keeper.observe([seen(idle, .hidden, process: 42), seen(vpn, .visible)], at: now, includesStash: true)
        let later = now.addingTimeInterval(SectionKeeper.appearanceWindow + 60)
        XCTAssertEqual(keeper.observe([seen(syncing, .hidden, process: 42), seen(vpn, .visible)], at: later, includesStash: true), [])
        XCTAssertEqual(keeper.memory[syncing.rawValue]?.section, .hidden)
    }

    func testItemsOfAnAppThatJustAppearedStillCount() {
        // An app that adds its second item a little after launching.
        let second = MenuItemKey(owner: "com.getdropbox.dropbox", token: "id:second")
        var keeper = SectionKeeper(memory: [second.rawValue: .init(section: .hidden, seen: now)])
        _ = keeper.observe([seen(dropbox, .hidden, process: 7)], at: now, includesStash: true)
        let misplaced = keeper.observe(
            [seen(dropbox, .hidden, process: 7), seen(second, .stash, process: 7)],
            at: now.addingTimeInterval(20),
            includesStash: true
        )
        XCTAssertEqual(misplaced, [SectionKeeper.Misplacement(key: second, found: .stash, belongs: .hidden)])
    }

    func testGivesUpOnAnItemItsAppKeepsMoving() {
        var keeper = SectionKeeper()
        _ = keeper.observe([seen(dropbox, .hidden)], at: now, includesStash: true)
        for round in 0..<SectionKeeper.putBackLimit {
            _ = keeper.observe([], at: now, includesStash: true)
            let misplaced = keeper.observe([seen(dropbox, .visible, process: Int32(200 + round))], at: now, includesStash: true)
            XCTAssertEqual(misplaced.count, 1, "round \(round)")
            keeper.didPutBack(dropbox)
        }
        _ = keeper.observe([], at: now, includesStash: true)
        XCTAssertEqual(keeper.observe([seen(dropbox, .visible, process: 900)], at: now, includesStash: true), [])
        XCTAssertEqual(keeper.memory[dropbox.rawValue]?.section, .visible)
    }

    func testPositionalKeysAreLeftAlone() {
        var keeper = SectionKeeper()
        let first = MenuItemKey(owner: "com.example.multi", token: "idx:0")
        let twin = MenuItemKey(owner: "com.example.multi", token: "ax:status~2")
        _ = keeper.observe([seen(first, .hidden), seen(twin, .hidden)], at: now, includesStash: true)
        XCTAssertTrue(keeper.memory.isEmpty)
        XCTAssertTrue(first.isPositional)
        XCTAssertTrue(twin.isPositional)
        XCTAssertFalse(dropbox.isPositional)
    }

    func testAnUnknownPositionKeepsTheItemAsItWas() {
        var keeper = SectionKeeper()
        _ = keeper.observe([seen(dropbox, .hidden)], at: now, includesStash: true)
        // Hidden by the stepped engine: its position is not known.
        XCTAssertEqual(keeper.observe([seen(dropbox, nil)], at: now, includesStash: true), [])
        XCTAssertEqual(keeper.observe([seen(dropbox, .hidden)], at: now, includesStash: true), [])
        // Its app restarted meanwhile: once known again, it counts as new.
        _ = keeper.observe([seen(dropbox, nil, process: 500)], at: now, includesStash: true)
        let misplaced = keeper.observe([seen(dropbox, .stash, process: 500)], at: now, includesStash: true)
        XCTAssertEqual(misplaced, [SectionKeeper.Misplacement(key: dropbox, found: .stash, belongs: .hidden)])
    }

    func testWithoutTheStashItsItemsCountAsHidden() {
        var keeper = SectionKeeper(memory: [dropbox.rawValue: .init(section: .stash, seen: now)])
        XCTAssertEqual(keeper.observe([seen(dropbox, .hidden)], at: now, includesStash: false), [])
        // The Stash is still remembered for when it is back.
        XCTAssertEqual(keeper.memory[dropbox.rawValue]?.section, .stash)
    }

    func testAcceptingKeepsItemsWhereTheyAre() {
        var keeper = SectionKeeper(memory: [dropbox.rawValue: .init(section: .hidden, seen: now)])
        let misplaced = keeper.observe([seen(dropbox, .visible)], at: now, includesStash: true)
        keeper.accept(misplaced, at: now)
        XCTAssertEqual(keeper.memory[dropbox.rawValue]?.section, .visible)
    }

    func testForgetsItemsNotSeenForLong() {
        let old = now.addingTimeInterval(-200 * 86_400)
        var keeper = SectionKeeper(memory: [
            dropbox.rawValue: .init(section: .hidden, seen: old),
            vpn.rawValue: .init(section: .visible, seen: now),
        ])
        keeper.forget(notSeenSince: now.addingTimeInterval(-180 * 86_400))
        XCTAssertNil(keeper.memory[dropbox.rawValue])
        XCTAssertNotNil(keeper.memory[vpn.rawValue])
        XCTAssertTrue(keeper.hasUnsavedChanges)
    }

    func testSeenDatesChangeOncePerDay() {
        var keeper = SectionKeeper()
        _ = keeper.observe([seen(dropbox, .hidden)], at: now, includesStash: true)
        keeper.markSaved()
        _ = keeper.observe([seen(dropbox, .hidden)], at: now.addingTimeInterval(60), includesStash: true)
        XCTAssertFalse(keeper.hasUnsavedChanges)
        _ = keeper.observe([seen(dropbox, .hidden)], at: now.addingTimeInterval(2 * 86_400), includesStash: true)
        XCTAssertTrue(keeper.hasUnsavedChanges)
    }

    func testMemoryRoundTrips() throws {
        var keeper = SectionKeeper()
        _ = keeper.observe([seen(dropbox, .stash)], at: now, includesStash: true)
        let data = try JSONEncoder().encode(keeper.memory)
        let decoded = try JSONDecoder().decode([String: SectionKeeper.Remembered].self, from: data)
        XCTAssertEqual(decoded, keeper.memory)
    }
}
