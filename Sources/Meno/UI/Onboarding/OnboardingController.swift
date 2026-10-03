import AppKit
import SwiftUI

/// Shows the welcome window on first launch.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    unowned let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        let window = self.window ?? makeWindow()
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let view = OnboardingView(permissions: model.permissions) { [weak self] openLayout in
            guard let self else { return }
            self.model.completeOnboarding()
            // Settings opens first, so closing this window does not hide Meno
            // on its way there.
            if openLayout {
                self.model.openSettings(.layout)
            }
            self.close()
        }
        .environmentObject(model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: view)
        window.title = String(localized: "Welcome to Meno")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 680, height: 540))
        window.delegate = self
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.completeOnboarding()
        if !model.settingsWindow.isVisible {
            NSApp.hide(nil)
        }
    }
}
