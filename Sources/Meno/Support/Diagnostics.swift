import AppKit
import MenoCore

/// A plain-text report of what Meno sees, for bug reports. It stays on the
/// Mac unless the person pastes it somewhere.
@MainActor
enum Diagnostics {
    static func report(for model: AppModel) -> String {
        let state = model.statusBar.state
        var lines = [
            "Meno \(AppInfo.version) (\(AppInfo.build)) · signed \(CodeSigning.isAdHoc ? "ad hoc" : "with a certificate")"
                + " · \((Bundle.main.bundlePath as NSString).abbreviatingWithTildeInPath)",
            "macOS \(AppInfo.osVersionString) · \(architecture) · \(Locale.current.identifier)"
                + " · interface \(InterfaceLanguageSetting.current.rawValue)",
            "Engine: \(model.statusBar.engine)\(model.statusBar.engineFallback == nil ? "" : " (switched)")"
                + " · hiding verified \(hidingVerified(model.statusBar))"
                + " · hidden \(state.hiddenCollapsed ? "collapsed" : "shown")"
                + " · stash \(state.stashCollapsed ? "collapsed" : "shown") · zen \(state.zen ? "on" : "off")",
            "Accessibility: \(model.permissions.accessibility ? "granted" : "missing")"
                + " · Screen Recording: \(model.permissions.screenRecording ? "granted" : "missing")",
            "Reveal: \(model.settings.general.revealStyle.rawValue)"
                + " · keeps sections \(model.settings.general.keepsSections ? "on" : "off")"
                + " · tint \(model.settings.tint.enabled ? model.settings.tint.colorSource.rawValue : "off")",
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
        rules += " · capture listeners \(automation.captureListenerCount)"
        lines.append(rules)
        if !model.settings.groups.isEmpty {
            lines.append("Groups: " + model.settings.groups.map { group in
                "\(group.name) (\(group.items.count) items, icon \(describe(model.statusBar.groupIconFrame(group.id).map(ScreenGeometry.quartzRect(fromCocoa:)))))"
            }.joined(separator: ", "))
        }
        let itemsDisplay = model.statusBar.screen.flatMap(ScreenGeometry.displayID(of:))
        for screen in NSScreen.screens {
            let frame = screen.frame
            let menuBarHeight = Int(frame.maxY - screen.visibleFrame.maxY)
            let notch = screen.safeAreaInsets.top > 0 ? "notch" : "no notch"
            let items = ScreenGeometry.displayID(of: screen) == itemsDisplay ? " · items here" : ""
            lines.append("Screen: \(Int(frame.width))×\(Int(frame.height)) @\(screen.backingScaleFactor)x · menu bar \(menuBarHeight) pt · \(notch)"
                + (ScreenGeometry.isBuiltIn(screen) ? " · built in" : "") + items)
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

    /// Whether hiding was seen to work: yes, no, not yet, or not checked
    /// with the stepped engine.
    private static func hidingVerified(_ statusBar: StatusBarController) -> String {
        guard statusBar.engine == .wide else { return "not checked" }
        switch statusBar.hidingCheck.verdict {
        case .verified: return "yes"
        case .failed: return "no"
        case .unknown: return "not yet"
        }
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

extension Diagnostics {
    /// Whether Meno prints what it does to standard error, for a script that
    /// measures it, as CI does. Set `MENO_DIAG=1` in its environment.
    static let printsEvents = ProcessInfo.processInfo.environment["MENO_DIAG"] == "1"

    /// Prints a line starting with `MENO_DIAG` to standard error when
    /// `printsEvents`.
    static func event(_ line: @autoclosure () -> String) {
        guard printsEvents else { return }
        FileHandle.standardError.write(Data("MENO_DIAG \(line())\n".utf8))
    }

    private static var reportSignal: DispatchSourceSignal?

    /// With `printsEvents`, prints the report again on SIGUSR1, after a
    /// fresh scan, for scripts that check what Meno sees.
    static func printReportsOnSignal(for model: AppModel) {
        guard printsEvents, reportSignal == nil else { return }
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak model] in
            MainActor.assumeIsolated {
                guard let model else { return }
                Task {
                    await model.inventory.refresh()
                    event("report\n" + report(for: model))
                }
            }
        }
        source.resume()
        reportSignal = source
    }

    /// The memory Meno takes up, in kilobytes, as Activity Monitor counts it.
    static var physicalFootprint: UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint / 1024
    }
}
