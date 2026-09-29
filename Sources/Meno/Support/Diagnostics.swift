import AppKit
import MenoCore

/// A plain-text report of what Meno sees, for bug reports. It stays on the
/// Mac unless the person pastes it somewhere.
@MainActor
enum Diagnostics {
    static func report(for model: AppModel) -> String {
        let state = model.statusBar.state
        var lines = [
            "Meno \(AppInfo.version) (\(AppInfo.build))",
            "macOS \(AppInfo.osVersionString) · \(architecture) · \(Locale.current.identifier)",
            "Engine: \(model.statusBar.engine) · hidden \(state.hiddenCollapsed ? "collapsed" : "shown")"
                + " · stash \(state.stashCollapsed ? "collapsed" : "shown") · zen \(state.zen ? "on" : "off")",
            "Accessibility: \(model.permissions.accessibility ? "granted" : "missing")"
                + " · Screen Recording: \(model.permissions.screenRecording ? "granted" : "missing")",
        ]
        let automation = model.automation
        var rules = "Rules: \(model.settings.rules.count), \(automation.activeRuleIDs.count) active"
            + " · Low Power Mode \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")"
        if automation.watchesCaptureActivity {
            let capture = automation.capture
            rules += " · microphone \(capture.microphone ? "in use" : "idle")"
            if !capture.microphoneUsers.isEmpty {
                rules += " (\(capture.microphoneUsers.joined(separator: ", ")))"
            }
            rules += " · camera \(capture.camera ? "in use" : "idle")"
        }
        lines.append(rules)
        if !model.settings.groups.isEmpty {
            lines.append("Groups: " + model.settings.groups.map { group in
                "\(group.name) (\(group.items.count) items, icon \(describe(model.statusBar.groupIconFrame(group.id).map(ScreenGeometry.quartzRect(fromCocoa:)))))"
            }.joined(separator: ", "))
        }
        for screen in NSScreen.screens {
            let frame = screen.frame
            let menuBarHeight = Int(frame.maxY - screen.visibleFrame.maxY)
            let notch = screen.safeAreaInsets.top > 0 ? "notch" : "no notch"
            lines.append("Screen: \(Int(frame.width))×\(Int(frame.height)) @\(screen.backingScaleFactor)x · menu bar \(menuBarHeight) pt · \(notch)")
        }
        lines.append("Meno icon \(describe(model.statusBar.toggleFrame))"
            + " · hidden divider \(describe(model.statusBar.hiddenDividerFrame))"
            + " · stash divider \(describe(model.statusBar.stashDividerFrame))")
        let skipped = model.inventory.skipped
        for (label, counts) in [("unnamed", skipped.unnamed), ("duplicate", skipped.duplicates), ("empty", skipped.empty)] where !counts.isEmpty {
            lines.append("Skipped \(label) elements: " + counts.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
        }
        let items = model.inventory.items
        lines.append("Items (\(items.count)):")
        for item in items {
            var flags: [String] = []
            if !item.isMovable { flags.append("fixed") }
            if !item.isOnScreen { flags.append("off screen") }
            if item.kind == .marker { flags.append("marker") }
            let section = item.section.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
            lines.append("  \(section) \(describe(item.frame)) \(item.key.rawValue) “\(item.displayName)”"
                + (flags.isEmpty ? "" : " [\(flags.joined(separator: ", "))]"))
        }
        return lines.joined(separator: "\n")
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private static func describe(_ frame: CGRect?) -> String {
        guard let frame else { return "none" }
        return "x=\(Int(frame.minX)) w=\(Int(frame.width))"
    }
}
