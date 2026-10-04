import XCTest
@testable import MenoCore

final class MenuBarScanGateTests: XCTestCase {
    private func window(_ id: UInt32 = 1, pid: Int32 = 2, x: Double = 10, width: Double = 20, isOnScreen: Bool = true) -> MenuBarScanGate.Window {
        .init(id: id, pid: pid, x: x, y: 0, width: width, height: 24, isOnScreen: isOnScreen)
    }
    func testOnlyStableCompletedScansCanBeSkipped() {
        var gate = MenuBarScanGate()
        let snapshot: MenuBarScanGate.Snapshot = [window()]
        XCTAssertTrue(gate.needsScan(snapshot))
        gate.scanned(before: snapshot, after: snapshot)
        XCTAssertFalse(gate.needsScan(snapshot))
        XCTAssertTrue(gate.needsScan(nil))
        for changed: MenuBarScanGate.Snapshot in [[window(), window(3)], [], [window(pid: 3)], [window(x: 30)], [window(width: 30)], [window(4)], [window(isOnScreen: false)]] {
            XCTAssertTrue(gate.needsScan(changed))
        }
    }
    func testChangingOrUnavailableSnapshotsInvalidatePreviousScan() {
        var gate = MenuBarScanGate()
        let a: MenuBarScanGate.Snapshot = [window()]
        let b: MenuBarScanGate.Snapshot = [window(x: 30)]
        gate.scanned(before: a, after: b)
        XCTAssertTrue(gate.needsScan(a))
        XCTAssertTrue(gate.needsScan(b))
        gate.scanned(before: nil, after: a)
        XCTAssertTrue(gate.needsScan(a))
        gate.scanned(before: nil, after: nil)
        XCTAssertTrue(gate.needsScan([]))
        gate.scanned(before: [], after: [])
        XCTAssertFalse(gate.needsScan([]))
    }
}
