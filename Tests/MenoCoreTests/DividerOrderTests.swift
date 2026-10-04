import XCTest
@testable import MenoCore

final class DividerOrderTests: XCTestCase {
    private func span(_ end: Double) -> HorizontalSpan { HorizontalSpan(minX: end - 20, maxX: end) }

    func testRepairPriorityAndMissingFrames() {
        let cases: [(DividerOrder.Frames, DividerOrder.Repair?, Bool)] = [
            (.init(hidden: nil), nil, false),
            (.init(hidden: span(100), stash: span(50), toggle: span(150)), nil, true),
            (.init(hidden: span(200), stash: span(250), toggle: span(150)), .hidden, false),
            (.init(hidden: span(100), stash: span(120), toggle: span(150)), .stash, false),
            (.init(hidden: span(100), stash: span(100), toggle: span(100)), nil, true),
            (.init(hidden: span(200), toggle: span(150), toggleExists: false), nil, true),
            (.init(hidden: span(100)), nil, true),
            (.init(hidden: HorizontalSpan(minX: -10000, maxX: 100), stash: span(50), toggle: span(150)), nil, true)
        ]
        for (frames, expected, ordered) in cases {
            XCTAssertEqual(DividerOrder.repair(frames: frames), expected)
            XCTAssertEqual(DividerOrder.isInOrder(frames: frames), ordered)
        }
    }
}
