import AppKit
import IOKit.ps
import MenoCore

/// Collects the state that rules are evaluated against.
enum SystemSignals {
    @MainActor
    static func snapshot(isOnline: Bool) -> RuleContext {
        let workspace = NSWorkspace.shared
        let running = Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
        let power = PowerSource.current()
        let externalDisplays = NSScreen.screens.filter { !ScreenGeometry.isBuiltIn($0) }.count
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return RuleContext(
            frontmostBundleID: workspace.frontmostApplication?.bundleIdentifier,
            runningBundleIDs: running,
            isOnBattery: power.onBattery,
            batteryLevel: power.level,
            externalDisplayCount: externalDisplays,
            minuteOfDay: (now.hour ?? 0) * 60 + (now.minute ?? 0),
            isOnline: isOnline
        )
    }
}

enum PowerSource {
    /// Whether the Mac runs on its internal battery, and its charge.
    static func current() -> (onBattery: Bool, level: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return (false, nil)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery" else { continue }
            let onBattery = description["Power Source State"] as? String == "Battery Power"
            var level: Int?
            if let current = description["Current Capacity"] as? Int,
               let maximum = description["Max Capacity"] as? Int, maximum > 0 {
                level = Int((Double(current) / Double(maximum) * 100).rounded())
            }
            return (onBattery, level)
        }
        return (false, nil)
    }
}
