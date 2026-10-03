import XCTest
@testable import MenoCore

final class UsageLogTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    let start = Date(timeIntervalSince1970: 1_780_000_000) // mid 2026
    let dropbox = MenuItemKey(owner: "com.getdropbox.dropbox", token: "solo")
    let wifi = MenuItemKey(owner: "com.apple.controlcenter", token: "id:wifi")

    func day(_ offset: Int) -> Date { start.addingTimeInterval(Double(offset) * 86_400) }

    func testDayKey() {
        XCTAssertEqual(UsageLog.dayKey(for: Date(timeIntervalSince1970: 0), calendar: calendar), "1970-01-01")
    }

    func testRecordingAndCounting() {
        var log = UsageLog()
        log.recordItemUse(dropbox, section: .hidden, source: .shelf, at: day(0), calendar: calendar)
        log.recordItemUse(dropbox, section: .visible, source: .menuBar, at: day(1), calendar: calendar)
        log.recordItemUse(wifi, section: .visible, source: .menuBar, at: day(1), calendar: calendar)

        XCTAssertEqual(log.usage(of: dropbox)?.total, 2)
        XCTAssertEqual(log.usage(of: dropbox)?.whileConcealed, 1)
        XCTAssertEqual(log.usage(of: dropbox)?.lastUsed, day(1))
        XCTAssertEqual(log.count(of: dropbox, lastDays: 1, now: day(1), calendar: calendar), 1)
        XCTAssertEqual(log.count(of: dropbox, lastDays: 7, now: day(1), calendar: calendar), 2)
        XCTAssertEqual(log.firstRecorded, day(0))

        let top = log.topItems(limit: 5, now: day(1), calendar: calendar)
        XCTAssertEqual(top.map(\.key), [dropbox, wifi])
        XCTAssertEqual(top.map(\.count), [2, 1])
    }

    func testRevealsAndPrune() {
        var log = UsageLog()
        log.recordReveal(trigger: "hover", at: day(0), calendar: calendar)
        log.recordReveal(trigger: "hover", at: day(3), calendar: calendar)
        log.recordReveal(trigger: "click", at: day(3), calendar: calendar)
        XCTAssertEqual(log.revealTriggers, ["hover": 2, "click": 1])
        let series = log.dailyReveals(lastDays: 4, now: day(3), calendar: calendar)
        XCTAssertEqual(series.map(\.count), [1, 0, 0, 2])

        log.recordItemUse(dropbox, section: nil, source: .hotkey, at: day(0), calendar: calendar)
        log.prune(keepingDays: 2, now: day(3), calendar: calendar)
        XCTAssertEqual(log.reveals.count, 1)
        XCTAssertEqual(log.usage(of: dropbox)?.daily, [:])
        XCTAssertEqual(log.usage(of: dropbox)?.total, 1)
    }

    func testSuggestions() {
        var log = UsageLog()
        let idle = MenuItemKey(owner: "com.example.idle", token: "solo")
        log.recordItemUse(idle, section: .visible, source: .menuBar, at: day(0), calendar: calendar)
        for offset in 0..<6 {
            log.recordItemUse(dropbox, section: .hidden, source: .shelf, at: day(28 + offset % 3), calendar: calendar)
        }
        let sections: [MenuItemKey: ItemSection] = [dropbox: .hidden, idle: .visible, wifi: .visible]
        let suggestions = log.suggestions(
            sections: sections,
            movable: [dropbox, idle],
            now: day(30),
            calendar: calendar
        )
        XCTAssertEqual(suggestions, [.promote(dropbox, uses: 6), .demote(idle, idleDays: 30)])
        XCTAssertEqual(suggestions.map(\.key), [dropbox, idle])

        // Not enough history yet: no demotions.
        let early = log.suggestions(sections: sections, movable: [dropbox, idle], now: day(10), calendar: calendar)
        XCTAssertFalse(early.contains { if case .demote = $0 { return true } else { return false } })
    }

    func testOnlyOpensWhileConcealedSuggestKeepingVisible() {
        var log = UsageLog()
        // Opened often while visible, then hidden.
        for offset in 0..<6 {
            log.recordItemUse(dropbox, section: .visible, source: .menuBar, at: day(28 + offset % 3), calendar: calendar)
        }
        log.recordItemUse(dropbox, section: .hidden, source: .shelf, at: day(30), calendar: calendar)
        XCTAssertEqual(log.count(of: dropbox, lastDays: 7, now: day(30), calendar: calendar), 7)
        XCTAssertEqual(log.concealedCount(of: dropbox, lastDays: 7, now: day(30), calendar: calendar), 1)
        XCTAssertEqual(log.suggestions(sections: [dropbox: .hidden], movable: [dropbox], now: day(30), calendar: calendar), [])

        // Concealed opens are pruned with the other days.
        log.prune(keepingDays: 2, now: day(40), calendar: calendar)
        XCTAssertEqual(log.usage(of: dropbox)?.dailyConcealed, [:])
    }

    func testUsageFromOtherVersionsIsKept() throws {
        // A record without the per-day concealed opens, and with a field
        // this version does not know.
        let json = #"{"items": {"com.getdropbox.dropbox#solo": {"total": 3, "daily": {"2026-05-28": 3}, "future": 1}}}"#
        let log = try TolerantJSON.decode(UsageLog.self, from: Data(json.utf8), defaults: UsageLog())
        XCTAssertEqual(log.usage(of: dropbox)?.total, 3)
        XCTAssertEqual(log.usage(of: dropbox)?.whileConcealed, 0)
        XCTAssertEqual(log.usage(of: dropbox)?.daily, ["2026-05-28": 3])
        XCTAssertEqual(log.usage(of: dropbox)?.dailyConcealed, [:])
    }

    func testStashSuggestions() {
        var log = UsageLog()
        let forgotten = MenuItemKey(owner: "com.example.forgotten", token: "solo")
        log.recordItemUse(forgotten, section: .hidden, source: .shelf, at: day(0), calendar: calendar)
        let sections: [MenuItemKey: ItemSection] = [forgotten: .hidden]
        XCTAssertEqual(
            log.suggestions(sections: sections, movable: [forgotten], now: day(61), calendar: calendar),
            [.stash(forgotten, idleDays: 61)]
        )
        // Not before 60 days, and not without the Stash.
        XCTAssertEqual(log.suggestions(sections: sections, movable: [forgotten], now: day(40), calendar: calendar), [])
        XCTAssertEqual(
            log.suggestions(sections: sections, movable: [forgotten], includesStash: false, now: day(61), calendar: calendar),
            []
        )
        // Items in the Stash already are left alone.
        XCTAssertEqual(log.suggestions(sections: [forgotten: .stash], movable: [forgotten], now: day(61), calendar: calendar), [])
    }

    func testDismissedSuggestionsStayAwayForAWhile() throws {
        var log = UsageLog()
        let idle = MenuItemKey(owner: "com.example.idle", token: "solo")
        log.recordItemUse(idle, section: .visible, source: .menuBar, at: day(0), calendar: calendar)
        let sections: [MenuItemKey: ItemSection] = [idle: .visible]
        let suggestion = try XCTUnwrap(log.suggestions(sections: sections, movable: [idle], now: day(30), calendar: calendar).first)
        log.dismiss(suggestion, at: day(30))
        // Turned down, also while its numbers change.
        XCTAssertEqual(log.suggestions(sections: sections, movable: [idle], now: day(45), calendar: calendar), [])
        XCTAssertEqual(
            log.suggestions(sections: sections, movable: [idle], now: day(91), calendar: calendar),
            [.demote(idle, idleDays: 91)]
        )
        // Other kinds of suggestions for the item are not turned down.
        XCTAssertNotEqual(UsageSuggestion.stash(idle, idleDays: 1).id, suggestion.id)

        // Dismissals are dropped once they ran out, and survive saving.
        let decoded = try TolerantJSON.decode(UsageLog.self, from: TolerantJSON.makeEncoder().encode(log), defaults: UsageLog())
        XCTAssertEqual(decoded.dismissedSuggestions, log.dismissedSuggestions)
        log.prune(keepingDays: 90, now: day(91), calendar: calendar)
        XCTAssertTrue(log.dismissedSuggestions.isEmpty)
        let old = try TolerantJSON.decode(UsageLog.self, from: Data(#"{"reveals": {}}"#.utf8), defaults: UsageLog())
        XCTAssertTrue(old.dismissedSuggestions.isEmpty)
    }
}
