import Foundation
import XCTest
@testable import MenoCore

final class InventoryBuilderTests: XCTestCase {
    private let layout = DividerLayout(hidden: HorizontalSpan(x: 200, width: 20), stash: HorizontalSpan(x: 100, width: 20))
    private func item(_ owner: String = "test.app", x: CGFloat, width: CGFloat = 20, identifier: String? = nil, onScreen: Bool = true) -> InventoryBuilder.RawItem {
        .init(owner: owner, appName: "Example", frame: CGRect(x: x, y: 0, width: width, height: 20), identifier: identifier, detail: "Example", isOnScreen: onScreen)
    }

    func testLeftoversDoNotChangeSurvivingSiblingKey() {
        let result = InventoryBuilder.build(raw: [item(x: 300), item(x: 320, width: 0)], dividers: .init(layout: layout), cached: .init())
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.key.token, "solo")
        XCTAssertEqual(result.items.first?.sourceIndex, 0)
        XCTAssertEqual(result.skipped.empty["test.app"], 1)
        XCTAssertEqual(result.items.first?.section, .visible)
    }

    func testUnreliableOverflowPreservesZeroWidthItemsAndCachedPlacement() {
        let key = MenuItemKey(owner: "test.app", token: "solo")
        let result = InventoryBuilder.build(raw: [item(x: -100, width: 0, onScreen: false)], dividers: .init(layout: layout, framesAreReliable: false), cached: .init(sections: [key: .stash], positions: [key: 40]))
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.section, .stash)
        XCTAssertEqual(result.items.first?.frame.minX, 40)
        XCTAssertTrue(result.reliablySectioned.isEmpty)
        XCTAssertTrue(result.skipped.empty.isEmpty)
    }

    func testOwnDividerOverlapDoesNotOverwriteCachedSection() {
        let key = MenuItemKey(owner: "test.app", token: "solo")
        let result = InventoryBuilder.build(raw: [item(x: 200)], dividers: .init(layout: layout, ownFrames: [CGRect(x: 190, y: 0, width: 40, height: 20)]), cached: .init(sections: [key: .hidden], positions: [key: 150]))
        XCTAssertEqual(result.items.first?.frame.minX, 150)
        XCTAssertEqual(result.items.first?.section, .hidden)
        XCTAssertEqual(result.cached.sections[key], .hidden)
        XCTAssertTrue(result.reliablySectioned.isEmpty)
    }

    func testReliableScanUpdatesAllSectionsAndCache() {
        let raw = [item(x: 300, identifier: "visible"), item(x: 150, identifier: "hidden"), item(x: 40, identifier: "stash")]
        let result = InventoryBuilder.build(raw: raw, dividers: .init(layout: layout), cached: .init())
        XCTAssertEqual(result.items.map(\.section), [.stash, .hidden, .visible])
        XCTAssertEqual(result.reliablySectioned.count, 3)
        XCTAssertEqual(result.cached.positions[result.items[0].key], 40)
        XCTAssertEqual(result.items.map(\.sourceIndex), [2, 1, 0])
    }

    func testHostedDuplicatesLeaveOriginalPayloadIndex() {
        let raw = [item("com.apple.controlcenter", x: 300, identifier: "test.app"), item(x: 300)]
        let result = InventoryBuilder.build(raw: raw, dividers: .init(layout: layout), cached: .init())
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.sourceIndex, 1)
        XCTAssertEqual(result.skipped.duplicates["com.apple.controlcenter"], 1)
    }

    func testMissingDividersKeepsSectionButAcceptsReliablePosition() {
        let key = MenuItemKey(owner: "test.app", token: "solo")
        let result = InventoryBuilder.build(raw: [item(x: 300)], dividers: .init(layout: nil), cached: .init(sections: [key: .stash], positions: [key: 40]))
        XCTAssertEqual(result.items.first?.section, .stash)
        XCTAssertEqual(result.cached.positions[key], 300)
        XCTAssertTrue(result.reliablySectioned.isEmpty)
    }
}
