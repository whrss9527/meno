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
}
