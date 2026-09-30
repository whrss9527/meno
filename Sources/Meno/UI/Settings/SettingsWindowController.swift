import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case layout
    case appearance
    case hotkeys
    case rules
    case scenes
    case markers
    case insights
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .layout: return String(localized: "Layout")
        case .appearance: return String(localized: "Appearance")
        case .hotkeys: return String(localized: "Hotkeys")
        case .rules: return String(localized: "Rules")
        case .scenes: return String(localized: "Scenes")
        case .markers: return String(localized: "Markers")
        case .insights: return String(localized: "Insights")
        case .permissions: return String(localized: "Permissions")
        case .about: return String(localized: "About")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return String(localized: "How hidden items appear and disappear.")
        case .layout: return String(localized: "Choose which items stay in the menu bar and which ones Meno tucks away.")
        case .appearance: return String(localized: "The Meno icon, the Shelf and the look of the menu bar.")
        case .hotkeys: return String(localized: "Keyboard shortcuts that work in every app.")
        case .rules: return String(localized: "Let the menu bar adapt to what you are doing.")
        case .scenes: return String(localized: "Save arrangements and switch between them.")
        case .markers: return String(localized: "Spaces, lines and labels to group your items.")
        case .insights: return String(localized: "How you use the menu bar, measured on this Mac only.")
        case .permissions: return String(localized: "What Meno needs, and why.")
        case .about: return String(localized: "A calm menu bar, made with glass.")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .layout: return "rectangle.3.group"
        case .appearance: return "paintpalette"
        case .hotkeys: return "command"
        case .rules: return "wand.and.stars"
        case .scenes: return "square.stack.3d.up"
        case .markers: return "rectangle.split.3x1"
        case .insights: return "chart.bar.xaxis"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

/// Hosts the settings window.
@MainActor
final class SettingsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    unowned let model: AppModel

    @Published var pane: SettingsPane = .general

    private var window: NSWindow?
    /// The app to bring back when Settings closes: the one used last.
    private var previousApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != AppInfo.ownPID else { return }
            MainActor.assumeIsolated {
                self?.previousApp = app
            }
        }
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(pane: SettingsPane? = nil) {
        if let pane {
            self.pane = pane
        }
        let window = self.window ?? makeWindow()
        if !NSApp.isActive, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != AppInfo.ownPID {
            previousApp = front
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task {
            await model.inventory.refresh()
            model.images.refresh(for: model.inventory.items, captureAllowed: model.permissions.canCapture, renew: true)
        }
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(controller: self)
            .environmentObject(model)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = String(localized: "Meno Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Dragging the background would move the window instead of the items
        // in the Layout pane; the window still moves by its title bar.
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 560)
        window.setContentSize(NSSize(width: 940, height: 660))
        window.center()
        window.setFrameAutosaveName("MenoSettingsWindow")
        window.delegate = self
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.reveal.scheduleRehide()
        guard !model.onboarding.isVisible, let previousApp, !previousApp.isTerminated else { return }
        self.previousApp = nil
        NSApp.yieldActivation(to: previousApp)
        _ = previousApp.activate(options: [])
    }
}
