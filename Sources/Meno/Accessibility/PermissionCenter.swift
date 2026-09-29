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

    private var pollTask: Task<Void, Never>?
    private let grantedAtLaunch = CGPreflightScreenCaptureAccess()

    var onAccessibilityGranted: (() -> Void)?

    func startMonitoring() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibility {
            accessibility = trusted
            if trusted { onAccessibilityGranted?() }
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
