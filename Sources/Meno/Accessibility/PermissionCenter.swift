import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

/// Tracks the privacy permissions Meno uses.
///
/// - Accessibility (required) to read menu bar items, open them and move them.
/// - Screen Recording (optional) to show the real artwork of hidden items.
@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var screenRecording = CGPreflightScreenCaptureAccess()
    /// Set once Screen Recording was granted while Meno was running; macOS
    /// applies it only after a relaunch.
    @Published private(set) var screenRecordingNeedsRelaunch = false
    /// Whether Accessibility was granted at some point before.
    @Published private(set) var accessibilityWasGranted = UserDefaults.standard.bool(forKey: PermissionCenter.grantedKey)

    private var pollTask: Task<Void, Never>?
    private var activeObserver: NSObjectProtocol?
    private let grantedAtLaunch = CGPreflightScreenCaptureAccess()
    private static let grantedKey = "AccessibilityWasGranted"

    /// Accessibility was granted before but no longer applies. After an
    /// update, System Settings keeps the old entry switched on, but it
    /// belongs to the previous build.
    var needsAccessibilityAgain: Bool {
        !accessibility && accessibilityWasGranted
    }

    var onAccessibilityGranted: (() -> Void)?

    func startMonitoring() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                // Quick while Accessibility is missing, so that granting it
                // takes effect at once. Otherwise this only notices changes
                // made in System Settings, which also show when Meno comes
                // to the front.
                let seconds: UInt64 = self.accessibility ? 10 : 1
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000 + 500_000_000)
            }
        }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibility {
            accessibility = trusted
            if trusted { onAccessibilityGranted?() }
        }
        if trusted, !accessibilityWasGranted {
            accessibilityWasGranted = true
            UserDefaults.standard.set(true, forKey: Self.grantedKey)
        }
        let capture = CGPreflightScreenCaptureAccess()
        if capture != screenRecording {
            screenRecording = capture
        }
        screenRecordingNeedsRelaunch = capture && !grantedAtLaunch
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            open(.accessibility)
        }
    }

    /// Removes Meno's entry from the Accessibility list and asks again, so
    /// macOS adds the current build. Returns whether the entry was removed.
    func resetAccessibility() async -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let removed = await Self.run("/usr/bin/tccutil", arguments: ["reset", "Accessibility", bundleID])
        requestAccessibility()
        return removed
    }

    private static func run(_ path: String, arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            open(.screenRecording)
        }
    }

    enum Pane {
        case accessibility
        case screenRecording
    }

    func open(_ pane: Pane) {
        let anchor: String
        switch pane {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
