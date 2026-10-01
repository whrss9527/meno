import XCTest
@testable import MenoCore

final class SectionKeeperTests: XCTestCase {
    private let dropbox = MenuItemKey(owner: "com.getdropbox.dropbox", token: "solo")
    private let weather = MenuItemKey(owner: "com.example.weather", token: "solo")
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func seen(_ key: MenuItemKey, _ section: ItemSection?, process: Int32 = 100) -> SectionKeeper.Observation {
        SectionKeeper.Observation(key: key, section: section, process: process)
    }

    func testRemembersWhereItemsAreAtFirst() {
        var keeper = SectionKeeper()
        let misplaced = keeper.observe([seen(dropbox, .hidden), seen(weather, .visible)], at: now, includesStash: true)
        XCTAssertEqual(misplaced, [])
        XCTAssertEqual(keeper.memory[dropbox.rawValue]?.section, .hidden)
        XCTAssertEqual(keeper.memory[weather.rawValue]?.section, .visible)
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
        _ = keeper.observe([seen(dropbox, .hidden), seen(weather, .visible)], at: now, includesStash: true)
        // Dropbox quits, then comes back at the left end, in the Stash.
        _ = keeper.observe([seen(weather, .visible)], at: now, includesStash: true)
        let misplaced = keeper.observe([seen(dropbox, .stash, process: 200), seen(weather, .visible)], at: now, includesStash: true)
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
        // An app that was running all along adds an item: that was on purpose.
        let timer = MenuItemKey(owner: "com.example.tools", token: "id:timer")
        let clock = MenuItemKey(owner: "com.example.tools", token: "id:clock")
        var keeper = SectionKeeper(memory: [timer.rawValue: .init(section: .visible, seen: now)])
        _ = keeper.observe([seen(clock, .hidden, process: 42), seen(weather, .visible)], at: now, includesStash: true)
        let later = now.addingTimeInterval(SectionKeeper.appearanceWindow + 60)
        XCTAssertEqual(keeper.observe([seen(clock, .hidden, process: 42), seen(timer, .hidden, process: 42)], at: later, includesStash: true), [])
        XCTAssertEqual(keeper.memory[timer.rawValue]?.section, .hidden)
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

    func testOnlySteadyKeysAreKept() {
        var keeper = SectionKeeper()
        let first = MenuItemKey(owner: "com.example.multi", token: "idx:0")
        let text = MenuItemKey(owner: "com.example.multi", token: "ax:status")
        let twin = MenuItemKey(owner: "com.example.multi", token: "id:status~2")
        let identified = MenuItemKey(owner: "com.example.multi", token: "id:status")
        _ = keeper.observe([seen(first, .hidden), seen(text, .hidden), seen(twin, .hidden)], at: now, includesStash: true)
        XCTAssertTrue(keeper.memory.isEmpty)
        XCTAssertFalse(first.isSteady)
        XCTAssertFalse(text.isSteady)
        XCTAssertFalse(twin.isSteady)
        XCTAssertTrue(identified.isSteady)
        XCTAssertTrue(dropbox.isSteady)
    }

    func testMovesMenoMadeCountAsWhereItemsBelong() {
        var keeper = SectionKeeper(memory: [dropbox.rawValue: .init(section: .visible, seen: now)])
        // A rule hid Dropbox before the first scan was taken in.
        keeper.record(dropbox, in: .hidden, process: 100, at: now, includesStash: true)
        XCTAssertEqual(keeper.memory[dropbox.rawValue]?.section, .hidden)
        XCTAssertEqual(keeper.observe([seen(dropbox, .hidden)], at: now, includesStash: true), [])
        // Text keys are not recorded either.
        let text = MenuItemKey(owner: "com.example.multi", token: "ax:status")
        keeper.record(text, in: .hidden, process: 5, at: now, includesStash: true)
        XCTAssertNil(keeper.memory[text.rawValue])
    }

    func testAnItemWhosePlaceIsNotKnownYetStillCameWithItsApp() {
        // With the stepped engine, hidden items have no known place until
        // they are shown, which may be long after their app started.
        var keeper = SectionKeeper(memory: [dropbox.rawValue: .init(section: .hidden, seen: now)])
        _ = keeper.observe([seen(weather, .visible, process: 1)], at: now, includesStash: true)
        _ = keeper.observe([seen(weather, .visible, process: 1), seen(dropbox, nil, process: 9)], at: now, includesStash: true)
        let later = now.addingTimeInterval(SectionKeeper.appearanceWindow * 10)
        let misplaced = keeper.observe([seen(weather, .visible, process: 1), seen(dropbox, .stash, process: 9)], at: later, includesStash: true)
        XCTAssertEqual(misplaced, [SectionKeeper.Misplacement(key: dropbox, found: .stash, belongs: .hidden)])
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
            weather.rawValue: .init(section: .visible, seen: now),
        ])
        keeper.forget(notSeenSince: now.addingTimeInterval(-180 * 86_400))
        XCTAssertNil(keeper.memory[dropbox.rawValue])
        XCTAssertNotNil(keeper.memory[weather.rawValue])
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
