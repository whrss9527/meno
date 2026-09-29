import XCTest
@testable import MenoCore

final class TemporaryPlacementTests: XCTestCase {
    private let dropbox = MenuItemKey(owner: "com.getdropbox.dropbox", token: "solo")
    private let timer = MenuItemKey(owner: "com.example.timer", token: "solo")

    func testShowAndReturn() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var placements: [TemporaryPlacement] = []
        placements.show(dropbox, from: .hidden, until: start.addingTimeInterval(900))
        placements.show(timer, from: .stash, until: start.addingTimeInterval(3600))
        XCTAssertEqual(placements.nextDue, start.addingTimeInterval(900))
        XCTAssertEqual(placements.placement(of: timer)?.returnSection, .stash)

        XCTAssertTrue(placements.removeDue(at: start.addingTimeInterval(899)).isEmpty)
        let due = placements.removeDue(at: start.addingTimeInterval(900))
        XCTAssertEqual(due.map(\.itemKey), [dropbox])
        XCTAssertEqual(placements.map(\.itemKey), [timer])
        XCTAssertEqual(placements.removeDue(at: start.addingTimeInterval(7200)).count, 1)
        XCTAssertNil(placements.nextDue)
    }

    func testShowingAgainKeepsTheOriginalSection() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var placements: [TemporaryPlacement] = []
        placements.show(dropbox, from: .hidden, until: start.addingTimeInterval(900))
        // Shown again while already visible: the original section stays.
        placements.show(dropbox, from: .visible, until: start.addingTimeInterval(3600))
        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(placements.first?.returnSection, .hidden)
        XCTAssertEqual(placements.first?.until, start.addingTimeInterval(3600))
    }

    func testCheckingWaitsForTheNextOneOrAMinute() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertNil([TemporaryPlacement]().delayUntilNextCheck(at: now))
        var placements: [TemporaryPlacement] = []
        placements.show(dropbox, from: .hidden, until: now.addingTimeInterval(20))
        XCTAssertEqual(placements.delayUntilNextCheck(at: now), 20)
        // One that is due but waiting does not make the check run every second.
        placements.show(timer, from: .hidden, until: now.addingTimeInterval(-300))
        XCTAssertEqual(placements.delayUntilNextCheck(at: now), 20)
        placements.removeAll { $0.itemKey == dropbox }
        XCTAssertEqual(placements.delayUntilNextCheck(at: now), 60)
        placements.show(dropbox, from: .hidden, until: now.addingTimeInterval(0.2))
        XCTAssertEqual(placements.delayUntilNextCheck(at: now), 1)
    }

    func testMovingAnItemInAStoredLayout() {
        let a = MenuItemKey(owner: "a", token: "solo")
        let layout = SceneLayout(visible: [a], hidden: [dropbox], stash: [timer])
        XCTAssertEqual(layout.moving(dropbox, to: .visible).visible, [dropbox, a])
        XCTAssertEqual(layout.moving(a, to: .hidden).hidden, [dropbox, a])
        XCTAssertEqual(layout.moving(a, to: .stash).stash, [timer, a])
        XCTAssertEqual(layout.moving(a, to: .hidden).visible, [])
        let unknown = MenuItemKey(owner: "gone", token: "solo")
        XCTAssertEqual(layout.moving(unknown, to: .visible), layout)
    }

    func testPlacementsSurviveSaving() throws {
        var settings = MenoSettings()
        settings.temporaryPlacements = [TemporaryPlacement(itemKey: dropbox, returnSection: .stash, until: Date(timeIntervalSince1970: 1_800_000_000))]
        let decoded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertEqual(decoded.temporaryPlacements, settings.temporaryPlacements)
        // Settings from before this feature have none.
        XCTAssertTrue(try MenoSettings.decode(from: Data("{}".utf8)).temporaryPlacements.isEmpty)
    }
}
