import Foundation

/// Only completed scans of an unchanged window snapshot may be reused.
public struct MenuBarScanGate: Sendable {
    public struct Window: Hashable, Sendable {
        public let id: UInt32
        public let pid: Int32
        public let x, y, width, height: Double
        public init(id: UInt32, pid: Int32, x: Double, y: Double, width: Double, height: Double) {
            self.id = id; self.pid = pid
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }
    public typealias Snapshot = Set<Window>
    private var completed: Snapshot?
    public init() {}
    public func needsScan(_ snapshot: Snapshot?) -> Bool {
        guard let snapshot, let completed else { return true }
        return snapshot != completed
    }
    public mutating func scanned(before: Snapshot?, after: Snapshot?) {
        completed = before == after ? after : nil
    }
}
